import core
import demo
import dom
import gleam/bytes_builder
import gleam/erlang/process
import gleam/function
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/io
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/otp/actor
import gleam/otp/task
import gleam/result
import gleam/string
import gleam/string_builder
import mist.{type Connection, type ResponseData}
import utils

pub type ServerSubjects(msg) {
  ServerSubjects(
    self: process.Subject(ServerSideMessage(msg)),
    broadcast: process.Subject(ServerSideMessage(msg)),
  )
}

pub fn main() {
  // These values are for the Websocket process initialized below
  let broadcast_subject = process.new_subject()

  // Demo app
  let app = demo.demo()
  let state = app.init()
  let #(app, view) = core.build_view(app, state)

  let not_found =
    response.new(404)
    |> response.set_body(mist.Bytes(bytes_builder.new()))

  let assert Ok(_) =
    fn(req: Request(Connection)) -> Response(ResponseData) {
      case request.path_segments(req) {
        [] -> send_view(req, view)
        ["ws"] -> {
          let self_subject = process.new_subject()
          let selector =
            process.new_selector()
            |> process.selecting(broadcast_subject, function.identity)
            |> process.selecting(self_subject, function.identity)
          let subjects =
            ServerSubjects(self: self_subject, broadcast: broadcast_subject)
          mist.websocket(
            request: req,
            on_init: fn(_conn) {
              #(#(app, state, view, subjects), Some(selector))
            },
            on_close: fn(_state) { io.println("goodbye!") },
            handler: handle_ws_message,
          )
        }
        ["file", ..rest] -> serve_file(req, rest)

        _ -> not_found
      }
    }
    |> mist.new
    |> mist.port(3000)
    |> mist.start_http

  process.sleep_forever()
}

pub type ServerSideMessage(msg) {
  EffectFeedback(core.Msg(msg))
}

fn handle_msg(
  conn: mist.WebsocketConnection,
  subjects: ServerSubjects(msg),
  app: core.App(model, msg),
  state: model,
  prev_view: core.View(core.Msg(msg)),
  msg: core.Msg(msg),
) {
  let #(new_state, effects) = core.update(app, state, msg)
  let #(new_app, view) = core.build_view(app, new_state)
  let diffs = core.diff(prev_view, view)
  let title_diffs =
    core.title_diff(prev_view, view)
    |> option.map(fn(t) { #("title", json.string(t)) })
    |> utils.option_to_list()
  let message = case diffs {
    [] -> []
    _ ->
      diffs
      |> json.array(of: dom.encode)
      |> fn(diffs) { [#("diff", diffs), ..title_diffs] }
      |> json.object()
      |> json.to_string()
      |> fn(m) { [m] }
  }

  let assert Ok(_) =
    list.map(message, with: mist.send_text_frame(conn, _))
    |> result.all

  // Run effects
  list.map(effects, fn(effect) {
    task.async(fn() {
      let core.Effect(f) = effect
      let msg = f()
      process.send(subjects.self, EffectFeedback(msg))
    })
  })

  #(new_app, new_state, view)
}

fn handle_ws_message(tea, conn, message) {
  let #(app, state, prev_view, subjects) = tea
  case message {
    mist.Text("ping") -> {
      let assert Ok(_) = mist.send_text_frame(conn, "pong")
      actor.continue(tea)
    }

    mist.Text(incoming) -> {
      case core.deserialize(app, incoming) {
        Some(msg) -> {
          let #(new_app, new_state, new_view) =
            handle_msg(conn, subjects, app, state, prev_view, msg)
          actor.continue(#(new_app, new_state, new_view, subjects))
        }
        None -> {
          io.println("error: could not deserialize message " <> incoming)
          actor.continue(tea)
        }
      }
    }

    mist.Binary(_) -> {
      actor.continue(tea)
    }

    mist.Custom(EffectFeedback(msg)) -> {
      let #(new_app, new_state, new_view) =
        handle_msg(conn, subjects, app, state, prev_view, msg)
      actor.continue(#(new_app, new_state, new_view, subjects))
    }

    mist.Closed | mist.Shutdown -> actor.Stop(process.Normal)
  }
}

fn serve_file(
  _req: Request(Connection),
  path: List(String),
) -> Response(ResponseData) {
  let file_path = string.join(path, "/")

  // Omitting validation for brevity
  mist.send_file(file_path, offset: 0, limit: None)
  |> result.map(fn(file) {
    response.new(200)
    |> response.prepend_header("content-type", "text/javascript")
    |> response.set_body(file)
  })
  |> result.lazy_unwrap(fn() {
    response.new(404)
    |> response.set_body(mist.Bytes(bytes_builder.new()))
  })
}

fn send_view(_req: Request(Connection), view: core.View(msg)) {
  response.new(200)
  |> response.prepend_header("content-type", "text/html")
  |> response.set_body(
    mist.Bytes(bytes_builder.from_string_builder(core.render(view))),
  )
}
