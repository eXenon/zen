import gleam/dict
import gleam/dynamic
import gleam/erlang/node
import gluid

// Types

pub type Id {
  Id(String)
}

pub type Node {
  Node(String)
}

pub type Attribute {
  Attribute(name: String, value: String)
}

pub type DomNode(msg) {
  Element(
    id: Id,
    node: Node,
    attributes: List(Attribute),
    children: List(DomNode(msg)),
    events: dict.Dict(String, EventHandler(msg)),
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

pub type EventStore(msg) {
  EventStore(dict.Dict(Id, dict.Dict(String, EventHandler(msg))))
}

pub fn empty_event_store() -> EventStore(msg) {
  EventStore(dict.from_list([]))
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

pub fn on_click(node: DomNode(msg), handler: fn() -> msg) -> DomNode(msg) {
  case node {
    Element(i, n, a, c, e) ->
      Element(
        id: i,
        node: n,
        attributes: a,
        children: c,
        events: dict.insert(e, "click", Click(handler)),
      )
    Text(_) -> node
  }
}

pub fn on_mouse_over(
  node: DomNode(msg),
  handler: fn(EventPayloadCoordinates) -> msg,
) -> DomNode(msg) {
  case node {
    Element(i, n, a, c, e) ->
      Element(
        id: i,
        node: n,
        attributes: a,
        children: c,
        events: dict.insert(e, "mouseover", MouseOver(handler)),
      )
    Text(_) -> node
  }
}

// Convenience functions

pub fn div(
  attributes: List(Attribute),
  children: List(DomNode(msg)),
) -> DomNode(msg) {
  let id = Id(gluid.guidv4())
  Element(id, Node("div"), attributes, children, dict.from_list([]))
}

pub fn button(
  attributes: List(Attribute),
  children: List(DomNode(msg)),
) -> DomNode(msg) {
  let id = Id(gluid.guidv4())
  Element(id, Node("button"), attributes, children, dict.from_list([]))
}

pub fn text(text: String) -> DomNode(msg) {
  Text(text)
}
