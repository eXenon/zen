import gleam/option.{type Option, None, Some}

fn inner(i, a, b) {
  case a, b {
    [h1, ..t1], [h2, ..t2] -> [#(i, Some(h1), Some(h2)), ..inner(i + 1, t1, t2)]
    [h1, ..t1], [] -> [#(i, Some(h1), None), ..inner(i + 1, t1, [])]
    [], [h2, ..t2] -> [#(i, None, Some(h2)), ..inner(i + 1, [], t2)]
    [], [] -> []
  }
}

pub fn extzipmap(a: List(a), b: List(b)) -> List(#(Int, Option(a), Option(b))) {
  inner(0, a, b)
}
