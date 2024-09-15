import gleam/erlang/process.{type Subject}
import gleam/io
import zen/helpers/pubsub.{type PubSubMessage}

pub type Effect(msg, model) {
  Broadcast(msg)
}

pub fn run(
  self: Subject(msg),
  pubsub: Subject(PubSubMessage(msg)),
  effect: Effect(msg, model),
) -> Nil {
  case effect {
    Broadcast(msg) -> {
      pubsub.broadcast(pubsub, self, msg)
    }
  }
}
