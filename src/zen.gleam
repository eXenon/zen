import gleam/bytes_builder
import gleam/erlang
import gleam/erlang/process.{type Subject}
import gleam/function
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/io
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/otp/actor
import gleam/result
import gleam/string
import gleam/string_builder
import mist.{type Connection, type ResponseData}
import zen/core
import zen/dom
import zen/dom/builder
import zen/dom/id
import zen/effects
import zen/helpers/pubsub
import zen/helpers/timedkv
import zen/utils

pub type ServerSideState(model, msg) {
  ServerSideState(
    id: String,
    self: Subject(core.Msg(msg)),
    app: core.App(model, msg),
    state: model,
    view: core.View(core.Msg(msg)),
    timedkv: Subject(
      timedkv.TimedKVMessage(
        #(core.App(model, msg), model, core.View(core.Msg(msg))),
      ),
    ),
    pubsub: Subject(pubsub.PubSubMessage(core.Msg(msg))),
  )
}

pub fn run(app: core.App(model, msg)) {
  // PubSub handles messages between clients
  let assert Ok(pubsub) = pubsub.create()

  // TimedKV handles the ability to link a websocket connection to a client
  let assert Ok(timedkv) = timedkv.create(30)

  let not_found =
    response.new(404)
    |> response.set_body(mist.Bytes(bytes_builder.new()))

  let assert Ok(_) =
    fn(req: Request(Connection)) -> Response(ResponseData) {
      case request.path_segments(req) {
        [] -> {
          let id = utils.uuid()
          let state = app.init()
          let #(app, view) = core.build_view(app, state)
          timedkv.store(timedkv, id, #(app, state, view))
          send_view(req, id, view)
        }
        ["ws"] -> {
          mist.websocket(
            request: req,
            on_init: fn(_conn) {
              // Initialize a new app state, but the client can request the already initialized state
              // by sending "init+" followed by the id
              let state = app.init()
              let #(app, view) = core.build_view(app, state)
              let id = utils.uuid()
              let self_subject = process.new_subject()
              let selector =
                process.new_selector()
                |> process.selecting(self_subject, function.identity)
              let state =
                ServerSideState(
                  id: id,
                  self: self_subject,
                  app: app,
                  state: state,
                  view: view,
                  timedkv: timedkv,
                  pubsub: pubsub,
                )
              let _ = pubsub.subscribe(pubsub, self_subject, [pubsub.topic(id)])
              #(state, Some(selector))
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
    |> mist.port(5001)
    |> mist.start_http

  process.sleep_forever()
}

fn handle_msg(
  conn: mist.WebsocketConnection,
  zen: ServerSideState(model, msg),
  msg: core.Msg(msg),
) {
  let #(new_state, effects) = core.update(zen.app, zen.state, msg)
  let #(new_app, new_view) = core.build_view(zen.app, new_state)
  let diffs = core.diff(zen.view, new_view)
  let title_diffs =
    core.title_diff(zen.view, new_view)
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

  // Send diffs to client
  let assert Ok(_) =
    list.map(message, with: mist.send_text_frame(conn, _))
    |> result.all

  // Run effects
  list.map(effects, fn(effect) { effects.run(zen.self, zen.pubsub, effect) })

  ServerSideState(
    zen.id,
    zen.self,
    new_app,
    new_state,
    new_view,
    zen.timedkv,
    zen.pubsub,
  )
}

fn handle_ws_message(
  zen: ServerSideState(model, msg),
  conn: mist.WebsocketConnection,
  message: mist.WebsocketMessage(core.Msg(msg)),
) {
  case message {
    mist.Text("ping") -> {
      let assert Ok(_) = mist.send_text_frame(conn, "pong")
      actor.continue(zen)
    }

    mist.Text("init+" <> id) -> {
      let assert Ok(#(app, state, view)) = timedkv.get(zen.timedkv, id)
      let new_zen =
        ServerSideState(id, zen.self, app, state, view, zen.timedkv, zen.pubsub)
      // Ensure that the client state is synced with the server state
      // even though theoretically, the client should already have the
      // initial view from the static response
      let assert Ok(_) =
        [#("body", dom.node_encoder(dom.assign_ids(id.root(), view.body)))]
        |> json.object
        |> json.to_string
        |> fn(s) { mist.send_text_frame(conn, s) }
      actor.continue(new_zen)
    }

    mist.Text(incoming) -> {
      case core.deserialize(zen.app, incoming) {
        Some(msg) -> {
          let new_zen = handle_msg(conn, zen, msg)
          actor.continue(new_zen)
        }
        None -> {
          io.println("error: could not deserialize message " <> incoming)
          actor.continue(zen)
        }
      }
    }

    mist.Binary(_) -> {
      actor.continue(zen)
    }

    mist.Custom(msg) -> {
      let new_zen = handle_msg(conn, zen, msg)
      actor.continue(new_zen)
    }

    mist.Closed | mist.Shutdown -> actor.Stop(process.Normal)
  }
}

fn serve_file(
  _req: Request(Connection),
  path: List(String),
) -> Response(ResponseData) {
  let assert Ok(priv) = erlang.priv_directory("zen")
  let file_path = string.join([priv, ..path], "/")

  // Omitting validation for brevity
  mist.send_file(file_path, offset: 0, limit: None)
  |> result.map(fn(file) {
    response.new(200)
    |> response.prepend_header("content-type", "application/javascript")
    |> response.prepend_header("cache-control", "no-cache")
    |> response.prepend_header("pragma", "no-cache")
    |> response.prepend_header("expires", "0")
    |> response.prepend_header("x-content-type-options", "nosniff")
    |> response.set_body(file)
  })
  |> result.lazy_unwrap(fn() {
    response.new(404)
    |> response.set_body(mist.Bytes(bytes_builder.new()))
  })
}

fn send_view(_req: Request(Connection), id: String, view: core.View(msg)) {
  response.new(200)
  |> response.prepend_header("content-type", "text/html")
  |> response.set_body(
    mist.Bytes(bytes_builder.from_string_builder(core.render(id, view))),
  )
}
