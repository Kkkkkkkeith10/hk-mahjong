/// Fan (番種) recognizer — line-for-line port of ref_engine/fans.py.
/// Scores a winning hand against the FanTable (data/fan_table.json).
///
/// Pipeline (總例 p.10-11):
///   1. enumerate concealed readings (decompose.enumerateStandard)
///   2. per reading: detect pattern instances over the 5 melds (+eye)
///   3. 單式結算 (p.11 item 11): instances of the SAME 番種 co-count only
///      if every pair shares < 50% of their melds (例1-3). Different 番種
///      are unrestricted here — the 不複合 suppresses graph handles those.
///   4. apply the (transitive) suppresses graph from fan_table.json
///   5. 高點法 (item 10): max total across readings / placements
///   6. 嚦咕兩食 (item 12): standard + liku readings are ADDITIVE
///
/// 明/暗 variants: a pattern instance is 暗 iff every constituent meld is
/// concealed; a meld completed by the winning discard/搶槓 counts as
/// exposed (placement is enumerated; 高點法 picks the best).
///
/// DETERMINISM: awarded-fan maps are insertion-ordered (Dart Map default)
/// and all sorts are STABLE (mergesort helper below) so tie-breaking and
/// fan output order match the Python reference bit-for-bit.
library;

import 'decompose.dart';
import 'fan_table.dart';
import 'kinds.dart';

const Set<String> notImplemented = {
  'open_chain_loop', 'closed_chain_loop', // VERIFY-4 (連環套)
  'open_golden_gate', 'closed_golden_gate', // VERIFY-4 (金門橋)
  'mixed_court', 'pure_court', // VERIFY-6 (滿庭芳)
  'four_of_kind_hand', 'seven_of_kind_hand', // VERIFY-9
  'ten_of_kind_hand', // VERIFY-9
  'big_duck', // VERIFY (大鴨)
};

/// A meld for scoring.
class FM {
  final List<int> kinds; // 3 kind ints (kong: still 3, kong=true)
  final bool triplet;
  final bool concealed;
  final bool kong;
  const FM(this.kinds, this.triplet, this.concealed, {this.kong = false});
}

/// An exposed meld as the engine tracks it: (kind, mtype).
/// mtype: 'chow' (kind = low tile) | 'pung' | 'kong_exposed' |
/// 'kong_added' | 'kong_concealed'.
typedef Exposure = (int kind, String mtype);

/// Everything the recognizer needs about a win.
class Ctx {
  List<int> counts; // concealed tiles incl. winning tile
  int jokers;
  List<Exposure> exposed;
  int winKind;
  String winMethod; // discard | self_draw | rob_kong
  List<int> flowers; // ints 1..8
  int seat; // 0=E 1=S 2=W 3=N
  bool dealer;
  int dealerRepeatN;
  bool ting;
  String tingClass; // '' | heaven | earth | man
  bool instantEat;
  bool lastTile;
  bool flowerDraw;
  bool kongDraw;
  int tailChainN;
  int multiWin;
  String winClass; // '' | heaven_earth | man
  bool sevenRobOne;
  bool jokerInEye;

  Ctx({
    required this.counts,
    this.jokers = 0,
    List<Exposure>? exposed,
    this.winKind = -1,
    this.winMethod = 'discard',
    List<int>? flowers,
    this.seat = 0,
    this.dealer = false,
    this.dealerRepeatN = 0,
    this.ting = false,
    this.tingClass = '',
    this.instantEat = false,
    this.lastTile = false,
    this.flowerDraw = false,
    this.kongDraw = false,
    this.tailChainN = 0,
    this.multiWin = 1,
    this.winClass = '',
    this.sevenRobOne = false,
    this.jokerInEye = true,
  })  : exposed = exposed ?? [],
        flowers = flowers ?? [];
}

List<FM> exposedMelds(Ctx ctx) {
  final out = <FM>[];
  for (final (kind, mtype) in ctx.exposed) {
    switch (mtype) {
      case 'chow':
        out.add(FM([kind, kind + 1, kind + 2], false, false));
      case 'pung':
        out.add(FM([kind, kind, kind], true, false));
      case 'kong_concealed':
        out.add(FM([kind, kind, kind], true, true, kong: true));
      default: // kong_exposed / kong_added
        out.add(FM([kind, kind, kind], true, false, kong: true));
    }
  }
  return out;
}

// ── helpers ─────────────────────────────────────────────────────────────

/// Stable sort (Dart's List.sort is unstable; Python's is stable and the
/// fixture fan ordering depends on it).
void stableSortBy<T>(List<T> xs, int Function(T, T) cmp) {
  final decorated = [for (var i = 0; i < xs.length; i++) (xs[i], i)];
  decorated.sort((a, b) {
    final c = cmp(a.$1, b.$1);
    return c != 0 ? c : a.$2 - b.$2;
  });
  for (var i = 0; i < xs.length; i++) {
    xs[i] = decorated[i].$1;
  }
}

/// k-combinations of [xs] in itertools.combinations order
/// (lexicographic by index).
Iterable<List<T>> combos<T>(List<T> xs, int k) sync* {
  final n = xs.length;
  if (k > n) return;
  final idx = [for (var i = 0; i < k; i++) i];
  while (true) {
    yield [for (final i in idx) xs[i]];
    var i = k - 1;
    while (i >= 0 && idx[i] == i + n - k) {
      i--;
    }
    if (i < 0) return;
    idx[i]++;
    for (var j = i + 1; j < k; j++) {
      idx[j] = idx[j - 1] + 1;
    }
  }
}

// ── 單式結算: per-fan-id max multiset selection ─────────────────────────

/// An instance = set of meld indices (int) plus the eye marker 'E'.
typedef Instance = Set<Object>;

String _instKey(Instance inst) {
  final parts = [for (final x in inst) x.toString()]..sort();
  return parts.join(',');
}

/// Max count subset with pairwise shared/size < 0.5 (p.11 item 11).
int selectMax(List<Instance> instances) {
  // dedupe, then sort by stringified elements (stable, type-safe key —
  // mirrors Python's sorted(set(instances), key=...))
  final byKey = <String, Instance>{};
  for (final inst in instances) {
    byKey.putIfAbsent(_instKey(inst), () => inst);
  }
  final keys = byKey.keys.toList();
  // Python compares the sorted string-lists lexicographically; comparing
  // the ','-joined keys is NOT identical in general, so compare lists.
  final sortedElems = {
    for (final k in keys) k: k.split(',')
  };
  keys.sort((a, b) {
    final la = sortedElems[a]!, lb = sortedElems[b]!;
    for (var i = 0; i < la.length && i < lb.length; i++) {
      final c = la[i].compareTo(lb[i]);
      if (c != 0) return c;
    }
    return la.length - lb.length;
  });
  final uniq = [for (final k in keys) byKey[k]!];
  var best = 0;

  bool ok(Instance a, List<Instance> chosen) {
    for (final b in chosen) {
      final inter = a.intersection(b).length;
      final minLen = a.length < b.length ? a.length : b.length;
      if (2 * inter >= minLen) return false; // shared/size >= 0.5
    }
    return true;
  }

  void dfs(int i, List<Instance> chosen) {
    if (chosen.length + uniq.length - i <= best) return;
    if (i == uniq.length) {
      if (chosen.length > best) best = chosen.length;
      return;
    }
    if (ok(uniq[i], chosen)) {
      chosen.add(uniq[i]);
      dfs(i + 1, chosen);
      chosen.removeLast();
    }
    dfs(i + 1, chosen);
  }

  dfs(0, []);
  return best;
}

// ── pattern instance detection over one reading ─────────────────────────

/// 雜 suit rule: consecutive differ + all three suits appear.
bool _cycle3(List<int> suits) {
  if (suits.toSet().length != 3) return false;
  for (var i = 0; i < suits.length - 1; i++) {
    if (suits[i] == suits[i + 1]) return false;
  }
  return true;
}

typedef _Run = (int i, int s, int r, bool c);
typedef _Trip = (int i, int k, bool c);

/// ms: 5 melds. eye: kind (may be kJoker = wildcard).
/// Returns insertion-ordered map fan_id -> instances.
Map<String, List<Instance>> readingInstances(List<FM> ms, int eye) {
  final inst = <String, List<Instance>>{};

  void add(String fid, Iterable<Object> idx) {
    inst.putIfAbsent(fid, () => []).add({...idx});
  }

  final runs = <_Run>[
    for (var i = 0; i < ms.length; i++)
      if (!ms[i].triplet)
        (i, suitOf(ms[i].kinds[0]), rankOf(ms[i].kinds[0]), ms[i].concealed)
  ];
  final trips = <_Trip>[
    for (var i = 0; i < ms.length; i++)
      if (ms[i].triplet && ms[i].kinds[0] != kJoker)
        (i, ms[i].kinds[0], ms[i].concealed)
  ];
  final strips = <_Run>[
    for (final (i, k, c) in trips)
      if (isSuitedKind(k)) (i, suitOf(k), rankOf(k), c)
  ];
  final eyeSuited = eye != kJoker && isSuitedKind(eye);
  final es = eyeSuited ? suitOf(eye) : -1;
  final er = eyeSuited ? rankOf(eye) : -1;

  void oc(String prefix, List<bool> concs, Iterable<Object> idx) {
    add((concs.every((c) => c) ? 'closed_' : 'open_') + prefix, idx);
  }

  // — same-rank / identical runs —
  for (final pair in combos(runs, 2)) {
    final (i, si, ri, _) = pair[0];
    final (j, sj, rj, _) = pair[1];
    if (ri != rj) continue;
    add(si == sj ? 'identical_seq_pair' : 'mixed_double_seq', [i, j]);
  }
  for (final c3 in combos(runs, 3)) {
    final idx = [for (final r in c3) r.$1];
    final suits = [for (final r in c3) r.$2];
    final ranks = [for (final r in c3) r.$3];
    final concs = [for (final r in c3) r.$4];
    if (ranks.toSet().length != 1) continue;
    final ns = suits.toSet().length;
    if (ns == 3) {
      oc('triple_meet', concs, idx);
    } else if (ns == 1) {
      oc('pure_triple_seq', concs, idx);
    }
  }
  for (final c4 in combos(runs, 4)) {
    final idx = [for (final r in c4) r.$1];
    final suits = [for (final r in c4) r.$2];
    final ranks = [for (final r in c4) r.$3];
    final concs = [for (final r in c4) r.$4];
    if (ranks.toSet().length != 1) continue;
    if (suits.toSet().length == 1) {
      oc('pure_quad_seq', concs, idx);
    } else {
      add('four_same_seq', idx);
    }
  }
  if (runs.length == 5) {
    final ranks = [for (final r in runs) r.$3];
    final suits = [for (final r in runs) r.$2];
    if (ranks.toSet().length == 1 && suits.toSet().length > 1) {
      add('five_same_seq', [for (final r in runs) r.$1]);
    }
  }
  // 雙同順 / 雙般高: two disjoint pairs, distinguishable (p.11 例2)
  void doublePairs(String fidDouble, bool sameSuit) {
    final pairs = <(Set<int>, (int, int))>[
      for (final p in combos(runs, 2))
        if (p[0].$3 == p[1].$3 && (p[0].$2 == p[1].$2) == sameSuit)
          ({p[0].$1, p[1].$1}, (p[0].$2, p[0].$3))
    ];
    for (final q in combos(pairs, 2)) {
      final (pa, ka) = q[0];
      final (pb, kb) = q[1];
      if (ka != kb && pa.intersection(pb).isEmpty) {
        add(fidDouble, {...pa, ...pb});
      }
    }
  }

  doublePairs('double_same_seq', false);
  doublePairs('double_identical_seq', true);
  // 老少順
  final ts = <(Set<int>, int)>[
    for (final p in combos(runs, 2))
      if (p[0].$2 == p[1].$2 &&
          {p[0].$3, p[1].$3}.containsAll({1, 7}) &&
          {1, 7}.containsAll({p[0].$3, p[1].$3}))
        ({p[0].$1, p[1].$1}, p[0].$2)
  ];
  for (final (p, _) in ts) {
    add('terminal_seq', p);
  }
  for (final q in combos(ts, 2)) {
    final (pa, sa) = q[0];
    final (pb, sb) = q[1];
    if (sa != sb && pa.intersection(pb).isEmpty) {
      add('double_terminal_seq', {...pa, ...pb});
    }
  }
  // 龍 (ranks 1,4,7)
  for (final c3 in combos(runs, 3)) {
    final ranks = [for (final r in c3) r.$3]..sort();
    if (!(ranks[0] == 1 && ranks[1] == 4 && ranks[2] == 7)) continue;
    final idx = [for (final r in c3) r.$1];
    final suits = [for (final r in c3) r.$2];
    final concs = [for (final r in c3) r.$4];
    final ns = suits.toSet().length;
    if (ns == 1) {
      oc('pure_dragon', concs, idx);
    } else if (ns == 3) {
      oc('mixed_dragon', concs, idx);
    }
  }
  // 步高 (step 1 or 2)
  for (final (n, name) in [(3, '3step'), (4, '4step'), (5, '5step')]) {
    for (final cn in combos(runs, n)) {
      final cs = [...cn];
      stableSortBy(cs, (a, b) => a.$3 - b.$3);
      final idx = [for (final r in cs) r.$1];
      final suits = [for (final r in cs) r.$2];
      final ranks = [for (final r in cs) r.$3];
      final concs = [for (final r in cs) r.$4];
      final step = ranks[1] - ranks[0];
      if (step != 1 && step != 2) continue;
      var okStep = true;
      for (var k = 0; k < n - 1; k++) {
        if (ranks[k + 1] - ranks[k] != step) okStep = false;
      }
      if (!okStep) continue;
      if (suits.toSet().length == 1) {
        oc('pure_$name', concs, idx);
      } else if (_cycle3(suits)) {
        oc('mixed_$name', concs, idx);
      }
    }
  }

  // — triplet families (suited ranks) —
  for (final p in combos(strips, 2)) {
    final (i, si, ri, _) = p[0];
    final (j, sj, rj, _) = p[1];
    if (ri == rj && si != sj) {
      add('two_same_triplet', [i, j]);
      if (eyeSuited && er == ri && es != si && es != sj) {
        add('small_three_same_triplet', [i, j, 'E']);
      }
    }
    if (si == sj && (ri - rj).abs() == 1) {
      add('two_chain_triplet', [i, j]);
    }
    if (si == sj && ((ri == 1 && rj == 9) || (ri == 9 && rj == 1))) {
      add('terminal_triplet', [i, j]);
    }
  }
  for (final c3 in combos(strips, 3)) {
    final ranks = {for (final t in c3) t.$3};
    final suits = {for (final t in c3) t.$2};
    if (ranks.length == 1 && suits.length == 3) {
      add('three_same_triplet', [for (final t in c3) t.$1]);
    }
  }
  // 雙同刻 / 雙連刻 / 雙老少刻
  final stp = <(Set<int>, int)>[
    for (final p in combos(strips, 2))
      if (p[0].$3 == p[1].$3 && p[0].$2 != p[1].$2)
        ({p[0].$1, p[1].$1}, p[0].$3)
  ];
  for (final q in combos(stp, 2)) {
    final (pa, ra) = q[0];
    final (pb, rb) = q[1];
    if (ra != rb && pa.intersection(pb).isEmpty) {
      add('double_same_triplet', {...pa, ...pb});
    }
  }
  final ctp = <Set<int>>[
    for (final p in combos(strips, 2))
      if (p[0].$2 == p[1].$2 && (p[0].$3 - p[1].$3).abs() == 1)
        {p[0].$1, p[1].$1}
  ];
  for (final q in combos(ctp, 2)) {
    if (q[0].intersection(q[1]).isEmpty) {
      add('double_chain_triplet', {...q[0], ...q[1]});
    }
  }
  final ttp = <(Set<int>, int)>[
    for (final p in combos(strips, 2))
      if (p[0].$2 == p[1].$2 &&
          ((p[0].$3 == 1 && p[1].$3 == 9) || (p[0].$3 == 9 && p[1].$3 == 1)))
        ({p[0].$1, p[1].$1}, p[0].$2)
  ];
  for (final q in combos(ttp, 2)) {
    final (pa, sa) = q[0];
    final (pb, sb) = q[1];
    if (sa != sb && pa.intersection(pb).isEmpty) {
      add('double_terminal_triplet', {...pa, ...pb});
    }
  }
  // 連刻 chains, same suit
  const names = {
    3: 'three_chain_triplet',
    4: 'four_chain_triplet',
    5: 'five_chain_triplet'
  };
  const small = {
    3: 'small_three_chain_triplet',
    4: 'small_four_chain_triplet',
    5: 'small_five_chain_triplet',
    6: 'small_six_chain_triplet'
  };
  for (final n in [3, 4, 5]) {
    for (final cn in combos(strips, n)) {
      final cs = [...cn];
      stableSortBy(cs, (a, b) => a.$3 - b.$3);
      final suits = {for (final t in cs) t.$2};
      final ranks = [for (final t in cs) t.$3];
      var chained = suits.length == 1;
      for (var k = 0; k < n - 1 && chained; k++) {
        if (ranks[k + 1] - ranks[k] != 1) chained = false;
      }
      if (chained) {
        add(names[n]!, [for (final t in cs) t.$1]);
      }
    }
  }
  // 小N連刻: (N-1) chained trips + eye adjacent, same suit
  for (final n in [2, 3, 4, 5]) {
    if (!eyeSuited) break;
    for (final cn in combos(strips, n)) {
      final cs = [...cn];
      stableSortBy(cs, (a, b) => a.$3 - b.$3);
      final suits = [for (final t in cs) t.$2];
      final ranks = [for (final t in cs) t.$3];
      if (suits.toSet().length != 1 || suits[0] != es) continue;
      var chained = true;
      for (var k = 0; k < n - 1; k++) {
        if (ranks[k + 1] - ranks[k] != 1) chained = false;
      }
      if (!chained) continue;
      if (er == ranks[0] - 1 || er == ranks[ranks.length - 1] + 1) {
        add(small[n + 1]!, [...[for (final t in cs) t.$1], 'E']);
      }
    }
  }
  // 三色連刻 (rotating suits)
  const mnames = {
    3: 'mixed_chain_triplet',
    4: 'mixed_4chain_triplet',
    5: 'mixed_5chain_triplet'
  };
  const msmall = {
    3: 'small_mixed_chain_triplet',
    4: 'small_mixed_4chain_triplet',
    5: 'small_mixed_5chain_triplet',
    6: 'small_mixed_6chain_triplet'
  };
  for (final n in [3, 4, 5]) {
    for (final cn in combos(strips, n)) {
      final cs = [...cn];
      stableSortBy(cs, (a, b) => a.$3 - b.$3);
      final suits = [for (final t in cs) t.$2];
      final ranks = [for (final t in cs) t.$3];
      var chained = true;
      for (var k = 0; k < n - 1; k++) {
        if (ranks[k + 1] - ranks[k] != 1) chained = false;
      }
      if (!chained) continue;
      if (_cycle3(suits)) {
        add(mnames[n]!, [for (final t in cs) t.$1]);
      }
    }
  }
  for (final n in [2, 3, 4, 5]) {
    // 小三色N連刻: eye extends the chain
    if (!eyeSuited) break;
    for (final cn in combos(strips, n)) {
      final cs = [...cn];
      stableSortBy(cs, (a, b) => a.$3 - b.$3);
      final suits = [for (final t in cs) t.$2];
      final ranks = [for (final t in cs) t.$3];
      var chained = true;
      for (var k = 0; k < n - 1; k++) {
        if (ranks[k + 1] - ranks[k] != 1) chained = false;
      }
      if (!chained) continue;
      for (final (pos, rEye) in [(0, ranks[0] - 1), (1, ranks[ranks.length - 1] + 1)]) {
        if (er != rEye) continue;
        final full = pos == 0 ? [es, ...suits] : [...suits, es];
        if (_cycle3(full)) {
          add(msmall[n + 1]!, [...[for (final t in cs) t.$1], 'E']);
        }
      }
    }
  }
  return inst;
}

// ── whole-hand / composition fans on a reading ──────────────────────────

/// All 17 tile kinds of the reading (kong extra tile ignored).
List<int> _fullKinds(List<FM> ms, int eye) {
  final ks = [eye, eye];
  for (final m in ms) {
    ks.addAll(m.kinds);
  }
  return ks;
}

/// Tile-composition fans shared by standard + special forms.
/// ks: list of 17 kinds (jokers resolved as kJoker); ms may be null
/// (special forms).
void compositionFans(
    List<int> ks, List<FM>? ms, Ctx ctx, void Function(String, [int]) award) {
  final suited = [
    for (final k in ks)
      if (k != kJoker && isSuitedKind(k)) k
  ];
  final honors = [
    for (final k in ks)
      if (k != kJoker && isHonorKind(k)) k
  ];
  final suits = {for (final k in suited) suitOf(k)};
  if (honors.isEmpty) {
    award('no_honors');
    if (!suited.any(isTerminalKind)) award('no_terminals');
    if (ctx.flowers.isEmpty) award('no_honor_no_flower');
  }
  if (!ks.any((k) => k != kJoker && isSuitedKind(k) && rankOf(k) == 5)) {
    award('missing_five');
  }
  if (suits.length == 2) award('missing_one_suit');
  // 五門/七門 — VERIFY definitions (presence-based 小, set-based 大)
  final winds = [
    for (final k in honors)
      if (k < kindDragon) k
  ];
  final drags = [
    for (final k in honors)
      if (k >= kindDragon) k
  ];
  if (suits.length == 3 && winds.isNotEmpty && drags.isNotEmpty) {
    award('small_five_types');
    if (ctx.flowers.isNotEmpty && ctx.jokers > 0) award('small_seven_types');
    if (ms != null) {
      final wt = ms.any((m) =>
          m.triplet && kindWind <= m.kinds[0] && m.kinds[0] < kindDragon);
      final dt = ms.any((m) => m.triplet && m.kinds[0] >= kindDragon);
      final rsuits = {
        for (final m in ms)
          if (m.kinds[0] != kJoker && isSuitedKind(m.kinds[0]))
            suitOf(m.kinds[0])
      };
      if (wt && dt && rsuits.length == 3) {
        award('big_five_types');
        if (ctx.flowers.isNotEmpty && ctx.jokers > 0) {
          award('big_seven_types');
        }
      }
    }
  }
  if (honors.isNotEmpty && suits.length == 1) award('mixed_one_suit');
  if (honors.isEmpty && suits.length == 1 && suited.isNotEmpty) {
    award('pure_one_suit');
  }
  if (suited.isEmpty && honors.isNotEmpty) award('all_honors');
  final orphanOnly = ks.every((k) => k == kJoker || isOrphanKind(k));
  final termOnly = ks.every((k) => k == kJoker || isTerminalKind(k));
  if (termOnly) {
    award('pure_terminals');
  } else if (orphanOnly) {
    award('mixed_terminals');
  }
}

void flowerFans(Ctx ctx, void Function(String, [int]) award) {
  final fl = ctx.flowers;
  if (fl.isEmpty) {
    award('no_flowers');
  } else {
    award('flower_tile', fl.length);
    final mine = {ctx.seat + 1, ctx.seat + 5};
    final sf = fl.where(mine.contains).length;
    if (sf > 0) award('seat_flower', sf);
    var sets = 0;
    final flSet = fl.toSet();
    for (final grp in [
      {1, 2, 3, 4},
      {5, 6, 7, 8}
    ]) {
      if (flSet.containsAll(grp)) sets++;
    }
    if (sets > 0) award('one_set_flowers', sets);
  }
  if (fl.length == 8) award('eight_immortals');
  if (ctx.sevenRobOne) award('seven_rob_one');
}

void situationalFans(
    Ctx ctx, bool munChing, void Function(String, [int]) award) {
  if (ctx.ting) award('ting');
  if (ctx.tingClass.isNotEmpty) award('${ctx.tingClass}_ting');
  if (munChing) award('mun_ching');
  if (ctx.winMethod == 'self_draw') {
    award('self_draw');
    if (munChing) award('mun_mo');
  }
  if (ctx.ting && munChing) award('mun_ting');
  if (ctx.instantEat) award('instant_eat');
  if (ctx.lastTile) award('last_tile');
  if (ctx.winMethod == 'rob_kong') award('rob_kong');
  if (ctx.flowerDraw) award('flower_draw');
  if (ctx.kongDraw) award('kong_draw');
  if (ctx.tailChainN > 0) award('tail_chain_draw', ctx.tailChainN);
  if (ctx.multiWin == 2) {
    award('double_win');
  } else if (ctx.multiWin == 3) {
    award('triple_win');
  }
  if (ctx.dealer) award('dealer');
  if (ctx.dealerRepeatN > 0) award('dealer_repeat', ctx.dealerRepeatN);
  if (ctx.winClass == 'heaven_earth') {
    award('heaven_earth_win');
  } else if (ctx.winClass == 'man') {
    award('man_win');
  }
}

// ── standard-form reading score ─────────────────────────────────────────

bool _munChing(Ctx ctx) =>
    !ctx.exposed.any((e) => e.$2 != 'kong_concealed');

/// Score one reading (melds already concealment-adjusted).
Map<String, int> _scoreReading(
    List<FM> ms, int eye, Ctx ctx, FanTable table, List<int>? outs) {
  final awarded = <String, int>{};

  void award(String fid, [int times = 1]) {
    if (notImplemented.contains(fid) || !table.byId.containsKey(fid)) return;
    if (!table.enabled(fid)) return;
    awarded[fid] = (awarded[fid] ?? 0) + times;
  }

  // pattern instances under 單式結算
  readingInstances(ms, eye).forEach((fid, sets) {
    final n = selectMax(sets);
    if (n > 0) award(fid, n);
  });

  final trips = [
    for (final m in ms)
      if (m.triplet) m
  ];
  // 暗刻 count
  final nc = trips.where((m) => m.concealed).length;
  for (final (n, fid) in [
    (5, 'five_concealed'),
    (4, 'four_concealed'),
    (3, 'three_concealed'),
    (2, 'two_concealed')
  ]) {
    if (nc == n) {
      award(fid);
      break;
    }
  }
  final nk = ms.where((m) => m.kong).length;
  if (nk > 0) award('kong', nk);
  // honor sets
  final ht = trips.where((m) => isHonorKind(m.kinds[0])).length;
  if (ht > 0) award('honor_tiles', ht);
  if (trips.any((m) => m.kinds[0] == kindWind + ctx.seat)) {
    award('seat_honor');
  }
  final d3 = trips
      .where((m) => m.kinds[0] >= kindDragon && m.kinds[0] < kJoker)
      .length;
  final w3 = trips
      .where((m) => kindWind <= m.kinds[0] && m.kinds[0] < kindDragon)
      .length;
  final eyeDragon = kindDragon <= eye && eye < kJoker;
  final eyeWind = kindWind <= eye && eye < kindDragon;
  if (d3 == 3) {
    award('big_three_dragons');
  } else if (d3 == 2 && eyeDragon) {
    award('small_three_dragons');
  }
  if (w3 == 4) {
    award('big_four_winds');
  } else if (w3 == 3 && eyeWind) {
    award('small_four_winds');
  } else if (w3 == 3) {
    award('big_three_winds');
  } else if (w3 == 2 && eyeWind) {
    award('small_three_winds');
  }
  // whole-hand shapes
  if (trips.length == 5) {
    award('all_triplets');
    if (trips.every((m) => m.concealed) &&
        ctx.winMethod == 'self_draw' &&
        !ctx.exposed.any((e) => e.$2 != 'kong_concealed')) {
      award('all_concealed_triplets'); // 坎坎糊 VERIFY-5
    }
  }
  if (trips.isEmpty) {
    award('common_hand');
    if (ctx.flowers.isEmpty &&
        !isHonorKind(eye) &&
        !ms.any((m) => m.kinds.any(isHonorKind))) {
      award('big_common'); // 大平 VERIFY-3
    }
  }
  // 帶么 families (every set incl. eye holds orphan / terminal)
  bool hasT(List<int> kinds) =>
      kinds.any((k) => k != kJoker && isTerminalKind(k));
  bool hasO(List<int> kinds) =>
      kinds.any((k) => k != kJoker && isOrphanKind(k));
  if (ms.every((m) => hasO(m.kinds)) &&
      (eye == kJoker || isOrphanKind(eye))) {
    final honorsUsed = ms.any(
            (m) => m.kinds.any((k) => k != kJoker && isHonorKind(k))) ||
        isHonorKind(eye);
    if (ms.every((m) => hasT(m.kinds)) &&
        (eye == kJoker || isTerminalKind(eye)) &&
        !honorsUsed) {
      award('pure_terminal_sets');
    } else if (honorsUsed) {
      award('mixed_terminal_sets');
    } else {
      award('pure_terminal_sets');
    }
  }
  // 四歸 (VERIFY-7)
  final ks = _fullKinds(ms, eye);
  var quadKinds = 0;
  for (var k = 0; k < numKinds; k++) {
    if (!isSuitedKind(k)) continue;
    if (ks.where((x) => x == k).length != 4) continue;
    if (ms.any((m) => m.kong && m.kinds[0] == k)) continue;
    quadKinds++;
    final inTrip = ms.any((m) => m.triplet && m.kinds[0] == k);
    final involved = [
      for (final m in ms)
        if (m.kinds.contains(k)) m
    ];
    final closed = involved.every((m) => m.concealed);
    if (eye == k) {
      award(closed ? 'closed_four_to_two' : 'open_four_to_two');
    } else if (inTrip) {
      award(closed ? 'closed_four_to_three' : 'open_four_to_three');
    } else {
      award(closed ? 'closed_four_to_four' : 'open_four_to_four');
    }
  }
  if (quadKinds >= 3) {
    award('eight_return');
    award('twelve_return');
  } else if (quadKinds == 2) {
    award('eight_return');
  }
  // composition + flowers + situational
  final munChing = _munChing(ctx);
  compositionFans(ks, ms, ctx, award);
  flowerFans(ctx, award);
  situationalFans(ctx, munChing, award);
  // wait shape
  _waitFans(ms, eye, ctx, outs, award);
  return awarded;
}

void _waitFans(List<FM> ms, int eye, Ctx ctx, List<int>? outs,
    void Function(String, [int]) award) {
  if (ctx.winKind < 0 || outs == null) return;
  if (outs.length == 1) {
    award('single_wait'); // 獨獨
    return;
  }
  final w = ctx.winKind;
  if (eye == w) {
    award('pair_eye_wait'); // 將眼
    return;
  }
  for (final m in ms) {
    if (!m.kinds.contains(w)) continue;
    if (m.triplet) {
      award('pair_call_win'); // 對碰
      return;
    }
    final a = m.kinds[0], b = m.kinds[1], c = m.kinds[2];
    if (w == b ||
        (w == c && rankOf(a) == 1) ||
        (w == a && rankOf(c) == 9)) {
      award('false_single'); // 假獨 (卡/邊 with other outs)
      return;
    }
  }
  // 兩面 or joker-resolved: no wait fan
}

// ── special forms ───────────────────────────────────────────────────────

Map<String, int> _scoreLiku(Ctx ctx, FanTable table) {
  final awarded = <String, int>{};

  void award(String fid, [int times = 1]) {
    if (table.byId.containsKey(fid) &&
        table.enabled(fid) &&
        !notImplemented.contains(fid)) {
      awarded[fid] = (awarded[fid] ?? 0) + times;
    }
  }

  award('liku_liku');
  final lp = ctx.jokers == 0 ? likuPairs(ctx.counts) : null;
  if (lp != null) {
    final (trip, pairs) = lp;
    final groups = [...pairs, trip];
    if (groups.toSet().length == 8) award('eight_pairs_liku'); // VERIFY-13
    var allDragons = true;
    for (var d = kindDragon; d < kindDragon + 3; d++) {
      if (!groups.contains(d)) allDragons = false;
    }
    if (allDragons) award('dragon_liku');
    var allWinds = true;
    for (var w = kindWind; w < kindWind + 4; w++) {
      if (!groups.contains(w)) allWinds = false;
    }
    if (allWinds) award('winds_liku');
    // 三色同對
    final pr = pairs.toSet();
    for (var r = 1; r <= 9; r++) {
      var all3 = true;
      for (var s = 0; s < 3; s++) {
        if (!pr.contains(s * 9 + r - 1)) all3 = false;
      }
      if (all3) award('three_suit_same_pair');
    }
    // 連對 (chain pairs incl. the triplet kind)
    var best = 0;
    final groupSet = groups.toSet();
    for (var s = 0; s < 3; s++) {
      final ranks = {
        for (final k in groupSet)
          if (isSuitedKind(k) && suitOf(k) == s) rankOf(k)
      };
      for (var r = 1; r <= 9; r++) {
        var n = 0;
        while (r + n <= 9 && ranks.contains(r + n)) {
          n++;
        }
        if (n > best) best = n;
      }
    }
    const names = {
      3: 'three_chain_pairs',
      4: 'four_chain_pairs',
      5: 'five_chain_pairs',
      6: 'six_chain_pairs',
      7: 'seven_chain_pairs',
      8: 'eight_chain_pairs'
    };
    if (best >= 3) award(names[best < 8 ? best : 8]!);
  }
  final ks = <int>[];
  for (var k = 0; k < numKinds; k++) {
    for (var i = 0; i < ctx.counts[k]; i++) {
      ks.add(k);
    }
  }
  compositionFans(ks, null, ctx, award);
  return awarded;
}

Map<String, int> _scoreSixteen(Ctx ctx, FanTable table, List<int>? outs) {
  final awarded = <String, int>{};

  void award(String fid, [int times = 1]) {
    if (table.byId.containsKey(fid) && table.enabled(fid)) {
      awarded[fid] = (awarded[fid] ?? 0) + times;
    }
  }

  award('sixteen_disjoint');
  final kinds = [
    for (var k = 0; k < numKinds; k++)
      if (ctx.counts[k] > 0) k
  ];
  if (outs != null && outs.length >= 16) award('sixteen_gates_disjoint');
  final byRank = <int, Set<int>>{};
  for (final k in kinds) {
    if (isSuitedKind(k)) {
      byRank.putIfAbsent(rankOf(k), () => {}).add(suitOf(k));
    }
  }
  if (byRank.values.any((s) => s.length == 3)) {
    award('disjoint_three_meet'); // VERIFY
  }
  final suited = kinds.where(isSuitedKind).toList();
  if (suited.length == 9) {
    final ranks = [for (final k in suited) rankOf(k)]..sort();
    var oneToNine = true;
    for (var i = 0; i < 9; i++) {
      if (ranks[i] != i + 1) oneToNine = false;
    }
    if (oneToNine) {
      final bySuit = <int, Set<int>>{};
      for (final k in suited) {
        bySuit.putIfAbsent(suitOf(k), () => {}).add(rankOf(k) % 3);
      }
      if (bySuit.length == 3 && bySuit.values.every((v) => v.length == 1)) {
        award('disjoint_mixed_dragon'); // VERIFY
      }
    }
  }
  return awarded;
}

Map<String, int> _scoreOrphans(Ctx ctx, FanTable table, List<int>? outs) {
  final awarded = <String, int>{'thirteen_orphans': 1};
  if (outs != null &&
      outs.length >= 13 &&
      table.enabled('thirteen_gates_orphans')) {
    awarded['thirteen_gates_orphans'] = 1;
  }
  return awarded;
}

// ── suppresses + totals ─────────────────────────────────────────────────

int _points(String fid, int n, FanTable table) {
  final e = table.byId[fid]!;
  if (e.formula != null) return table.value(fid, n);
  return e.value * n;
}

/// 不複合: the suppresses graph defines mutually exclusive alternative
/// countings; 高點法 keeps the max-total compatible subset (p.11 例2).
Map<String, int> _applySuppresses(Map<String, int> awarded, FanTable table) {
  final ids = awarded.keys.toList();
  stableSortBy(
      ids,
      (a, b) =>
          _points(b, awarded[b]!, table) - _points(a, awarded[a]!, table));
  final conf = {for (final f in ids) f: <String>{}};
  for (final a in ids) {
    for (final b in ids) {
      if (a != b &&
          (table.suppressedBy(a).contains(b) ||
              table.suppressedBy(b).contains(a))) {
        conf[a]!.add(b);
      }
    }
  }
  if (conf.values.every((s) => s.isEmpty)) return awarded;
  final pts = {for (final f in ids) f: _points(f, awarded[f]!, table)};
  var bestTot = -1;
  Map<String, int> bestSel = {};

  void dfs(int i, Map<String, int> cur, int tot, Set<String> blocked) {
    var rem = tot;
    for (var j = i; j < ids.length; j++) {
      if (!blocked.contains(ids[j])) rem += pts[ids[j]]!;
    }
    if (rem <= bestTot) return;
    if (i == ids.length) {
      bestTot = tot;
      bestSel = Map.of(cur); // insertion order preserved
      return;
    }
    final f = ids[i];
    if (!blocked.contains(f)) {
      cur[f] = awarded[f]!;
      dfs(i + 1, cur, tot + pts[f]!, {...blocked, ...conf[f]!});
      cur.remove(f);
    }
    dfs(i + 1, cur, tot, blocked);
  }

  dfs(0, {}, 0, {});
  return bestSel;
}

typedef FanLine = (String id, int n, int points);

(List<FanLine>, int) _finalize(Map<String, int> awarded, FanTable table) {
  final items = awarded.entries.toList();
  stableSortBy(
      items,
      (a, b) =>
          _points(b.key, b.value, table) - _points(a.key, a.value, table));
  final out = <FanLine>[];
  var total = 0;
  for (final it in items) {
    final pts = _points(it.key, it.value, table);
    out.add((it.key, it.value, pts));
    total += pts;
  }
  return (out, total);
}

class ScoreResult {
  final bool notAWin;
  final List<FanLine> fans;
  final int total;
  final String form;
  final Set<String> forms;
  const ScoreResult(
      {this.notAWin = false,
      this.fans = const [],
      this.total = 0,
      this.form = '',
      this.forms = const {}});
}

/// Score a winning hand. Returns ScoreResult (notAWin=true if the hand
/// doesn't win).
ScoreResult scoreWin(Ctx ctx, FanTable table) {
  final nExp = ctx.exposed.length;
  final forms =
      winForms(ctx.counts, ctx.jokers, nExp, jokerInEye: ctx.jokerInEye);
  if (forms.isEmpty) return const ScoreResult(notAWin: true);
  // pre-win waits (for 獨獨/扇 fans)
  List<int>? outs;
  if (0 <= ctx.winKind &&
      ctx.winKind < numKinds &&
      ctx.counts[ctx.winKind] > 0) {
    final pre = [...ctx.counts];
    pre[ctx.winKind] -= 1;
    outs = winningKinds(pre, ctx.jokers, nExp, jokerInEye: ctx.jokerInEye);
  }

  (List<FanLine>, int)? bestStd;
  if (forms.contains('standard')) {
    final exp = exposedMelds(ctx);
    for (final reading
        in enumerateStandard(ctx.counts, ctx.jokers, 5 - nExp,
            jokerInEye: ctx.jokerInEye)) {
      final eye = reading.eye;
      final base = [
        ...exp,
        for (final m in reading.melds)
          FM([m.a, m.b, m.c], m.triplet, true)
      ];
      var variants = [base];
      if ((ctx.winMethod == 'discard' || ctx.winMethod == 'rob_kong') &&
          ctx.winKind >= 0) {
        variants = [];
        for (var wi = exp.length; wi < base.length; wi++) {
          if (base[wi].kinds.contains(ctx.winKind)) {
            final v = [
              for (var i = 0; i < base.length; i++)
                FM(base[i].kinds, base[i].triplet,
                    base[i].concealed && i != wi,
                    kong: base[i].kong)
            ];
            variants.add(v);
          }
        }
        if (eye == ctx.winKind || variants.isEmpty) variants.add(base);
      }
      for (final msv in variants) {
        var aw = _scoreReading(msv, eye, ctx, table, outs);
        aw = _applySuppresses(aw, table);
        final (fans, tot) = _finalize(aw, table);
        if (bestStd == null || tot > bestStd.$2) bestStd = (fans, tot);
      }
    }
  }

  (List<FanLine>, int) special(Map<String, int> scorer) {
    final aw = Map<String, int>.of(scorer);
    final munChing = _munChing(ctx);

    void award(String fid, [int times = 1]) {
      if (table.byId.containsKey(fid) && table.enabled(fid)) {
        aw[fid] = (aw[fid] ?? 0) + times;
      }
    }

    flowerFans(ctx, award);
    situationalFans(ctx, munChing, award);
    if (outs != null && outs.length == 1) award('single_wait');
    final applied = _applySuppresses(aw, table);
    return _finalize(applied, table);
  }

  // insertion order matters: standard → liku → sixteen → orphans
  final results = <String, (List<FanLine>, int)>{};
  if (bestStd != null) results['standard'] = bestStd;
  if (forms.contains('liku')) results['liku'] = special(_scoreLiku(ctx, table));
  if (forms.contains('sixteen')) {
    results['sixteen'] = special(_scoreSixteen(ctx, table, outs));
  }
  if (forms.contains('orphans')) {
    results['orphans'] = special(_scoreOrphans(ctx, table, outs));
  }

  List<FanLine> fans;
  int total;
  String form;
  // 嚦咕兩食 (p.11 item 12): standard + liku are additive; otherwise 高點法
  if (results.containsKey('standard') && results.containsKey('liku')) {
    const likuOnly = {
      'liku_liku',
      'eight_pairs_liku',
      'dragon_liku',
      'winds_liku',
      'three_suit_same_pair'
    };
    fans = [
      ...results['standard']!.$1,
      for (final f in results['liku']!.$1)
        if (likuOnly.contains(f.$1) || f.$1.endsWith('_chain_pairs')) f
    ];
    total = 0;
    for (final f in fans) {
      total += f.$3;
    }
    form = 'liku_two_eat';
  } else {
    // first max wins (Python max() semantics over insertion order)
    String? bestForm;
    (List<FanLine>, int)? bestVal;
    for (final e in results.entries) {
      if (bestVal == null || e.value.$2 > bestVal.$2) {
        bestForm = e.key;
        bestVal = e.value;
      }
    }
    fans = bestVal!.$1;
    total = bestVal.$2;
    form = bestForm!;
  }

  // 大雞 (VERIFY): a win carrying zero fan
  if (total == 0 && table.enabled('big_chicken')) {
    final v = table.value('big_chicken');
    fans = [('big_chicken', 1, v)];
    total = v;
  }
  return ScoreResult(fans: fans, total: total, form: form, forms: forms);
}
