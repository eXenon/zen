import core.{type DomNode}

pub fn div(
  attributes: List(#(String, String)),
  children: List(DomNode(msg)),
  hover: fn(#(Int, Int)) -> msg,
) -> DomNode(msg) {
  let id = core.uuid()
  core.Element("div", attributes, children, [
    core.Event(id, core.MouseOver(hover)),
  ])
}

pub fn button(
  attributes: List(#(String, String)),
  children: List(DomNode(msg)),
  on_click: fn() -> msg,
) -> DomNode(msg) {
  let id = core.uuid()
  core.Element("button", attributes, children, [
    core.Event(id, core.Click(on_click)),
  ])
}

pub fn text(text: String) -> DomNode(msg) {
  core.Text(text)
}
