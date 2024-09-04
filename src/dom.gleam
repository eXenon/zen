import gleam/dynamic
import gleam/erlang/node
import gluid

// Types

pub type DomNode(msg) {
  Element(
    node: String,
    attributes: List(#(String, String)),
    children: List(DomNode(msg)),
    events: List(Event(msg)),
  )
  Text(String)
}

pub type EventPayloadCoordinates {
  Coordinates(x: Int, y: Int)
}

pub type EventHandler(msg) {
  Click(fn() -> msg)
  MouseOver(fn(EventPayloadCoordinates) -> msg)
}

pub type EventHandlerError {
  DecodeError
}

// Event related functions

pub fn event_payload_decoder(
  handler: EventHandler(msg),
  payload: dynamic.Dynamic,
) -> Result(msg, EventHandlerError) {
  case handler {
    Click(handler) -> Ok(handler())
    MouseOver(handler) ->
      case
        dynamic.decode2(
          Coordinates,
          dynamic.field("x", dynamic.int),
          dynamic.field("y", dynamic.int),
        )(payload)
      {
        Ok(coordinates) -> Ok(handler(coordinates))
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

// Builders

pub fn make_click_event(handler: fn() -> msg) -> Event(msg) {
  let id = gluid.guidv4()
  Event(id, Click(handler))
}

pub fn make_mouse_over_event(
  handler: fn(EventPayloadCoordinates) -> msg,
) -> Event(msg) {
  let id = gluid.guidv4()
  Event(id, MouseOver(handler))
}

pub fn on_click(node: DomNode(msg), handler: fn() -> msg) -> DomNode(msg) {
  case node {
    Element(n, a, c, e) ->
      Element(node: n, attributes: a, children: c, events: [
        make_click_event(handler),
        ..e
      ])
    Text(_) -> node
  }
}

pub fn on_mouse_over(
  node: DomNode(msg),
  handler: fn(EventPayloadCoordinates) -> msg,
) -> DomNode(msg) {
  case node {
    Element(n, a, c, e) ->
      Element(node: n, attributes: a, children: c, events: [
        make_mouse_over_event(handler),
        ..e
      ])
    Text(_) -> node
  }
}

// Convenience functions

pub fn div(
  attributes: List(#(String, String)),
  children: List(DomNode(msg)),
) -> DomNode(msg) {
  Element("div", attributes, children, [])
}

pub fn button(
  attributes: List(#(String, String)),
  children: List(DomNode(msg)),
) -> DomNode(msg) {
  Element("button", attributes, children, [])
}

pub fn text(text: String) -> DomNode(msg) {
  Text(text)
}
