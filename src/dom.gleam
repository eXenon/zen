import gleam/dict
import gleam/dynamic
import gleam/erlang/node
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gluid
import utils

// Types

pub type Id {
  Id(List(Int))
}

pub fn root() -> Id {
  Id([])
}

pub fn child(parent: Id, index: Int) -> Id {
  let Id(parent_id) = parent
  Id([index, ..parent_id])
}

pub fn parent(child: Id) -> Id {
  let Id(child_id) = child
  case child_id {
    [_, ..parent_id] -> Id(parent_id)
    [] -> Id([])
  }
}

pub fn encode_id(id: Id) -> json.Json {
  let Id(id) = id
  json.array(id, json.int)
}

pub type Node {
  Node(String)
}

pub type Attribute {
  Attribute(name: String, value: String)
}

pub type DomNode(msg) {
  Element(
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

// Diff logic

pub type Diff(msg) {
  Update(selector: Id, inner: DomNode(msg))
  Append(selector: Id, inner: DomNode(msg))
  Prepend(selector: Id, inner: DomNode(msg))
  Delete(selector: Id)
  UpdateProperties(selector: Id, properties: List(Attribute))
}

pub fn diff_attributes(
  selector: Id,
  old: List(Attribute),
  new: List(Attribute),
) -> List(Diff(msg)) {
  case old == new {
    True -> []
    False -> [UpdateProperties(selector, new)]
  }
}

pub fn diff_events(
  _selector: Id,
  _old: dict.Dict(String, EventHandler(msg)),
  _new: dict.Dict(String, EventHandler(msg)),
) -> List(Diff(msg)) {
  // TODO
  []
}

pub fn diff_children(
  parent_id: Id,
  old: List(DomNode(msg)),
  new: List(DomNode(msg)),
) -> List(Diff(msg)) {
  let diff_children_helper = fn(
    input: #(Int, Option(DomNode(msg)), Option(DomNode(msg))),
  ) -> List(Diff(msg)) {
    let #(idx, old, new) = input
    let current_id = child(parent_id, idx)
    case old, new {
      None, None -> []
      None, Some(new) -> [Append(parent_id, new)]
      Some(_), None -> [Delete(parent_id)]
      Some(old), Some(new) -> {
        diff(current_id, old, new)
      }
    }
  }

  utils.extzipmap(old, new) |> list.map(diff_children_helper) |> list.concat
}

pub fn diff(
  parent_id: Id,
  old: DomNode(msg),
  new: DomNode(msg),
) -> List(Diff(msg)) {
  case old, new {
    Text(t1), Text(t2) if t1 == t2 -> []
    Text(_), Text(_) -> [Update(parent_id, new)]
    Element(node1, attributes1, children1, events1),
      Element(node2, attributes2, children2, events2)
      if node1 == node2
    -> {
      let attribute_diffs = diff_attributes(parent_id, attributes1, attributes2)
      let event_diffs = diff_events(parent_id, events1, events2)
      let child_diffs = diff_children(parent_id, children1, children2)
      list.concat([attribute_diffs, event_diffs, child_diffs])
    }
    _, _ -> [Update(parent_id, new)]
  }
}

pub fn encode(diff: Diff(msg)) -> json.Json {
  case diff {
    Update(selector, _inner) ->
      json.object([
        #("action", json.string("update")),
        #("selector", encode_id(selector)),
        #("value", json.string("")),
      ])
    Append(selector, _inner) ->
      json.object([
        #("action", json.string("append")),
        #("selector", encode_id(selector)),
        #("value", json.string("")),
      ])
    Prepend(selector, _inner) ->
      json.object([
        #("action", json.string("prepend")),
        #("selector", encode_id(selector)),
        #("value", json.string("")),
      ])
    Delete(selector) ->
      json.object([
        #("action", json.string("delete")),
        #("selector", encode_id(selector)),
      ])
    UpdateProperties(selector, properties) ->
      json.object([
        #("action", json.string("updateproperties")),
        #("selector", encode_id(selector)),
        #(
          "properties",
          json.object(
            list.map(properties, fn(a) {
              let Attribute(name, value) = a
              #(name, json.string(value))
            }),
          ),
        ),
      ])
  }
}

// Builders

pub fn on_click(node: DomNode(msg), handler: fn() -> msg) -> DomNode(msg) {
  case node {
    Element(n, a, c, e) ->
      Element(
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
    Element(n, a, c, e) ->
      Element(
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
  Element(Node("div"), attributes, children, dict.from_list([]))
}

pub fn button(
  attributes: List(Attribute),
  children: List(DomNode(msg)),
) -> DomNode(msg) {
  Element(Node("button"), attributes, children, dict.from_list([]))
}

pub fn text(text: String) -> DomNode(msg) {
  Text(text)
}
