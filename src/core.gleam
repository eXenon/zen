import gleam/dict
import gleam/dynamic
import gleam/json
import gleam/list
import gleam/option
import gleam/result
import gleam/string_builder
import gluid

pub fn uuid() -> String {
  gluid.guidv4()
}

pub type Msg(msg) {
  Custom(msg)
  NoOp
  Navigate(String)
}

pub type EventHandler(msg) {
  Click(fn() -> msg)
  MouseOver(fn(#(Int, Int)) -> msg)
}

pub type EventHandlerError {
  DecodeError
}

pub fn event_payload_decoder(
  handler: EventHandler(msg),
  payload: dynamic.Dynamic,
) -> Result(msg, EventHandlerError) {
  case handler {
    Click(handler) -> Ok(handler())
    MouseOver(handler) ->
      case dynamic.tuple2(dynamic.int, dynamic.int)(payload) {
        Ok(#(x, y)) -> Ok(handler(#(x, y)))
        Error(_) -> Error(DecodeError)
      }
  }
}

pub type Event(msg) {
  Event(id: String, handler: EventHandler(msg))
}

pub fn event_name(name: Event(msg)) -> String {
  case name.handler {
    Click(_) -> "click"
    MouseOver(_) -> "mouseover"
  }
}

pub type DomNode(msg) {
  Element(
    node: String,
    attributes: List(#(String, String)),
    children: List(DomNode(msg)),
    events: List(Event(msg)),
  )
  Text(String)
}

pub type View(msg) {
  View(title: String, body: DomNode(msg))
}

pub type App(model, msg) {
  App(
    init: fn() -> model,
    update: fn(model, Msg(msg)) -> model,
    view: fn(model) -> View(Msg(msg)),
    events: dict.Dict(String, EventHandler(Msg(msg))),
  )
}

pub fn deserialize(app: App(model, msg), raw: String) -> option.Option(Msg(msg)) {
  let decoder =
    dynamic.decode2(
      fn(id, payload) {
        let stored = dict.get(app.events, id)
        use handler <- result.try(stored)
        event_payload_decoder(handler, payload)
        |> result.nil_error
      },
      dynamic.field("handler", dynamic.string),
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
  App(init, update, view, dict.from_list([]))
}

pub fn render_attribute(
  attribute: #(String, String),
) -> string_builder.StringBuilder {
  let #(name, value) = attribute
  string_builder.concat([
    string_builder.from_string(name),
    string_builder.from_string("=\""),
    string_builder.from_string(value),
    string_builder.from_string("\""),
  ])
}

pub fn render_event(event: Event(msg)) -> string_builder.StringBuilder {
  string_builder.concat([
    string_builder.from_string("data-event=\""),
    string_builder.from_string(event_name(event)),
    string_builder.from_string("\" data-event-handler=\""),
    string_builder.from_string(event.id),
    string_builder.from_string("\""),
  ])
}

pub fn render_node(node: DomNode(msg)) -> string_builder.StringBuilder {
  case node {
    Element(node, attributes, children, events) ->
      string_builder.concat([
        string_builder.from_string("<"),
        string_builder.from_string(node),
        string_builder.from_string(" "),
        string_builder.concat(list.map(attributes, render_attribute)),
        string_builder.from_string(" "),
        string_builder.concat(list.map(events, render_event)),
        string_builder.from_string(">"),
        string_builder.concat(list.map(children, render_node)),
        string_builder.from_string("</"),
        string_builder.from_string(node),
        string_builder.from_string(">"),
      ])
    Text(text) -> string_builder.from_string(text)
  }
}

pub fn render(view: View(msg)) -> string_builder.StringBuilder {
  let View(title, body) = view
  string_builder.concat([
    prefix(),
    string_builder.from_string(title),
    middle(),
    render_node(body),
    suffix(),
  ])
}

pub fn all_events(node: DomNode(msg)) -> List(Event(msg)) {
  case node {
    Element(_, _, children, events) ->
      list.concat([events, list.concat(list.map(children, all_events))])
    Text(_) -> []
  }
}

pub fn build_view(
  app: App(model, msg),
  model: model,
) -> #(App(model, msg), View(Msg(msg))) {
  let view = app.view(model)
  let events = all_events(view.body)
  let registry =
    dict.from_list(list.map(events, fn(event) { #(event.id, event.handler) }))
  #(App(..app, events: registry), view)
}

pub fn update(app: App(model, msg), model: model, msg: Msg(msg)) -> model {
  app.update(model, msg)
}
