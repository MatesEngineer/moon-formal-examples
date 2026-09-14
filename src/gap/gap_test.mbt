// The proof says completion leaves no sentinel behind. These run it.
//
// `is_total` is the same property as an executable check, and it shares
// nothing with the proof but the predicate's name — so a mistake would have to
// be made twice, in two languages, to escape both.

///|
test "a fresh map is entirely undecided" {
  let m = @gap.make_unassigned(4)
  assert_eq(m.length(), 4)
  assert_false(@gap.is_total(m))
}

///|
test "completion leaves no undecided entry" {
  let cases : Array[FixedArray[Int]] = [
    [7],
    [7, -1],
    [7, -1, -1, -1],
    [0, -1, 3, -1, -1, 9],
    [1, 2, 3],
  ]
  for c in cases {
    let filled = @gap.fill_forward(c)
    assert_eq(filled.length(), c.length())
    assert_true(@gap.is_total(filled))
  }
}

///|
test "decided entries survive, undecided ones copy leftwards" {
  let filled = @gap.fill_forward([5, -1, -1, 8, -1])
  assert_eq(filled, [5, 5, 5, 8, 8])
}

///|
test "is_total decides the property it is named after" {
  assert_true(@gap.is_total([0, 1, 1]))
  assert_false(@gap.is_total([0, -1, 1]))
  assert_true(@gap.is_total([]))
}

///|
test "clamp_div lands inside the half-open range whatever it is handed" {
  for div in [-2147483647, -5, 0, 3, 4, 5, 2147483647] {
    let r = @gap.clamp_div(div, 2, 5)
    assert_true(r >= 2)
    assert_true(r < 5)
  }
  assert_eq(@gap.clamp_div(3, 2, 5), 3)
  assert_eq(@gap.clamp_div(99, 2, 5), 4)
  assert_eq(@gap.clamp_div(-99, 2, 5), 2)
}
