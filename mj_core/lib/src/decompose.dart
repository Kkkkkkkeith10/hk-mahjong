/// Hand decomposition, win detection, waits, and shanten — joker-aware.
/// Line-for-line port of ref_engine/decompose.py (fixture contract).
///
/// A full hand is 17 tiles = 5 面子 + 1 眼 (基本形), or a 特殊形
/// (嚦咕嚦咕 / 十三么 / 十六不搭). Exposed melds reduce the concealed
/// requirement: concealed part must form (5 - melds) melds + eye.
///
/// Jokers (百搭) may stand for any tile in the concealed part; a room
/// sub-option may forbid them as the eye.
///
/// DETERMINISM CONTRACT: enumerateStandard returns readings in canonical
/// order (eye asc, then melds lexicographic) so 高點法 ties resolve to the
/// same reading in Python and Dart.
library;

import 'kinds.dart';

// ── reading representation ──────────────────────────────────────────────

/// One meld of a resolved reading: 3 kind ints + triplet flag.
/// Ordering mirrors Python tuple comparison: (a,b,c) lexicographic, then
/// triplet (false < true).
class RMeld implements Comparable<RMeld> {
  final int a, b, c;
  final bool triplet;
  const RMeld(this.a, this.b, this.c, this.triplet);

  @override
  int compareTo(RMeld o) {
    if (a != o.a) return a - o.a;
    if (b != o.b) return b - o.b;
    if (c != o.c) return c - o.c;
    return (triplet ? 1 : 0) - (o.triplet ? 1 : 0);
  }

  String get key => '$a,$b,$c,${triplet ? 1 : 0}';

  @override
  String toString() => '($a,$b,$c${triplet ? " 刻" : " 順"})';
}

/// One reading of the concealed part: eye kind (may be kJoker = wildcard
/// eye) + sorted melds.
class Reading {
  final int eye;
  final List<RMeld> melds;
  const Reading(this.eye, this.melds);

  String get key => '$eye|${melds.map((m) => m.key).join(";")}';
}

int _compareReadings(Reading x, Reading y) {
  if (x.eye != y.eye) return x.eye - y.eye;
  for (var i = 0; i < x.melds.length && i < y.melds.length; i++) {
    final c = x.melds[i].compareTo(y.melds[i]);
    if (c != 0) return c;
  }
  return x.melds.length - y.melds.length;
}

// ── boolean win check (fast, memoized) ──────────────────────────────────

String _cntKey(List<int> cnt, int jk, int todo) =>
    '${String.fromCharCodes(cnt)}|$jk|$todo';

bool _canMelds(List<int> cnt, int jk, int todo, Map<String, bool> cache) {
  if (todo == 0) {
    return !cnt.any((c) => c != 0) && jk == 0;
  }
  var i = 0;
  while (i < numKinds && cnt[i] == 0) {
    i++;
  }
  if (i == numKinds) return jk == todo * 3;
  final key = _cntKey(cnt, jk, todo);
  final hit = cache[key];
  if (hit != null) return hit;
  var r = false;
  final c0 = cnt[i];
  // use copies of kind i as a triplet (pad with jokers only when it
  // consumes all remaining copies, to avoid stranded tiles)
  if (c0 >= 3) {
    cnt[i] -= 3;
    r = _canMelds(cnt, jk, todo - 1, cache);
    cnt[i] += 3;
  }
  if (!r && c0 < 3 && jk >= 3 - c0) {
    cnt[i] = 0;
    r = _canMelds(cnt, jk - (3 - c0), todo - 1, cache);
    cnt[i] = c0;
  }
  // runs starting at i (first tile real — i is the lowest occupied kind)
  if (!r && isSuitedKind(i) && i % 9 <= 6) {
    final b = i + 1, c = i + 2;
    outer:
    for (final jb in [0, 1]) {
      if (jb == 1 && jk < 1) continue;
      if (jb == 0 && cnt[b] == 0) continue;
      for (final jc in [0, 1]) {
        final uj = jb + jc;
        if (jk < uj) continue;
        if (jc == 0 && cnt[c] == 0) continue;
        cnt[i] -= 1;
        if (jb == 0) cnt[b] -= 1;
        if (jc == 0) cnt[c] -= 1;
        if (_canMelds(cnt, jk - uj, todo - 1, cache)) r = true;
        cnt[i] += 1;
        if (jb == 0) cnt[b] += 1;
        if (jc == 0) cnt[c] += 1;
        if (r) break outer;
      }
    }
  }
  cache[key] = r;
  return r;
}

int _sum(List<int> xs) {
  var s = 0;
  for (final x in xs) {
    s += x;
  }
  return s;
}

bool winsStandard(List<int> counts, int jokers, int needMelds,
    {bool jokerInEye = true}) {
  if (_sum(counts) + jokers != needMelds * 3 + 2) return false;
  final cache = <String, bool>{};
  for (var eye = 0; eye < numKinds; eye++) {
    if (counts[eye] >= 2) {
      counts[eye] -= 2;
      final ok = _canMelds(counts, jokers, needMelds, cache);
      counts[eye] += 2;
      if (ok) return true;
    }
    if (jokerInEye && counts[eye] == 1 && jokers >= 1) {
      counts[eye] -= 1;
      final ok = _canMelds(counts, jokers - 1, needMelds, cache);
      counts[eye] += 1;
      if (ok) return true;
    }
  }
  if (jokerInEye && jokers >= 2) {
    return _canMelds(counts, jokers - 2, needMelds, cache);
  }
  return false;
}

// ── enumeration for scoring (jokers resolved) ───────────────────────────

void _enumMelds(List<int> cnt, int jk, int todo, Map<String, List<RMeld>> out,
    List<RMeld> acc, int limit) {
  if (out.length >= limit) return;
  if (todo == 0) {
    if (!cnt.any((c) => c != 0) && jk == 0) {
      final sorted = [...acc]..sort();
      out.putIfAbsent(sorted.map((m) => m.key).join(';'), () => sorted);
    }
    return;
  }
  var i = 0;
  while (i < numKinds && cnt[i] == 0) {
    i++;
  }
  if (i == numKinds) {
    if (jk == todo * 3) {
      // pure-joker melds: mark as wildcard triplets (JOKER,JOKER,JOKER)
      final sorted = [
        ...acc,
        for (var t = 0; t < todo; t++) const RMeld(kJoker, kJoker, kJoker, true)
      ]..sort();
      out.putIfAbsent(sorted.map((m) => m.key).join(';'), () => sorted);
    }
    return;
  }
  final c0 = cnt[i];
  if (c0 >= 3) {
    cnt[i] -= 3;
    _enumMelds(cnt, jk, todo - 1, out, [...acc, RMeld(i, i, i, true)], limit);
    cnt[i] += 3;
  }
  if (c0 < 3 && jk >= 3 - c0) {
    cnt[i] = 0;
    _enumMelds(cnt, jk - (3 - c0), todo - 1, out,
        [...acc, RMeld(i, i, i, true)], limit);
    cnt[i] = c0;
  }
  if (isSuitedKind(i) && i % 9 <= 6) {
    final b = i + 1, c = i + 2;
    for (final jb in [0, 1]) {
      if ((jb == 1 && jk < 1) || (jb == 0 && cnt[b] == 0)) continue;
      for (final jc in [0, 1]) {
        final uj = jb + jc;
        if (jk < uj || (jc == 0 && cnt[c] == 0)) continue;
        cnt[i] -= 1;
        if (jb == 0) cnt[b] -= 1;
        if (jc == 0) cnt[c] -= 1;
        _enumMelds(cnt, jk - uj, todo - 1, out,
            [...acc, RMeld(i, b, c, false)], limit);
        cnt[i] += 1;
        if (jb == 0) cnt[b] += 1;
        if (jc == 0) cnt[c] += 1;
      }
    }
  }
}

/// All (eye, melds) readings of the concealed part, jokers resolved, in
/// canonical order (eye asc, melds lexicographic — the cross-language
/// 高點法 tie-break contract).
List<Reading> enumerateStandard(List<int> counts, int jokers, int needMelds,
    {bool jokerInEye = true, int limit = 200}) {
  if (_sum(counts) + jokers != needMelds * 3 + 2) return [];
  final readings = <Reading>[];
  for (var eye = 0; eye < numKinds; eye++) {
    final eyeOpts = <int>[];
    if (counts[eye] >= 2) eyeOpts.add(0);
    if (jokerInEye && counts[eye] == 1 && jokers >= 1) eyeOpts.add(1);
    for (final uj in eyeOpts) {
      counts[eye] -= 2 - uj;
      final melds = <String, List<RMeld>>{};
      _enumMelds(counts, jokers - uj, needMelds, melds, [], limit);
      counts[eye] += 2 - uj;
      for (final m in melds.values) {
        readings.add(Reading(eye, m));
      }
    }
  }
  if (jokerInEye && jokers >= 2) {
    final melds = <String, List<RMeld>>{};
    _enumMelds(counts, jokers - 2, needMelds, melds, [], limit);
    for (final m in melds.values) {
      readings.add(Reading(kJoker, m)); // wildcard eye
    }
  }
  // dedupe + canonical sort (see library docs)
  final seen = <String>{};
  final finalList = <Reading>[];
  for (final r in readings) {
    if (seen.add(r.key)) finalList.add(r);
  }
  finalList.sort(_compareReadings);
  return finalList;
}

// ── special forms (concealed hands; 17 tiles unless noted) ──────────────

/// 嚦咕嚦咕: 7 pairs + 1 triplet, fully concealed. 4-of-kind counts as
/// two pairs. VERIFY-12.
bool winsLiku(List<int> counts, int jokers) {
  if (_sum(counts) + jokers != 17) return false;
  for (var t = 0; t < numKinds; t++) {
    for (final real in [3, 2, 1]) {
      if (counts[t] < real) continue;
      final left = counts[t] - real;
      if (left != 0 && left != 1 && left != 2 && left != 4) continue;
      final uj = 3 - real;
      if (jokers < uj) continue;
      final rem = [...counts];
      rem[t] -= real;
      final rj = jokers - uj;
      var odd = 0;
      var bad = false;
      for (final c in rem) {
        if (c % 2 == 1) odd++;
        if (c == 3 || c > 4) bad = true;
      }
      if (bad) continue;
      if (odd <= rj && (rj - odd) % 2 == 0) return true;
    }
  }
  return false;
}

/// Pair kinds of a joker-free liku win (for 三元/四喜/八對 detectors).
/// Returns (tripletKind, pairs) or null.
(int, List<int>)? likuPairs(List<int> counts) {
  for (var t = 0; t < numKinds; t++) {
    if (counts[t] >= 3) {
      final rem = [...counts];
      rem[t] -= 3;
      if (rem.every((c) => c == 0 || c == 2 || c == 4)) {
        final pairs = <int>[];
        for (var k = 0; k < numKinds; k++) {
          for (var i = 0; i < rem[k] ~/ 2; i++) {
            pairs.add(k);
          }
        }
        return (t, pairs);
      }
    }
  }
  return null;
}

/// 十三么 (港式16張, VERIFY-11): 13 distinct 么九字 kinds + 1 extra orphan
/// (eye) + one ordinary 面子 (may be an exposed meld — at most 1).
bool winsThirteenOrphans(List<int> counts, int jokers, int nMelds) {
  if (nMelds > 1) return false;
  if (_sum(counts) + jokers != 17 - 3 * nMelds) return false;
  final cnt = [...counts];
  var jk = jokers;
  for (final k in orphanKinds) {
    if (cnt[k] >= 1) {
      cnt[k] -= 1;
    } else if (jk > 0) {
      jk -= 1;
    } else {
      return false;
    }
  }
  // eye partner: one more orphan (or joker)
  for (final k in orphanKinds) {
    if (cnt[k] >= 1) {
      final c2 = [...cnt];
      c2[k] -= 1;
      if (_restIsOneMeld(c2, jk, nMelds)) return true;
    }
  }
  if (jk >= 1 && _restIsOneMeld(cnt, jk - 1, nMelds)) return true;
  return false;
}

bool _restIsOneMeld(List<int> cnt, int jk, int nMelds) {
  final rem = _sum(cnt) + jk;
  if (nMelds == 1) return rem == 0;
  if (rem != 3) return false;
  return _canMelds(cnt, jk, 1, <String, bool>{});
}

/// 十六不搭: fully concealed; 16 pairwise-unconnected tiles, win tile
/// pairs one of them. No jokers (VERIFY).
bool winsSixteenDisjoint(List<int> counts, int jokers) {
  if (jokers != 0 || _sum(counts) != 17) return false;
  var pairs = 0;
  for (final c in counts) {
    if (c == 2) pairs++;
    if (c > 2) return false;
  }
  if (pairs != 1) return false;
  final kinds = [
    for (var k = 0; k < numKinds; k++)
      if (counts[k] >= 1) k
  ];
  if (kinds.length != 16) return false;
  for (var i = 0; i < kinds.length; i++) {
    for (var j = i + 1; j < kinds.length; j++) {
      final a = kinds[i], b = kinds[j];
      if (suitOf(a) == suitOf(b) && suitOf(a) <= 2 && b - a <= 2) {
        return false;
      }
    }
  }
  return true;
}

// ── top level ───────────────────────────────────────────────────────────

Set<String> winForms(List<int> counts, int jokers, int nMelds,
    {bool jokerInEye = true}) {
  final forms = <String>{};
  if (winsStandard(counts, jokers, 5 - nMelds, jokerInEye: jokerInEye)) {
    forms.add('standard');
  }
  if (nMelds == 0) {
    if (winsLiku(counts, jokers)) forms.add('liku');
    if (winsSixteenDisjoint(counts, jokers)) forms.add('sixteen');
  }
  if (winsThirteenOrphans(counts, jokers, nMelds)) forms.add('orphans');
  return forms;
}

/// All kinds t where hand+t wins — 聽牌 detection and 扇 counting.
List<int> winningKinds(List<int> counts, int jokers, int nMelds,
    {bool jokerInEye = true}) {
  final outs = <int>[];
  for (var t = 0; t < numKinds; t++) {
    if (counts[t] >= 4) continue;
    counts[t] += 1;
    if (winForms(counts, jokers, nMelds, jokerInEye: jokerInEye).isNotEmpty) {
      outs.add(t);
    }
    counts[t] -= 1;
  }
  return outs;
}

// ── shanten (L1 AI heuristic) ───────────────────────────────────────────

final Map<String, List<(int, int, bool)>> _blockCache = {};

/// Pareto-optimal (melds, partials, pairUsed) decompositions of one suit
/// block (or the honor block). Runs never cross suits, so blocks decompose
/// independently; the module-level cache makes shanten fast across a whole
/// game (hands repeat block patterns constantly).
List<(int, int, bool)> _blockOptions(List<int> block, bool suited) {
  final cacheKey = '${String.fromCharCodes(block)}|${suited ? 1 : 0}';
  final hit = _blockCache[cacheKey];
  if (hit != null) return hit;
  final out = <(int, int, bool)>{};
  final cnt = [...block];
  final n = cnt.length;

  void walk(int i, int m, int p, bool pair) {
    while (i < n && cnt[i] == 0) {
      i++;
    }
    if (i == n) {
      out.add((m, p, pair));
      return;
    }
    final c0 = cnt[i];
    if (c0 >= 3) {
      // triplet
      cnt[i] -= 3;
      walk(i, m + 1, p, pair);
      cnt[i] += 3;
    }
    if (suited && i <= n - 3 && cnt[i + 1] > 0 && cnt[i + 2] > 0) {
      // run
      cnt[i] -= 1;
      cnt[i + 1] -= 1;
      cnt[i + 2] -= 1;
      walk(i, m + 1, p, pair);
      cnt[i] += 1;
      cnt[i + 1] += 1;
      cnt[i + 2] += 1;
    }
    if (c0 >= 2) {
      cnt[i] -= 2;
      walk(i, m, p + 1, pair); // pair-as-partial
      if (!pair) walk(i, m, p, true); // the eye
      cnt[i] += 2;
    }
    if (suited) {
      for (final d in [1, 2]) {
        // edge/gap partial
        final j = i + d;
        if (j < n && cnt[j] > 0) {
          cnt[i] -= 1;
          cnt[j] -= 1;
          walk(i, m, p + 1, pair);
          cnt[i] += 1;
          cnt[j] += 1;
        }
      }
    }
    cnt[i] = 0; // drop this kind
    walk(i + 1, m, p, pair);
    cnt[i] = c0;
  }

  walk(0, 0, 0, false);
  // shanten is monotone nonincreasing in each component ⇒ dominated
  // options can never win; prune them
  bool geBool(bool x, bool y) => x || !y;
  final pruned = [
    for (final o in out)
      if (!out.any((o2) =>
          o2 != o &&
          o2.$1 >= o.$1 &&
          o2.$2 >= o.$2 &&
          geBool(o2.$3, o.$3)))
        o
  ];
  _blockCache[cacheKey] = pruned;
  return pruned;
}

/// Standard-form shanten (0 = 聽牌, -1 = win-shaped). Each joker reduces
/// by 1. Good enough for AI; legality uses exact win checks.
int shanten(List<int> counts, int jokers, int nMeldsExposed) {
  final need = 5 - nMeldsExposed;
  final blocks = [
    _blockOptions(counts.sublist(0, 9), true),
    _blockOptions(counts.sublist(9, 18), true),
    _blockOptions(counts.sublist(18, 27), true),
    _blockOptions(counts.sublist(27, 34), false),
  ];
  var best = 99;
  for (final (am, ap, ax) in blocks[0]) {
    for (final (bm, bp, bx) in blocks[1]) {
      for (final (cm, cp, cx) in blocks[2]) {
        for (final (dm, dp, dx) in blocks[3]) {
          final m = am + bm + cm + dm;
          final p = ap + bp + cp + dp;
          final useful = m < need ? m : need;
          var partials = need - useful;
          if (p < partials) partials = p;
          final s = (need - useful) * 2 -
              partials -
              ((ax || bx || cx || dx) ? 1 : 0);
          if (s < best) best = s;
        }
      }
    }
  }
  final r = best - jokers;
  return r < -1 ? -1 : r;
}
