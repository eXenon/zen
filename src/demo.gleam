import core
import dom
import gleam/int.{to_string}

pub type Model {
  Model(count: Int)
}

pub type Msg {
  Increment
  Decrement
}

pub fn init() -> Model {
  Model(count: 0)
}

pub fn update(model: Model, msg: core.Msg(Msg)) -> Model {
  case msg {
    core.Custom(Increment) -> Model(count: model.count + 1)
    core.Custom(Decrement) -> Model(count: model.count - 1)
    _ -> model
  }
}

pub fn view(model: Model) -> core.View(Msg) {
  core.View(
    title: "Demo",
    body: dom.div([], [
      dom.button([], [dom.text("Increment")], fn() { core.Custom(Increment) }),
      dom.text(to_string(model.count)),
      dom.button([], [dom.text("Decrement")], fn() { core.Custom(Decrement) }),
    ]),
  )
}

pub fn demo() -> core.App(Model, Msg) {
  core.app(init, update, view)
}
