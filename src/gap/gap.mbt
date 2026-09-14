// Completion of a partial map, and the proof that it completes.
//
// The setting, stripped to its bones. Something upstream (in the original, a
// greedy pass over floating-point distances followed by a local search)
// produces an array in which *some* entries are decided and the rest are `-1`.
// Completion fills the rest in. Everything downstream then does
//
//     let target = map[i]        // trusted to be a real index
//     let (a, b) = span(target)  // trusted to be in range
//
// with no check of its own. If completion leaves a `-1` behind, reading it out
// of `map` is not yet the problem; using it as an index into `span` is. Under
// WebAssembly that call traps and a `WebAssembly.RuntimeError` reaches the
// host, which is a call that returns no answer rather than a wrong one. In the
// JavaScript original the corresponding read is `undefined`, and the damage
// happens further downstream.
//
// "It happens not to leave one behind" is exactly the kind of claim a solver
// is good at and a test is bad at, because a test can only report that the
// inputs it tried did not produce one.

///|
/// A fresh map of `n` undecided entries.
///
/// The contract is longer than the body, and stated anyway: this is where the
/// sentinel enters the module. `-1` is not a valid index and cannot become
/// one, because every function here either preserves an entry or overwrites it
/// with a value copied from another entry. That is what makes `assigned` a
/// statement about values, and the whole chain expressible.
pub fn make_unassigned(
  n : Int,
) -> FixedArray[Int] where {
  proof_require: 0 <= n,
  proof_ensure: result => result.length() == n,
  proof_ensure: result => ∀ i : Int, in_bounds(i, n) → result[i] == -1,
  proof_reasoning: (
    #| Both clauses are the constructor's own semantics. `0 <= n` is the
    #| allocation's requirement: a negative length is not a short array, it is
    #| a trap.
  ),
} {
  FixedArray::make(n, -1)
}

///|
/// Is every entry decided?
///
/// The property `fill_forward` proves, restated as something that can be
/// *run*. That is not redundancy. A proof establishes that the code satisfies
/// the contract and says nothing about whether the contract says what was
/// meant; running this on real data checks the other half, and it shares
/// nothing with the proof but the predicate, so a mistake would have to be
/// made twice, in two languages, to escape both.
pub fn is_total(
  xs : FixedArray[Int],
) -> Bool where {
  proof_ensure: result => result == total(xs),
  proof_reasoning: (
    #| The equivalence is the loop invariant read off at the exit, where the
    #| prefix is the whole array.
  ),
} {
  let mut ok = true
  for i = 0; i < xs.length(); i = i + 1 {
    if xs[i] == -1 {
      ok = false
    }
  } where {
    proof_invariant: 0 <= i,
    proof_invariant: i <= xs.length(),
    proof_invariant: ok == prefix_total(xs, i),
    proof_reasoning: (
      #| Establishment: `prefix_total(xs, 0)` is vacuous and `ok` starts true.
      #|
      #| Preservation, in both directions, because the invariant is an
      #| equivalence. If entry `i` is decided, neither side changes. If it is
      #| not, `ok` is set false and `prefix_total(xs, i + 1)` is false with `i`
      #| as the witness.
      #|
      #| `ok` is only ever assigned false, which matches the predicate: a
      #| prefix that has lost a member cannot regain it as it grows.
      #|
      #| Termination is inferred from the loop's shape.
      #| `for i = 0; i < n; i = i + 1` is the only form MoonBit derives a
      #| variant for; written `i <= n - 1` the same loop gets none, and the
      #| obligation comes back unknown with no hint that the shape of the
      #| condition was the problem.
    ),
  }
  ok
}

///|
/// Clamp a division point into `[start, stop)`.
///
/// The join between the two halves of a real algorithm. In the original the
/// argument arrives from the floating-point solver, which the verifier cannot
/// see into at all, so it is not trusted, it is clamped. A solver returning
/// nonsense
/// can then still not produce a malformed map, and the proof below does not
/// depend on the numeric code being right, only on it returning an integer.
pub fn clamp_div(
  div : Int,
  start : Int,
  stop : Int,
) -> Int where {
  proof_require: start < stop,
  proof_ensure: result => start <= result,
  proof_ensure: result => result < stop,
  proof_reasoning: (
    #| Three branches, one per post-condition case. `stop - 1` is in range
    #| because `start < stop`, which is the only hypothesis doing any work.
  ),
} {
  if div < start {
    start
  } else if div >= stop {
    stop - 1
  } else {
    div
  }
}

///|
/// Fill every undecided entry with the nearest decided entry to its left.
///
/// The theorem, in English: *given an array whose first entry is decided, the
/// result has the same length and no undecided entry anywhere.*
///
/// The real thing is this plus a choice of where to cut each run, and
/// `clamp_div` above is where that choice arrives. The shape of the proof is
/// the same. Note what the contract does *not* say: nothing about which
/// value each entry receives, and nothing about the run being the closest
/// match. Those are the optimisation problem, and they are neither proved nor
/// provable. What is proved is that the sentinel is gone.
pub fn fill_forward(
  xs : FixedArray[Int],
) -> FixedArray[Int] where {
  proof_require: 0 < xs.length(),
  proof_require: assigned(xs, 0),
  proof_ensure: result => result.length() == xs.length(),
  proof_ensure: result => total(result),
  proof_reasoning: (
    #| The output is allocated locally and written in place rather than the
    #| input being mutated, and that is not a style choice. MoonBit has no
    #| `old(...)`, so a function that mutates its argument cannot state a frame
    #| condition ("and I changed nothing else"), and a caller therefore loses
    #| every fact it knew about the array the moment it makes the call. Proof
    #| by composition stops working. Within one body the verifier tracks each
    #| write exactly, so the rule is: keep every mutation inside the function
    #| that reasons about it.
    #|
    #| `assigned(xs, 0)` is the whole pre-condition and it is load-bearing in
    #| exactly one place: establishing the invariant at `i = 1`. Without it
    #| the first entry could be `-1`, and every later entry copying leftwards
    #| would copy it.
  ),
} {
  let n = xs.length()
  let out = FixedArray::make(n, -1)
  out[0] = xs[0]
  for i = 1; i < n; i = i + 1 {
    out[i] = if xs[i] == -1 { out[i - 1] } else { xs[i] }
  } where {
    proof_invariant: 1 <= i,
    proof_invariant: i <= n,
    proof_invariant: out.length() == n,
    proof_invariant: prefix_total(out, i),
    proof_reasoning: (
      #| Establishment. `out[0] = xs[0]` and `assigned(xs, 0)`, so
      #| `prefix_total(out, 1)`.
      #|
      #| Preservation. Two cases, and both extend the prefix by an entry that
      #| is decided. If `xs[i] != -1` the entry written is `xs[i]`. If it is
      #| `-1` the entry written is `out[i - 1]`, which the invariant already
      #| says is decided because `i - 1 < i`. Nothing below `i` is touched, so
      #| the rest of the prefix survives.
      #|
      #| Exit at `i == n` gives `prefix_total(out, n)`, whose quantifier ranges
      #| over exactly the indices `total(out)` does.
    ),
  }
  out
}
