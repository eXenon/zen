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
