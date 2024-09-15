import gleam/dict
import gleam/dynamic
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string_builder
import zen/dom
import zen/dom/events
import zen/dom/id
import zen/effects

pub type Msg(msg) {
  Custom(msg)
  NoOp
  Navigate(String)
}

pub type View(msg) {
  View(title: String, body: dom.DomNode(msg))
}

pub type App(model, msg) {
  App(
    init: fn() -> model,
    update: fn(model, Msg(msg)) ->
      #(model, List(effects.Effect(Msg(msg), model))),
    view: fn(model) -> View(Msg(msg)),
    events: events.EventStore(Msg(msg)),
  )
}

pub fn deserialize(app: App(model, msg), raw: String) -> option.Option(Msg(msg)) {
  let decoder =
    dynamic.decode3(
      fn(id, name, payload) {
        let events.EventStore(events) = app.events
        let stored = dict.get(events, id)
        use events_for_id <- result.try(stored)
        use handler <- result.try(dom.find_handler_for_event(
          events_for_id,
          name,
        ))
        events.event_payload_decoder(handler, payload)
        |> result.nil_error
      },
      dynamic.field("handler", id.id_decoder()),
      dynamic.field("name", dynamic.string),
      dynamic.field("payload", dynamic.dynamic),
    )

  json.decode(using: decoder, from: raw)
  |> result.nil_error
  |> result.flatten()
  |> option.from_result()
}

pub fn prefix() -> string_builder.StringBuilder {
  string_builder.from_string(
    "<!DOCTYPE html>
  <html lang=\"en\">
    <head>
      <meta charset=\"UTF-8\">
      <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">
      <script src=\"/file/debugger.js\"></script>
      <script src=\"/file/core.js\"></script>
      <title>
  ",
  )
}

pub fn middle(id: String) -> string_builder.StringBuilder {
  string_builder.from_string("</title>
    </head>
    <body data-zen-id=\"" <> id <> "\">
  ")
}

pub fn suffix() -> string_builder.StringBuilder {
  string_builder.from_string(
    "</body>
    </html>",
  )
}

pub fn app(init, update, view) -> App(model, msg) {
  App(init, update, view, events.empty_event_store())
}

pub fn render(id: String, view: View(msg)) -> string_builder.StringBuilder {
  let View(title, body) = view
  string_builder.concat([
    prefix(),
    string_builder.from_string(title),
    middle(id),
    dom.render_node(dom.assign_ids(id.root(), body)),
    suffix(),
  ])
}

pub fn all_events(
  id: id.Id,
  node: dom.DomNode(msg),
) -> List(#(id.Id, events.EventHandlers(msg))) {
  case node {
    dom.Element(_, _, children, events) -> [
      #(id, events),
      ..list.concat(
        list.index_map(children, fn(n, i) {
          let child_id = id.child(id, i)
          all_events(child_id, n)
        }),
      )
    ]
    dom.Text(_) -> []
  }
}

pub fn build_view(
  app: App(model, msg),
  model: model,
) -> #(App(model, msg), View(Msg(msg))) {
  let view = app.view(model)
  let events = all_events(id.root(), view.body)
  let registry = events.EventStore(dict.from_list(events))
  #(App(..app, events: registry), view)
}

pub fn update(
  app: App(model, msg),
  model: model,
  msg: Msg(msg),
) -> #(model, List(effects.Effect(Msg(msg), model))) {
  app.update(model, msg)
}

pub fn diff(view1: View(msg), view2: View(msg)) -> List(dom.Diff(msg)) {
  let View(_, body1) = view1
  let View(_, body2) = view2
  dom.diff(
    id.root(),
    dom.assign_ids(id.root(), body1),
    dom.assign_ids(id.root(), body2),
  )
}

pub fn title_diff(view1: View(msg), view2: View(msg)) -> Option(String) {
  let View(old, _) = view1
  let View(new, _) = view2
  case old, new {
    _, _ if old == new -> None
    _, _ -> Some(new)
  }
}
