/// L1 AI policy — line-for-line port of ref_engine/ai.py.
///
/// Level 1 = competent beginner: always wins when it can, declares 叮 when a
/// discard leaves a wait, discards by shanten descent (tie-break: fewest
/// neighbours / most isolated first), claims pung/chow only when it lowers
/// shanten, kongs whenever available. Deterministic given the same views
/// (no RNG), so self-play games are reproducible from the wall seed alone.
library;

import 'decompose.dart';
import 'engine.dart';
import 'kinds.dart';

/// Lower = more isolated = better to throw.
int _neighbourScore(List<int> counts, int k) {
  var s = counts[k] * 10;
  if (k < 27) {
    // suited: adjacent ranks matter
    final r = k % 9;
    for (final d in const [-2, -1, 1, 2]) {
      if (r + d >= 0 && r + d <= 8) {
        s += counts[k + d] * (d.abs() == 1 ? 2 : 1);
      }
    }
  }
  return s;
}

class L1Policy extends GamePolicy {
  @override
  List<int> chooseSwap(Map<String, dynamic> view, int n) {
    final c = [...(view['counts'] as List<int>)];
    final picks = <int>[];
    for (var i = 0; i < n; i++) {
      // Python: min(cands, key=...) — first minimum in ascending kind order.
      int? best;
      int? bestScore;
      for (var k = 0; k < numKinds; k++) {
        if (c[k] == 0) continue;
        final sc = _neighbourScore(c, k);
        if (bestScore == null || sc < bestScore) {
          best = k;
          bestScore = sc;
        }
      }
      c[best!] -= 1;
      picks.add(best);
    }
    return picks;
  }

  int _bestDiscard(Map<String, dynamic> view) {
    final c = view['counts'] as List<int>;
    final jk = view['jokers'] as int;
    final nm = (view['melds'] as List).length;
    int? best;
    (int, int)? bestKey;
    for (var k = 0; k < numKinds; k++) {
      if (c[k] == 0) continue;
      c[k] -= 1;
      final key = (shanten(c, jk, nm), _neighbourScore(c, k));
      c[k] += 1;
      // Python tuple < : strictly less wins; ties keep the earlier k.
      if (bestKey == null ||
          key.$1 < bestKey.$1 ||
          (key.$1 == bestKey.$1 && key.$2 < bestKey.$2)) {
        best = k;
        bestKey = key;
      }
    }
    return best!;
  }

  @override
  int chooseDiscard(Map<String, dynamic> view) => _bestDiscard(view);

  @override
  bool wantWin(Map<String, dynamic> view) => true;

  @override
  int? wantTing(Map<String, dynamic> view) {
    final c = view['counts'] as List<int>;
    final jk = view['jokers'] as int;
    final nm = (view['melds'] as List).length;
    for (var k = 0; k < numKinds; k++) {
      if (c[k] == 0) continue;
      c[k] -= 1;
      final ok = winningKinds(c, jk, nm).isNotEmpty;
      c[k] += 1;
      if (ok) return k;
    }
    return null;
  }

  @override
  (int, String)? wantKong(
      Map<String, dynamic> view, List<(int, String)> options) {
    // Kong whenever available (replacement draw + 底 reward); a ting hand
    // never reaches here (engine gates it).
    return options.isNotEmpty ? options.first : null;
  }

  bool _improves(Map<String, dynamic> view, List<int> take) {
    final c = view['counts'] as List<int>;
    final jk = view['jokers'] as int;
    final nm = (view['melds'] as List).length;
    final base = shanten(c, jk, nm);
    for (final k in take) {
      c[k] -= 1;
    }
    final after = shanten(c, jk, nm + 1);
    for (final k in take) {
      c[k] += 1;
    }
    return after < base;
  }

  @override
  String? wantClaim(
      Map<String, dynamic> view, int kind, List<String> options) {
    if (options.contains('pung') && _improves(view, [kind, kind])) {
      return 'pung';
    }
    return null;
  }

  @override
  int? wantChow(Map<String, dynamic> view, int kind, List<int> lowOptions) {
    for (final lo in lowOptions) {
      final need = [
        for (final x in [lo, lo + 1, lo + 2])
          if (x != kind) x
      ];
      if (_improves(view, need)) return lo;
    }
    return null;
  }
}
