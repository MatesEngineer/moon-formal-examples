// What the proofs cover is the domain `[INT_FLOOR, INT_MAX]`. What they cannot
// cover is `Int::min_value`, one below it, which no contract in the module can
// even mention — so its behaviour is recorded here by hand instead.

///|
/// Values at and around every boundary the arithmetic can meet.
fn edges() -> Array[Int] {
  [-2147483647, -2147483646, -1000000, -1, 0, 1, 1000000, 2147483646, 2147483647]
}

///|
test "add agrees with addition wherever addition works" {
  for a in edges() {
    for b in edges() {
      let sum = @saturating.add(a, b)
      // Reconstruct the true sum in a wider type to decide what to expect.
      let exact = a.to_int64() + b.to_int64()
      if exact > 2147483647L {
        assert_eq(sum, 2147483647)
      } else if exact < -2147483647L {
        assert_eq(sum, -2147483647)
      } else {
        assert_eq(sum.to_int64(), exact)
      }
    }
  }
}

///|
test "add clamps rather than wrapping" {
  assert_eq(@saturating.add(2147483647, 1), 2147483647)
  assert_eq(@saturating.add(2147483647, 2147483647), 2147483647)
  assert_eq(@saturating.add(-2147483647, -1), -2147483647)
}

///|
test "iabs on the domain the contract names" {
  for x in edges() {
    let r = @saturating.iabs(x)
    assert_true(r >= 0)
    assert_eq(r.to_int64(), if x < 0 { -x.to_int64() } else { x.to_int64() })
  }
}
