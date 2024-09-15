import zen/dom.{type DomNode, Element, N, Text}
import zen/dom/attributes.{type Attribute}
import zen/dom/events.{type EventPayloadCoordinates, Click, Input, MouseOver}

// ----------------------------------------------------------------------------
// Builders
// ----------------------------------------------------------------------------

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

// ----------------------------------------------------------------------------
// Helpers
// ----------------------------------------------------------------------------

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

pub fn on_input(node: DomNode(msg), handler: fn(String) -> msg) -> DomNode(msg) {
  case node {
    Element(n, a, c, e) ->
      Element(node: n, attributes: a, children: c, events: [Input(handler), ..e])
    Text(_) -> node
  }
}
