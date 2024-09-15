import gleam/json

// ----------------------------------------------------------------------------
// Types
// ----------------------------------------------------------------------------

pub type Attribute {
  Value(String)
  TextInput
  Attribute(name: String, value: String)
}

// ----------------------------------------------------------------------------
// Encoding
// ----------------------------------------------------------------------------

pub fn to_string(attribute: Attribute) -> #(String, String) {
  case attribute {
    Value(value) -> #("value", value)
    TextInput -> #("type", "text")
    Attribute(name, value) -> #(name, value)
  }
}

pub fn to_json(attribute: Attribute) -> #(String, json.Json) {
  case attribute {
    Value(value) -> #("value", json.string(value))
    TextInput -> #("type", json.string("text"))
    Attribute(name, value) -> #(name, json.string(value))
  }
}
