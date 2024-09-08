import core
import dom
import gleam/int.{to_string}
import utils

pub type Model {
  Model(count: Int, position: #(Int, Int))
}

pub type Msg {
  Increment
  Decrement
  MouseOver(#(Int, Int))
}

pub fn init() -> Model {
  Model(count: 0, position: #(0, 0))
}

pub fn update(
  model: Model,
  msg: core.Msg(Msg),
) -> #(Model, List(core.Effect(Msg))) {
  #(
    case msg {
      core.Custom(Increment) -> Model(..model, count: model.count + 1)
      core.Custom(Decrement) -> Model(..model, count: model.count - 1)
      core.Custom(MouseOver(pos)) -> Model(..model, position: pos)
      _ -> model
    },
    [],
  )
}

pub fn view(model: Model) -> core.View(core.Msg(Msg)) {
  let #(x, y) = model.position
  core.View(
    title: "Demo + " <> int.to_string(x) <> " - " <> int.to_string(y),
    body: dom.div([], [
      dom.button([], [dom.text("Increment")])
        |> dom.on_click(fn() { core.Custom(Increment) }),
      dom.text(
        to_string(model.count) <> " " <> to_string(x) <> " " <> to_string(y),
      ),
      dom.button([], [dom.text("Decrement")])
        |> dom.on_click(fn() { core.Custom(Decrement) }),
      ..utils.for_each(x, fn(i) { dom.button([], [dom.text(int.to_string(i))]) })
    ])
      |> dom.on_mouse_over(fn(pos) { core.Custom(MouseOver(#(pos.x, pos.y))) }),
  )
}

pub fn demo() -> core.App(Model, Msg) {
  core.app(init, update, view)
}
