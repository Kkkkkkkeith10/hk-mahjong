/// Proves the deterministic-replay driver (replay.dart) reproduces the
/// live engine bit-for-bit, so multiplayer games ruled by MatchDriver are
/// exactly the golden-fixture-tested single-player rules.
///
/// Method: play a match directly with L1 bots where seat 0's policy is
/// wrapped in a recorder capturing every answer it gives at the prompts a
/// scripted seat would surface (same 叮 gate). Then:
///   1. full replay of the recorded log ⇒ identical event logs, results,
///      scores, dealer rotation, ledger;
///   2. incremental replay (prefixes of the log) ⇒ every intermediate run
///      parks at exactly the prompt the next recorded action answers;
///   3. malformed / out-of-turn actions ⇒ ReplayException, never corruption.
import 'dart:async';
import 'dart:io';

import 'package:mj_core/mj_core.dart';
import 'package:test/test.dart';

import 'golden_util.dart';

/// Wraps L1Policy for one seat, recording (type, value) pairs exactly where
/// _ScriptedSeat would prompt (so the log replays 1:1). Mirrors the 叮 gate.
class RecordingL1 extends GamePolicy {
  final int seat;
  final L1Policy inner = L1Policy();
  final List<SeatAction> log = [];
  RecordingL1(this.seat);

  T _rec<T>(String type, T v, [Object? Function(T)? enc]) {
    log.add(SeatAction(seat, type, enc == null ? v : enc(v)));
    return v;
  }

  // L1Policy is fully synchronous, so the FutureOr results are plain values;
  // the casts below are safe and let us record/encode them directly.
  @override
  FutureOr<List<int>> chooseSwap(Map<String, dynamic> view, int n) =>
      _rec('swap', inner.chooseSwap(view, n) as List<int>);

  @override
  FutureOr<int> chooseDiscard(Map<String, dynamic> view) =>
      _rec('discard', inner.chooseDiscard(view) as int);

  @override
  FutureOr<bool> wantWin(Map<String, dynamic> view) =>
      _rec('win', inner.wantWin(view) as bool);

  @override
  FutureOr<int?> wantTing(Map<String, dynamic> view) {
    if (!canDeclareTing(view)) return null; // gate: scripted seat won't prompt
    return _rec('ting', inner.wantTing(view) as int?);
  }

  @override
  FutureOr<(int, String)?> wantKong(
          Map<String, dynamic> view, List<(int, String)> options) =>
      _rec<(int, String)?>('kong', inner.wantKong(view, options) as (int, String)?,
          (c) => c == null ? null : [c.$1, c.$2]);

  @override
  FutureOr<String?> wantClaim(
          Map<String, dynamic> view, int kind, List<String> options) =>
      _rec('claim', inner.wantClaim(view, kind, options) as String?);

  @override
  FutureOr<int?> wantChow(
          Map<String, dynamic> view, int kind, List<int> lowOptions) =>
      _rec('chow', inner.wantChow(view, kind, lowOptions) as int?);
}

/// Direct match run mirroring MatchDriver's loop, recording seat 0.
Future<
    (
      List<SeatAction>,
      List<List<Map<String, dynamic>>>, // event log per hand
      List<int>, // final scores
      int, // final dealer
      int, // final repeatN
      List<(int, int, int, int)> // wiped ledger
    )> playDirect(FanTable table, MatchRules rules) async {
  final seeds = SplitMix64(rules.seed ^ 0x5EED);
  final ledger = LaLedger(table.settlement.laLedger);
  final scores = [0, 0, 0, 0];
  var dealer = 0, repeatN = 0;
  final rec = RecordingL1(0);
  final allEvents = <List<Map<String, dynamic>>>[];
  for (var h = 0; h < rules.totalHands; h++) {
    final eng = Engine(seeds.nextBounded(1 << 30), table,
        opts: EngineOptions(
            jokers: rules.jokers, swap: rules.swap, laOn: rules.laOn),
        dealer: dealer,
        repeatN: repeatN,
        ledger: rules.laOn ? ledger : null);
    final res = await eng.play([rec, L1Policy(), L1Policy(), L1Policy()]);
    allEvents.add([for (final e in eng.events) Map.of(e)]);
    for (final d in eng.deltas) {
      scores[d.frm] -= d.amount;
      scores[d.to] += d.amount;
    }
    if (res.dealerRepeats) {
      repeatN += 1;
    } else {
      dealer = (dealer + 1) % 4;
      repeatN = 0;
    }
  }
  final wiped = ledger.matchEnd();
  return (rec.log, allEvents, scores, dealer, repeatN, wiped);
}

void main() {
  late FanTable table;

  setUpAll(() {
    table = FanTable.fromJsonString(
        File('../data/fan_table.json').readAsStringSync());
  });

  // A spread of rule combos and seeds; jokers exercise 百搭 paths, swap
  // exercises 換牌 prompts, multiple hands exercise dealer rotation + 拉.
  final combos = [
    const MatchRules(seed: 9001, totalHands: 4),
    const MatchRules(seed: 9002, totalHands: 4, jokers: 4, swap: 'fixed3'),
    const MatchRules(seed: 9003, totalHands: 4, jokers: 8, swap: 'dice'),
    const MatchRules(seed: 9004, totalHands: 2, laOn: false),
    const MatchRules(seed: 9005, totalHands: 8),
  ];

  test('full replay reproduces the direct run bit-for-bit', () async {
    for (final rules in combos) {
      final label = 'seed=${rules.seed}';
      final (log, events, scores, dealer, repeatN, wiped) =
          await playDirect(table, rules);
      final snap = await MatchDriver(table, rules, {0}).run(log);
      expect(snap.matchOver, isTrue, reason: label);
      expect(snap.pending, isNull, reason: label);
      expect(snap.scores, scores, reason: label);
      expect(snap.dealer, dealer, reason: label);
      expect(snap.repeatN, repeatN, reason: label);
      expect(snap.wipedLedger, wiped, reason: label);
      // Last hand's event log must match exactly.
      expect(deepEq(snap.engine.events, events.last), isTrue,
          reason: '$label event log diverged:\n'
              'direct: ${pretty(events.last)}\n'
              'replay: ${pretty(snap.engine.events)}');
    }
  });

  test('incremental replay parks at exactly the next recorded prompt',
      () async {
    final rules = combos[1]; // jokers + swap: richest prompt mix
    final (log, _, _, _, _, _) = await playDirect(table, rules);
    final driver = MatchDriver(table, rules, {0});
    // Cap the walk to keep runtime sane; the full-log case is covered above.
    final steps = log.length < 60 ? log.length : 60;
    for (var i = 0; i < steps; i++) {
      final snap = await driver.run(log.sublist(0, i));
      expect(snap.matchOver, isFalse, reason: 'prefix $i');
      expect(snap.pending, isNotNull, reason: 'prefix $i');
      expect(snap.pending!.seat, log[i].seat, reason: 'prefix $i');
      expect(snap.pending!.type, log[i].type, reason: 'prefix $i');
      // Where botAnswerFor delegates to L1 (swap/discard/ting/win), it must
      // equal the recorded L1 answer — pinning AI takeover to the same code.
      // (kong/claim/chow timeouts deliberately decline instead.)
      if (const {'swap', 'discard', 'ting', 'win'}.contains(log[i].type)) {
        expect(deepEq(botAnswerFor(snap, snap.pending!), log[i].value), isTrue,
            reason: 'prefix $i bot answer');
      }
    }
  });

  test('bad actions raise ReplayException, not corruption', () async {
    final rules = combos[0];
    final (log, _, _, _, _, _) = await playDirect(table, rules);
    final driver = MatchDriver(table, rules, {0});
    // Out-of-order type.
    final wrongType = [SeatAction(0, 'chow', 3), ...log.skip(1)];
    expect(() => driver.run(wrongType), throwsA(isA<ReplayException>()));
    // Bot seat acting.
    expect(() => MatchDriver(table, rules, {0}).run([SeatAction(1, 'discard', 3)]),
        throwsA(isA<ReplayException>()));
    // Discarding a tile not in hand: find the first discard action and
    // replace its kind with one the hand cannot contain alongside it.
    final di = log.indexWhere((a) => a.type == 'discard');
    if (di >= 0) {
      final snap = await driver.run(log.sublist(0, di));
      final counts = snap.engine.players[0].counts;
      final missing = List.generate(numKinds, (k) => k)
          .firstWhere((k) => counts[k] == 0, orElse: () => -1);
      if (missing >= 0) {
        final bad = [...log.sublist(0, di), SeatAction(0, 'discard', missing)];
        expect(() => driver.run(bad), throwsA(isA<ReplayException>()));
      }
    }
    // JSON round trip of actions is lossless.
    for (final a in log.take(20)) {
      final back = SeatAction.fromJson(a.toJson());
      expect(back.seat, a.seat);
      expect(back.type, a.type);
      expect(deepEq(back.value, a.value), isTrue);
    }
  });

  test('clientView hides other hands and routes the prompt correctly',
      () async {
    final rules = combos[0];
    final (log, _, _, _, _, _) = await playDirect(table, rules);
    final driver = MatchDriver(table, rules, {0});
    final snap = await driver.run(log.sublist(0, 5));
    for (var s = 0; s < 4; s++) {
      final v = clientView(snap, s);
      expect(v.containsKey('counts'), isTrue);
      expect((v['players'] as List).length, 4);
      for (final q in v['players'] as List) {
        expect((q as Map).containsKey('counts'), isFalse,
            reason: 'opponent hand contents must never be in a client view');
      }
      if (snap.pending!.seat == s) {
        expect(v['prompt'], isNotNull);
      } else {
        expect(v['prompt'], isNull);
      }
      expect(v['waiting_on'], snap.pending!.seat);
    }
  });
}
