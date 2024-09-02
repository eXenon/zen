import core
import demo
import gleam/bytes_builder
import gleam/erlang/process
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/io
import gleam/json
import gleam/option.{None, Some}
import gleam/otp/actor
import gleam/result
import gleam/string
import gleam/string_builder
import mist.{type Connection, type ResponseData}

pub fn main() {
  // These values are for the Websocket process initialized below
  let selector = process.new_selector()

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
        ["ws"] ->
          mist.websocket(
            request: req,
            on_init: fn(_conn) { #(#(app, state), Some(selector)) },
            on_close: fn(_state) { io.println("goodbye!") },
            handler: handle_ws_message,
          )
        ["file", ..rest] -> serve_file(req, rest)

        _ -> not_found
      }
    }
    |> mist.new
    |> mist.port(3000)
    |> mist.start_http

  process.sleep_forever()
}

pub type MyMessage {
  Broadcast(String)
}

fn handle_ws_message(tea, conn, message) {
  let #(app, state) = tea
  case message {
    mist.Text("ping") -> {
      let assert Ok(_) = mist.send_text_frame(conn, "pong")
      actor.continue(tea)
    }

    mist.Text(incoming) -> {
      case core.deserialize(app, incoming) {
        Some(event) -> {
          let new_state = core.update(app, state, event)
          let #(new_app, view) = core.build_view(app, new_state)
          let message =
            view
            |> core.render()
            |> string_builder.to_string
            |> json.string()
            |> fn(body) { [#("body", body)] }
            |> json.object()
            |> json.to_string()
          let assert Ok(_) = mist.send_text_frame(conn, message)
          actor.continue(#(new_app, new_state))
        }
        None -> {
          actor.continue(tea)
        }
      }
    }

    mist.Binary(_) -> {
      actor.continue(tea)
    }

    mist.Custom(Broadcast(text)) -> {
      let assert Ok(_) = mist.send_text_frame(conn, text)
      actor.continue(tea)
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
