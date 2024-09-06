import dom
import gleam/dict
import gleam/dynamic
import gleam/int
import gleam/io
import gleam/json
import gleam/list
import gleam/option
import gleam/result
import gleam/string_builder

pub type Msg(msg) {
  Custom(msg)
  NoOp
  Navigate(String)
}

pub type View(msg) {
  View(title: String, body: dom.DomNode(msg))
}

pub type Effect(msg) {
  Effect(fn() -> Msg(msg))
}

pub type App(model, msg) {
  App(
    init: fn() -> model,
    update: fn(model, Msg(msg)) -> #(model, List(Effect(msg))),
    view: fn(model) -> View(Msg(msg)),
    events: dom.EventStore(Msg(msg)),
  )
}

pub fn deserialize(app: App(model, msg), raw: String) -> option.Option(Msg(msg)) {
  let decoder =
    dynamic.decode3(
      fn(id, name, payload) {
        let dom.EventStore(events) = app.events
        let stored = dict.get(events, dom.Id(id))
        use events_for_id <- result.try(stored)
        use handler <- result.try(dict.get(events_for_id, name))
        dom.event_payload_decoder(handler, payload)
        |> result.nil_error
      },
      dynamic.field("handler", dynamic.list(dynamic.int)),
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
      <script src=\"/file/frontend/core.js\"></script>
      <title>
  ",
  )
}

pub fn middle() -> string_builder.StringBuilder {
  string_builder.from_string(
    "</title>
    </head>
    <body>
  ",
  )
}

pub fn suffix() -> string_builder.StringBuilder {
  string_builder.from_string(
    "</body>
    </html>",
  )
}

pub fn app(init, update, view) -> App(model, msg) {
  App(init, update, view, dom.empty_event_store())
}

pub fn render_attribute(
  attribute: dom.Attribute,
) -> string_builder.StringBuilder {
  let dom.Attribute(name, value) = attribute
  string_builder.concat([
    string_builder.from_string(name),
    string_builder.from_string("=\""),
    string_builder.from_string(value),
    string_builder.from_string("\""),
  ])
}

pub fn render_event(event_name: String) -> string_builder.StringBuilder {
  string_builder.concat([
    string_builder.from_string("data-event=\""),
    string_builder.from_string(event_name),
    string_builder.from_string("\""),
  ])
}

pub fn render_id(id: dom.Id) -> string_builder.StringBuilder {
  let dom.Id(id) = id
  string_builder.join(
    list.map(id, fn(i) { string_builder.from_string(int.to_string(i)) }),
    "-",
  )
}

pub fn render_node(
  current_id: dom.Id,
  node: dom.DomNode(msg),
) -> string_builder.StringBuilder {
  case node {
    dom.Element(dom.Node(node), attributes, children, events) ->
      string_builder.concat([
        string_builder.from_string("<"),
        string_builder.from_string(node),
        string_builder.from_string(" id=\""),
        render_id(current_id),
        string_builder.from_string("\" "),
        string_builder.concat(list.map(attributes, render_attribute)),
        string_builder.from_string(" "),
        string_builder.concat(list.map(dict.keys(events), render_event)),
        string_builder.from_string(">"),
        string_builder.concat(
          list.index_map(children, fn(n, i) {
            let child_id = dom.child(current_id, i)
            render_node(child_id, n)
          }),
        ),
        string_builder.from_string("</"),
        string_builder.from_string(node),
        string_builder.from_string(">"),
      ])
    dom.Text(text) -> string_builder.from_string(text)
  }
}

pub fn render(view: View(msg)) -> string_builder.StringBuilder {
  let View(title, body) = view
  string_builder.concat([
    prefix(),
    string_builder.from_string(title),
    middle(),
    render_node(dom.root(), body),
    suffix(),
  ])
}

pub fn all_events(
  id: dom.Id,
  node: dom.DomNode(msg),
) -> List(#(dom.Id, dict.Dict(String, dom.EventHandler(msg)))) {
  case node {
    dom.Element(_, _, children, events) -> [
      #(id, events),
      ..list.concat(
        list.index_map(children, fn(n, i) {
          let child_id = dom.child(id, i)
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
  let events = all_events(dom.root(), view.body)
  let registry = dom.EventStore(dict.from_list(events))
  #(App(..app, events: registry), view)
}

pub fn update(
  app: App(model, msg),
  model: model,
  msg: Msg(msg),
) -> #(model, List(Effect(msg))) {
  app.update(model, msg)
}
