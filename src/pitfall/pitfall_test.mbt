// Both functions in this package are proved. Neither proof means what a
// casual reading would take it to mean, and these tests are the record of the
// gap in each case.

///|
/// The most negative `Int`.
///
/// A perfectly ordinary literal, and `moonbitlang/core` writes it as one:
/// `pub const MIN_VALUE = -2147483648`. It is spelled out here rather than
/// imported only to keep the package free of dependencies.
fn int_min() -> Int {
  -2147483648
}

///|
test "abs_unguarded: the pre-condition is not enforced at runtime" {
  // The contract excludes this value, and the exclusion is real: with it, the
  // function is correct, and `moon prove` closes the goal under both proof
  // models. What the contract cannot do is stop anyone calling it anyway.
  //
  // No error is raised, nothing is logged, and the "absolute value" is
  // negative. A pre-condition is discharged by whoever calls, and at the edge
  // of the verified code that is nobody.
  let unchecked = @pitfall.abs_unguarded(int_min())
  assert_eq(unchecked, int_min())
  assert_true(unchecked < 0)
}

///|
test "abs_unguarded is correct everywhere its contract applies" {
  for x in [-2147483647, -1000, -1, 0, 1, 1000, 2147483647] {
    let r = @pitfall.abs_unguarded(x)
    assert_true(r >= 0)
    assert_eq(r.to_int64(), if x < 0 { -x.to_int64() } else { x.to_int64() })
  }
}

///|
test "abs_diff_unsound: `0 <= result` is proved, and false" {
  // 2147483647 - (-2147483647) is 4294967294 over the integers, and -2 in an
  // `Int`. The proof is about the first number. Nothing in the contract
  // excludes these inputs, so unlike the case above this is a genuine
  // counterexample to the post-condition and not a violated pre-condition.
  let broken = @pitfall.abs_diff_unsound(2147483647, -2147483647)
  assert_eq(broken, -2)
  assert_true(broken < 0)
}

///|
test "abs_diff_unsound is correct wherever the true value is representable" {
  // The bug is exactly the overflow, which is worth pinning too: the function
  // is not nonsense, its contract just does not say where it stops holding.
  assert_eq(@pitfall.abs_diff_unsound(10, 4), 6)
  assert_eq(@pitfall.abs_diff_unsound(4, 10), 6)
  assert_eq(@pitfall.abs_diff_unsound(-3, -9), 6)
}
