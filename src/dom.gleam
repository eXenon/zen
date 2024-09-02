import core.{type DomNode}

pub fn div(
  attributes: List(#(String, String)),
  children: List(DomNode(msg)),
) -> DomNode(msg) {
  core.Element("div", attributes, children, [])
}

pub fn button(
  attributes: List(#(String, String)),
  children: List(DomNode(msg)),
  on_click: fn() -> core.Msg(msg),
) -> DomNode(msg) {
  let id = core.uuid()
  core.Element("button", attributes, children, [#("click", id, on_click)])
}

pub fn text(text: String) -> DomNode(msg) {
  core.Text(text)
}
