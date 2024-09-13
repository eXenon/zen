import gleam/dynamic
import gleam/int
import gleam/json
import gleam/list
import gleam/result
import gleam/string

// ----------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------- 

pub type Id {
  Root
  Node(List(Int))
}

// ----------------------------------------------------------------------------
// Functions
// ----------------------------------------------------------------------------

pub fn root() -> Id {
  Root
}

pub fn child(parent: Id, index: Int) -> Id {
  case parent {
    Root -> Node([index])
    Node(p) -> Node([index, ..p])
  }
}

pub fn parent(child: Id) -> Id {
  case child {
    Root -> Root
    Node([_, ..parent_path]) -> Node(parent_path)
    Node([]) -> Root
  }
}

// ----------------------------------------------------------------------------
// Encoding
// ----------------------------------------------------------------------------

pub fn encode_id(id: Id) -> json.Json {
  case id {
    Root -> json.string("root")
    Node(path) -> json.array(path, json.int)
  }
}

pub fn print_id(id: Id) -> String {
  case id {
    Root -> "root"
    Node(path) -> string.join(list.map(path, int.to_string), "-")
  }
}

pub fn id_decoder() {
  dynamic.any([
    fn(d) {
      dynamic.string(d)
      |> result.try(fn(s) {
        case s {
          "root" -> Ok(Root)
          _ ->
            Error([dynamic.DecodeError(expected: "root", found: s, path: [])])
        }
      })
    },
    fn(d) {
      dynamic.list(of: dynamic.int)(d)
      |> result.map(Node)
    },
  ])
}
