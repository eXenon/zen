import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/list
import gleam/otp/actor
import gleam/result

pub opaque type Topic {
  Topic(String)
}

pub fn topic(name) -> Topic {
  Topic(name)
}

pub opaque type PubSubMessage(msg) {
  Subscribe(Subject(msg), List(Topic))
  Publish(Topic, msg)
  Broadcast(Subject(msg), msg)
}

type PubSubState(msg) {
  PubSubState(
    subscribers: List(Subject(msg)),
    topics: Dict(Topic, List(Subject(msg))),
  )
}

fn handle_message(
  message: PubSubMessage(msg),
  state: PubSubState(msg),
) -> actor.Next(PubSubMessage(msg), PubSubState(msg)) {
  case message {
    Subscribe(subject, topic) -> {
      let subscribers = [subject, ..state.subscribers]
      let topics =
        list.fold(topic, state.topics, fn(topics, topic) {
          let subscribers = dict.get(topics, topic) |> result.unwrap([])
          dict.insert(into: topics, for: topic, insert: [subject, ..subscribers])
        })
      actor.continue(PubSubState(subscribers: subscribers, topics: topics))
    }
    Publish(topic, msg) -> {
      let subscribers = dict.get(state.topics, topic) |> result.unwrap([])
      list.map(subscribers, fn(subject) { process.send(subject, msg) })
      actor.continue(state)
    }
    Broadcast(subject, msg) -> {
      list.map(state.subscribers, fn(s) {
        case s == subject {
          // Don't send to self
          True -> Nil
          False -> process.send(s, msg)
        }
      })
      actor.continue(state)
    }
  }
}

// ----------------------------------------------------------------------------
// API
// ----------------------------------------------------------------------------

pub fn create() -> Result(Subject(PubSubMessage(msg)), actor.StartError) {
  let initial_state = PubSubState(subscribers: [], topics: dict.from_list([]))
  actor.start(initial_state, handle_message)
}

pub fn subscribe(
  pubsub: Subject(PubSubMessage(msg)),
  subject: Subject(msg),
  topics: List(Topic),
) -> Nil {
  process.send(pubsub, Subscribe(subject, topics))
}

pub fn publish(
  pubsub: Subject(PubSubMessage(msg)),
  topic: Topic,
  msg: msg,
) -> Nil {
  process.send(pubsub, Publish(topic, msg))
}

pub fn broadcast(
  pubsub: Subject(PubSubMessage(msg)),
  sender: Subject(msg),
  msg: msg,
) -> Nil {
  process.send(pubsub, Broadcast(sender, msg))
}
