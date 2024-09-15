import gleam/dict.{type Dict}
import gleam/erlang
import gleam/erlang/process.{type Subject}
import gleam/otp/actor
import gleam/result

type Time =
  Int

type Entry(value) {
  Entry(value: value, time: Time)
}

type State(value) {
  State(values: Dict(String, Entry(value)), expiration: Time)
}

pub opaque type TimedKVMessage(value) {
  Get(key: String, response: Subject(Result(value, Nil)))
  Set(key: String, value: value)
  Tick
}

fn handle_message(
  message: TimedKVMessage(value),
  state: State(value),
) -> actor.Next(TimedKVMessage(value), State(value)) {
  case message {
    Get(key, response) -> {
      let entry =
        dict.get(state.values, key) |> result.map(fn(entry) { entry.value })
      actor.send(response, entry)
      actor.continue(state)
    }
    Set(key, value) -> {
      let time = erlang.system_time(erlang.Second) + state.expiration
      let entry = Entry(value, time)
      let values = dict.insert(state.values, key, entry)
      actor.continue(State(values: values, expiration: state.expiration))
    }
    Tick -> {
      let time = erlang.system_time(erlang.Second)
      let values = dict.filter(state.values, fn(_, entry) { entry.time > time })
      actor.continue(State(values: values, expiration: state.expiration))
    }
  }
}

// ----------------------------------------------------------------------------
// API
// ----------------------------------------------------------------------------

pub fn create(
  expiration: Int,
) -> Result(Subject(TimedKVMessage(value)), actor.StartError) {
  actor.start(
    State(values: dict.from_list([]), expiration: expiration),
    handle_message,
  )
}

pub fn store(
  timedkv: Subject(TimedKVMessage(value)),
  key: String,
  value: value,
) -> Nil {
  process.send(timedkv, Set(key, value))
}

pub fn get(
  timedkv: Subject(TimedKVMessage(value)),
  key: String,
) -> Result(value, Nil) {
  process.call(timedkv, fn(s) { Get(key, s) }, within: 1000)
}
