import gleam/dict
import gleam/dynamic
import gleam/erlang/node
import gleam/function
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/otp/intensity_tracker
import gleam/result
import gleam/string
import gleam/string_builder
import gluid
import utils

// Types

pub type Id {
  Root
  Node(List(Int))
}

pub fn root() -> Id {
  Root
}

pub fn child(parent: Id, index: Int) -> Id {
  case parent {
    Root -> Node([index])
    Node(p) -> Node([index, ..p])
  }
}

pub fn parent(child: Id) -> Id {
  case child {
    Root -> Root
    Node([_, ..parent_path]) -> Node(parent_path)
    Node([]) -> Root
  }
}

pub fn encode_id(id: Id) -> json.Json {
  case id {
    Root -> json.string("root")
    Node(path) -> json.array(path, json.int)
  }
}

pub fn print_id(id: Id) -> String {
  case id {
    Root -> "root"
    Node(path) -> string.join(list.map(path, int.to_string), "-")
  }
}

pub fn id_decoder() {
  dynamic.any([
    fn(d) {
      dynamic.string(d)
      |> result.try(fn(s) {
        case s {
          "root" -> Ok(Root)
          _ ->
            Error([dynamic.DecodeError(expected: "root", found: s, path: [])])
        }
      })
    },
    fn(d) {
      dynamic.list(of: dynamic.int)(d)
      |> result.map(Node)
    },
  ])
}

pub type Node {
  N(String)
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

// DOM elements with attached IDs

pub type DomNodeWithId(msg) {
  ElementWI(
    id: Id,
    node: Node,
    attributes: List(Attribute),
    children: List(DomNodeWithId(msg)),
    events: dict.Dict(String, EventHandler(msg)),
  )
  TextWI(Id, String)
}

pub fn assign_ids(current_id: Id, node: DomNode(msg)) -> DomNodeWithId(msg) {
  case node {
    Element(n, a, c, e) ->
      ElementWI(
        id: current_id,
        node: n,
        attributes: a,
        children: list.index_map(c, fn(c, idx) {
          assign_ids(child(current_id, idx), c)
        }),
        events: e,
      )
    Text(t) -> TextWI(current_id, t)
  }
}

pub fn id_of(node: DomNodeWithId(msg)) -> Id {
  case node {
    ElementWI(i, _, _, _, _) -> i
    TextWI(i, _) -> i
  }
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

// Rendering logic

pub fn render_attribute(attribute: Attribute) -> string_builder.StringBuilder {
  let Attribute(name, value) = attribute
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

pub fn render_node(node: DomNodeWithId(msg)) -> string_builder.StringBuilder {
  case node {
    ElementWI(id, N(node), attributes, children, events) ->
      string_builder.concat([
        string_builder.from_string("<"),
        string_builder.from_string(node),
        string_builder.from_string(" id=\""),
        string_builder.from_string(print_id(id)),
        string_builder.from_string("\" "),
        string_builder.concat(list.map(attributes, render_attribute)),
        string_builder.from_string(" "),
        string_builder.concat(list.map(dict.keys(events), render_event)),
        string_builder.from_string(">"),
        string_builder.concat(list.map(children, render_node)),
        string_builder.from_string("</"),
        string_builder.from_string(node),
        string_builder.from_string(">"),
      ])
    TextWI(_, text) -> string_builder.from_string(text)
  }
}

// Diff logic

pub type Diff(msg) {
  Update(selector: Id, inner: DomNodeWithId(msg))
  UpdateText(selector: Id, text: String)
  Append(selector: Id, inner: DomNodeWithId(msg))
  Prepend(selector: Id, inner: DomNodeWithId(msg))
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
  old: List(DomNodeWithId(msg)),
  new: List(DomNodeWithId(msg)),
) -> List(Diff(msg)) {
  let diff_children_helper = fn(
    input: #(Int, Option(DomNodeWithId(msg)), Option(DomNodeWithId(msg))),
  ) -> List(Diff(msg)) {
    let #(idx, old, new) = input
    let current_id = child(parent_id, idx)
    case old, new {
      None, None -> []
      None, Some(new) -> [Append(parent_id, new)]
      Some(old), None -> [Delete(id_of(old))]
      Some(old), Some(new) -> {
        diff(current_id, old, new)
      }
    }
  }

  utils.extzipmap(old, new) |> list.map(diff_children_helper) |> list.concat
}

pub fn diff(
  parent_id: Id,
  old: DomNodeWithId(msg),
  new: DomNodeWithId(msg),
) -> List(Diff(msg)) {
  case old, new {
    TextWI(_, t1), TextWI(_, t2) if t1 == t2 -> []
    TextWI(_, _), TextWI(_, t2) -> [UpdateText(parent_id, t2)]
    ElementWI(_, node1, attributes1, children1, events1),
      ElementWI(new_id, node2, attributes2, children2, events2)
      if node1 == node2
    -> {
      let attribute_diffs = diff_attributes(parent_id, attributes1, attributes2)
      let event_diffs = diff_events(parent_id, events1, events2)
      let child_diffs = diff_children(new_id, children1, children2)
      list.concat([attribute_diffs, event_diffs, child_diffs])
    }
    _, _ -> [Update(parent_id, new)]
  }
}

pub fn encode(diff: Diff(msg)) -> json.Json {
  case diff {
    Update(selector, inner) ->
      json.object([
        #("action", json.string("update")),
        #("selector", encode_id(selector)),
        #("value", json.string(string_builder.to_string(render_node(inner)))),
      ])
    Append(selector, inner) ->
      json.object([
        #("action", json.string("append")),
        #("selector", encode_id(selector)),
        #("value", json.string(string_builder.to_string(render_node(inner)))),
      ])
    Prepend(selector, inner) ->
      json.object([
        #("action", json.string("prepend")),
        #("selector", encode_id(selector)),
        #("value", json.string(string_builder.to_string(render_node(inner)))),
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
    UpdateText(selector, text) ->
      json.object([
        #("action", json.string("updatetext")),
        #("selector", encode_id(selector)),
        #("value", json.string(text)),
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
  Element(N("div"), attributes, children, dict.from_list([]))
}

pub fn button(
  attributes: List(Attribute),
  children: List(DomNode(msg)),
) -> DomNode(msg) {
  Element(N("button"), attributes, children, dict.from_list([]))
}

pub fn text(text: String) -> DomNode(msg) {
  Text(text)
}
