/// Deterministic PRNG for the engine — SplitMix64.
///
/// DETERMINISM CONTRACT (do not touch without regenerating golden fixtures):
///  * 64-bit wrapping arithmetic (Dart native int semantics; this package
///    targets VM/AOT only — web compilation would break these semantics).
///  * nextBounded(n) = (next() & 0x7FFFFFFFFFFFFFFF) % n
///  * shuffle = Fisher–Yates from the top: for i = len-1 … 1,
///    j = nextBounded(i + 1), swap(i, j).
///
/// A reference Python implementation lives in tool/gen_golden.py and produced
/// test/fixtures/wall_golden.json. Dart tests assert bit-for-bit equality.
library;

class SplitMix64 {
  int _state;

  SplitMix64(int seed) : _state = seed;

  /// Next raw 64-bit value.
  int next() {
    _state = _state + 0x9E3779B97F4A7C15; // wraps on VM
    var z = _state;
    z = (z ^ (z >>> 30)) * 0xBF58476D1CE4E5B9;
    z = (z ^ (z >>> 27)) * 0x94D049BB133111EB;
    return z ^ (z >>> 31);
  }

  /// Uniform-ish int in [0, n). Tiny modulo bias is acceptable and is part
  /// of the frozen contract (the Python reference does exactly the same).
  int nextBounded(int n) {
    assert(n > 0);
    return (next() & 0x7FFFFFFFFFFFFFFF) % n;
  }

  /// In-place Fisher–Yates shuffle.
  void shuffle<T>(List<T> list) {
    for (var i = list.length - 1; i >= 1; i--) {
      final j = nextBounded(i + 1);
      final tmp = list[i];
      list[i] = list[j];
      list[j] = tmp;
    }
  }
}
