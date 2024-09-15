import gleam/dict
import gleam/dynamic
import gleam/list
import zen/dom/id.{type Id}

// ----------------------------------------------------------------------------
// Types
// ----------------------------------------------------------------------------

pub type Event(msg) {
  Event(id: String, handler: EventHandler(msg))
}

pub type EventPayloadCoordinates {
  Coordinates(x: Int, y: Int)
}

pub type EventHandler(msg) {
  Click(fn() -> msg)
  MouseOver(fn(EventPayloadCoordinates) -> msg)
  Input(fn(String) -> msg)
}

pub type EventHandlers(msg) =
  List(EventHandler(msg))

pub type EventHandlerError {
  DecodeError
}

pub type EventStore(msg) {
  EventStore(dict.Dict(Id, EventHandlers(msg)))
}

// ----------------------------------------------------------------------------
// Functions
// ----------------------------------------------------------------------------

pub fn empty_event_store() -> EventStore(msg) {
  EventStore(dict.from_list([]))
}

pub fn event_handler_name(event_handler: EventHandler(msg)) -> String {
  case event_handler {
    Click(_) -> "click"
    MouseOver(_) -> "mouseover"
    Input(_) -> "input"
  }
}

pub fn event_handler_names(handlers: EventHandlers(msg)) -> List(String) {
  list.map(handlers, event_handler_name)
}

// ----------------------------------------------------------------------------
// Encoding
// ----------------------------------------------------------------------------

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
    Input(handler) ->
      case dynamic.string(payload) {
        Ok(input) -> Ok(handler(input))
        Error(_) -> Error(DecodeError)
      }
  }
}
