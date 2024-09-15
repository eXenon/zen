import gleam/int
import gleam/option.{type Option, None, Some}
import gleam/string

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

pub fn for_each(count: Int, f: fn(Int) -> a) -> List(a) {
  case count {
    i if i <= 0 -> []
    i -> [f(i), ..for_each(i - 1, f)]
  }
}

pub fn option_to_list(o: Option(a)) -> List(a) {
  case o {
    Some(v) -> [v]
    None -> []
  }
}

fn four_random_bytes() -> String {
  int.random(0xFF_FF_FF_FF)
  |> int.to_base16
  |> string.pad_left(8, "0")
}

pub fn uuid() -> String {
  let p1 = four_random_bytes()
  let p2 = four_random_bytes()
  let p3 = four_random_bytes()
  let p4 = four_random_bytes()
  let p5 = four_random_bytes()
  let p6 = four_random_bytes()
  let p7 = four_random_bytes()
  let p8 = four_random_bytes()
  p1 <> p2 <> "-" <> p3 <> "-" <> p4 <> "-" <> p5 <> "-" <> p6 <> p7 <> p8
}
