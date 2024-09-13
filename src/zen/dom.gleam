import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string_builder
import utils
import zen/dom/attributes.{type Attribute, to_string as attribute_to_string}
import zen/dom/events.{
  type EventHandler, type EventHandlers, type EventPayloadCoordinates, Click,
  MouseOver, event_handler_name, event_handler_names,
}
import zen/dom/id.{type Id, child, encode_id, print_id}

// Types

pub type Node {
  N(String)
}

pub type DomNode(msg) {
  Element(
    node: Node,
    attributes: List(Attribute),
    children: List(DomNode(msg)),
    events: EventHandlers(msg),
  )
  Text(String)
}

// DOM elements with attached IDs

pub type DomNodeWithId(msg) {
  ElementWI(
    id: Id,
    node: Node,
    attributes: List(Attribute),
    children: List(DomNodeWithId(msg)),
    events: EventHandlers(msg),
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

pub fn find_handler_for_event(
  handlers: EventHandlers(msg),
  name: String,
) -> Result(EventHandler(msg), Nil) {
  handlers
  |> list.filter(fn(h) { event_handler_name(h) == name })
  |> list.first
}

// Rendering logic

pub fn render_attribute(attribute: Attribute) -> string_builder.StringBuilder {
  let #(name, value) = attribute_to_string(attribute)
  string_builder.concat([
    string_builder.from_string(name),
    string_builder.from_string("=\""),
    string_builder.from_string(value),
    string_builder.from_string("\""),
  ])
}

pub fn render_events(
  event_handlers: EventHandlers(msg),
) -> string_builder.StringBuilder {
  string_builder.concat([
    string_builder.from_string("data-event=\""),
    string_builder.join(
      list.map(event_handlers, fn(h) {
        h |> event_handler_name |> string_builder.from_string
      }),
      ",",
    ),
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
        render_events(events),
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
  UpdateEvents(selector: Id, event_names: List(String), remove: List(String))
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
  selector: Id,
  old: EventHandlers(msg),
  new: EventHandlers(msg),
) -> List(Diff(msg)) {
  case event_handler_names(old), event_handler_names(new) {
    old_events, new_events if old_events == new_events -> []
    old_events, new_events -> {
      let remove =
        list.filter(old_events, fn(e) { !list.contains(new_events, e) })
      [UpdateEvents(selector, new_events, remove)]
    }
  }
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
              let #(name, value) = attribute_to_string(a)
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
    UpdateEvents(selector, event_names, remove) ->
      json.object([
        #("action", json.string("updateevents")),
        #("selector", encode_id(selector)),
        #("value", json.array(event_names, json.string)),
        #("remove", json.array(remove, json.string)),
      ])
  }
}

// Builders

pub fn on_click(node: DomNode(msg), handler: fn() -> msg) -> DomNode(msg) {
  case node {
    Element(n, a, c, e) ->
      Element(node: n, attributes: a, children: c, events: [Click(handler), ..e])
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
        MouseOver(handler),
        ..e
      ])
    Text(_) -> node
  }
}

// Convenience functions

pub fn div(
  attributes: List(Attribute),
  children: List(DomNode(msg)),
) -> DomNode(msg) {
  Element(N("div"), attributes, children, [])
}

pub fn button(
  attributes: List(Attribute),
  children: List(DomNode(msg)),
) -> DomNode(msg) {
  Element(N("button"), attributes, children, [])
}

pub fn text(text: String) -> DomNode(msg) {
  Text(text)
}

pub fn input(attributes: List(Attribute)) -> DomNode(msg) {
  Element(N("input"), attributes, [], [])
}

pub fn span(
  attributes: List(Attribute),
  children: List(DomNode(msg)),
) -> DomNode(msg) {
  Element(N("span"), attributes, children, [])
}
