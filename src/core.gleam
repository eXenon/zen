import gleam/dict
import gleam/dynamic
import gleam/json
import gleam/list
import gleam/option
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

pub type DomNode(msg) {
  Element(
    node: String,
    attributes: List(#(String, String)),
    children: List(DomNode(msg)),
    events: List(#(String, String, fn() -> Msg(msg))),
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
    view: fn(model) -> View(msg),
    events: dict.Dict(String, fn() -> Msg(msg)),
  )
}

pub fn deserialize(app: App(model, msg), raw: String) -> option.Option(Msg(msg)) {
  let decoder =
    dynamic.decode1(
      fn(id) {
        let stored = dict.get(app.events, id)
        case stored {
          Ok(handler) -> handler()
          Error(_) -> NoOp
        }
      },
      dynamic.field("handler", dynamic.string),
    )
  json.decode(using: decoder, from: raw)
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

pub fn render_event(
  event: #(String, String, fn() -> Msg(msg)),
) -> string_builder.StringBuilder {
  let #(name, id, _handler) = event
  string_builder.concat([
    string_builder.from_string("data-event=\""),
    string_builder.from_string(name),
    string_builder.from_string("\" data-event-handler=\""),
    string_builder.from_string(id),
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

pub fn all_events(
  node: DomNode(msg),
) -> List(#(String, String, fn() -> Msg(msg))) {
  case node {
    Element(_, _, children, events) ->
      list.concat([events, list.concat(list.map(children, all_events))])
    Text(_) -> []
  }
}

pub fn build_view(
  app: App(model, msg),
  model: model,
) -> #(App(model, msg), View(msg)) {
  let view = app.view(model)
  let events = all_events(view.body)
  let registry =
    dict.from_list(
      list.map(events, fn(event) {
        let #(_name, id, handler) = event
        #(id, handler)
      }),
    )
  #(App(..app, events: registry), view)
}

pub fn update(app: App(model, msg), model: model, msg: Msg(msg)) -> model {
  app.update(model, msg)
}
