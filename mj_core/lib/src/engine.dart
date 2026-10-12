/// Game state machine — line-for-line port of ref_engine/engine.py.
///
/// One 局 (hand) of 港式台牌, driven by four GamePolicy objects. Emits a
/// full event log (the golden-fixture format this port is replay-tested
/// against). Policy methods return FutureOr so the same engine drives both
/// synchronous bots (L1Policy — replays stay deterministic) and the Flutter
/// client's HumanPolicy (Completers resolved by taps).
///
/// Rules implemented (總例 pp.3-9, p.11; VERIFY items marked):
///   配牌 4×4×4 (dealer draws the 17th as first-turn draw) · 補花 from
///   tail · 換牌 room option (fixed 3 or dice count, pass to 下家 —
///   direction VERIFY) · claims 食糊 > 碰/槓 > 上 · simultaneous winners
///   (雙響/三響) · 過水 (same-巡 block; 叮 decline = whole-局; declined
///   加槓 rob too) · 叮 (locked hand, rotated discards, 即食 window,
///   天/地叮) · 槓 (暗/明/加, tail replacement draw, 搶槓 vs 加槓 only,
///   暗槓 never robbable, 暗槓 instant 1底/家) · 海底 · 槓摸/花摸/
///   尾牌連摸 chain · 百搭 (may not be discarded — VERIFY) · 七搶一/
///   八仙過海 flower events end the 局 as 花糊 (rewards 拉落下一鋪, dealer
///   連莊 — VERIFY) · 流局 ⇒ 連莊.
library;

import 'dart:async';

import 'decompose.dart';
import 'fan_table.dart';
import 'fans.dart';
import 'kinds.dart';
import 'rng.dart';
import 'settle.dart';
import 'wall.dart';

class PlayerState {
  final List<int> counts = List.filled(numKinds, 0);
  int jokers = 0;
  final List<int> flowers = [];
  final List<Exposure> melds = [];
  final List<int> discards = [];
  bool ting = false;
  String tingClass = '';
  int tingTurn = -1; // turn counter at 叮 (for 即食)
  bool blockedTurn = false; // 過水 until own next draw
  bool blockedHand = false; // 叮過水: whole 局

  void add(String tid) {
    if (tid == 'J0') {
      jokers++;
    } else {
      counts[idToKind(tid)]++;
    }
  }

  void removeKind(int k, [int n = 1]) {
    assert(counts[k] >= n);
    counts[k] -= n;
  }

  int get handSize {
    var s = jokers;
    for (final c in counts) {
      s += c;
    }
    return s;
  }
}

class EngineOptions {
  final int jokers; // 0 | 4 | 8
  final String swap; // off | fixed3 | dice
  final bool laOn;
  final bool jokerInEye;

  EngineOptions(
      {this.jokers = 0,
      this.swap = 'off',
      this.laOn = true,
      this.jokerInEye = true}) {
    assert(jokers == 0 || jokers == 4 || jokers == 8);
    assert(swap == 'off' || swap == 'fixed3' || swap == 'dice');
  }
}

/// Per-win situational flags handed to the recognizer.
class WinFlags {
  final bool lastTile;
  final bool flowerDraw;
  final bool kongDraw;
  final bool instantEat;
  final int tailChainN;
  final int multiWin;
  final String winClass;
  const WinFlags(
      {this.lastTile = false,
      this.flowerDraw = false,
      this.kongDraw = false,
      this.instantEat = false,
      this.tailChainN = 0,
      this.multiWin = 1,
      this.winClass = ''});
}

class GameResult {
  final String kind; // win | exhaust | flower_hu
  final List<(int, ScoreResult)> winners;
  final int? discarder;
  final int? seat; // flower_hu winner
  final List<Delta> deltas;
  final bool dealerRepeats;
  const GameResult(this.kind,
      {this.winners = const [],
      this.discarder,
      this.seat,
      required this.deltas,
      required this.dealerRepeats});
}

/// Policy interface. Views are maps; kinds are ints. FutureOr returns:
/// bots answer synchronously, human policies may await UI input.
abstract class GamePolicy {
  FutureOr<List<int>> chooseSwap(Map<String, dynamic> view, int n);
  FutureOr<int> chooseDiscard(Map<String, dynamic> view);
  FutureOr<bool> wantWin(Map<String, dynamic> view) => true;

  /// Return the kind to discard while declaring 叮, or null.
  FutureOr<int?> wantTing(Map<String, dynamic> view) => null;
  FutureOr<(int, String)?> wantKong(
          Map<String, dynamic> view, List<(int, String)> options) =>
      null;
  FutureOr<String?> wantClaim(
          Map<String, dynamic> view, int kind, List<String> options) =>
      null;
  FutureOr<int?> wantChow(
          Map<String, dynamic> view, int kind, List<int> lowOptions) =>
      null;
}

class Engine {
  final EngineOptions opts;
  final SplitMix64 rng; // aux rng (dice), separate stream
  final Wall wall;
  final int dealer;
  final int repeatN;
  final FanTable table;
  final LaLedger? ledger;
  final List<PlayerState> players = [for (var i = 0; i < 4; i++) PlayerState()];
  final List<Map<String, dynamic>> events = [];
  int turnCount = 0; // increments on every head draw
  bool anyMeld = false; // any 鳴牌/暗槓 this 局
  int tailChain = 0; // current player's consecutive tail draws
  final List<Delta> deltas = [];
  GameResult? result;
  final Map<int, int> _lastWinKind = {};
  final Map<int, String> _winMethod = {};

  /// Optional live tap for UI consumers; fired on every logged event.
  void Function(Map<String, dynamic> event)? onEvent;

  Engine(int seed, this.table,
      {EngineOptions? opts, this.dealer = 0, this.repeatN = 0, this.ledger})
      : opts = opts ?? EngineOptions(),
        rng = SplitMix64(seed ^ 0xD1CE),
        wall = Wall.shuffled(seed, jokerCount: (opts ?? EngineOptions()).jokers);

  SettlementConfig get _cfg => table.settlement;

  // ── logging ─────────────────────────────────────────────────────────
  void log(String type, Map<String, dynamic> kw) {
    final e = {'type': type, ...kw};
    events.add(e);
    onEvent?.call(e);
  }

  /// Instant deltas are paid; la-flagged ones (花糊 rewards when
  /// flowerWinLa) are recorded to the ledger instead.
  void _applyDeltas(List<Delta> ds) {
    for (final d in ds) {
      if (d.la && ledger != null) {
        ledger!.record(d.to, d.frm, d.amount);
      } else {
        deltas.add(d);
      }
    }
  }

  // ── setup ───────────────────────────────────────────────────────────
  Future<void> _deal(List<GamePolicy> policies) async {
    final hands = wall.dealInitial();
    final handIds = [
      for (final h in hands) [for (final t in h) t.id]
    ];
    for (var s = 0; s < 4; s++) {
      for (final tid in handIds[s]) {
        if (tid[0] == 'X') {
          players[s].flowers.add(int.parse(tid.substring(1)));
        } else {
          players[s].add(tid);
        }
      }
    }
    log('deal', {'hands': handIds});
    // 換牌 (before 補花 — VERIFY ordering)
    if (opts.swap != 'off') {
      final n = opts.swap == 'fixed3' ? 3 : rng.nextBounded(6) + 1;
      log('swap_count', {'n': n});
      final gives = <List<int>>[];
      for (var s = 0; s < 4; s++) {
        final g = await policies[s].chooseSwap(_view(s), n);
        assert(g.length == n);
        for (final k in g) {
          players[s].removeKind(k);
        }
        gives.add(g);
      }
      for (var s = 0; s < 4; s++) {
        // pass to 下家 (VERIFY direction)
        for (final k in gives[s]) {
          players[(s + 1) % 4].counts[k] += 1;
        }
      }
      log('swap', {'gives': gives});
    }
    // 補花 in seat-order rounds from tail (flowers were set aside at
    // deal, so handSize < 16 marks how many replacements are owed)
    var changed = true;
    while (changed) {
      changed = false;
      for (var s = 0; s < 4; s++) {
        final p = players[s];
        final need = 16 - p.handSize;
        for (var i = 0; i < need; i++) {
          final tid = wall.drawTail().id;
          log('flower_replace', {'seat': s, 'tile': tid});
          if (tid[0] == 'X') {
            p.flowers.add(int.parse(tid.substring(1)));
          } else {
            p.add(tid);
          }
          changed = true;
        }
      }
    }
    for (var s = 0; s < 4; s++) {
      if (_flowerEvents(s)) return;
    }
  }

  Map<String, dynamic> _view(int seat) {
    final p = players[seat];
    return {
      'seat': seat,
      'counts': [...p.counts],
      'jokers': p.jokers,
      'melds': [...p.melds],
      'flowers': [...p.flowers],
      'ting': p.ting,
      'discards': [for (final q in players) [...q.discards]],
      'wall_remaining': wall.remaining,
      'dealer': dealer,
    };
  }

  // ── win helpers ─────────────────────────────────────────────────────
  Ctx _ctx(int seat, int winKind, String method, WinFlags f) {
    final p = players[seat];
    return Ctx(
      counts: [...p.counts],
      jokers: p.jokers,
      exposed: [...p.melds],
      winKind: winKind,
      winMethod: method,
      flowers: [...p.flowers],
      seat: seat,
      ting: p.ting,
      tingClass: p.tingClass,
      jokerInEye: opts.jokerInEye,
      lastTile: f.lastTile,
      flowerDraw: f.flowerDraw,
      kongDraw: f.kongDraw,
      instantEat: f.instantEat,
      tailChainN: f.tailChainN,
      multiWin: f.multiWin,
      winClass: f.winClass,
    );
  }

  bool _canWin(int seat, {int? extraKind}) {
    final p = players[seat];
    final c = [...p.counts];
    if (extraKind != null) c[extraKind] += 1;
    return winForms(c, p.jokers, p.melds.length,
            jokerInEye: opts.jokerInEye)
        .isNotEmpty;
  }

  bool _instantEat(int seat) {
    final p = players[seat];
    return p.ting &&
        p.tingTurn >= 0 &&
        !anyMeld &&
        turnCount - p.tingTurn <= 4;
  }

  void _finishWin(
      List<int> winners, int? discarder, Map<int, WinFlags> flagsBySeat) {
    final results = <(int, ScoreResult)>[];
    for (final w in winners) {
      final ctx =
          _ctx(w, _lastWinKind[w]!, _winMethod[w]!, flagsBySeat[w]!);
      final r = scoreWin(ctx, table);
      assert(!r.notAWin);
      results.add((w, r));
      log('win', {
        'seat': w,
        'total': r.total,
        'fans': [
          for (final (f, n, p) in r.fans) [f, n, p]
        ],
        'form': r.form,
      });
    }
    final order = [...winners];
    if (discarder != null) {
      order.sort((a, b) =>
          ((a - discarder - 1) % 4 + 4) % 4 - ((b - discarder - 1) % 4 + 4) % 4);
    }
    final byW = {for (final (w, r) in results) w: r};
    for (final w in order) {
      deltas.addAll(
          settleWin(byW[w]!.total, w, discarder, dealer, repeatN, ledger, _cfg));
    }
    result = GameResult('win',
        winners: results,
        discarder: discarder,
        deltas: deltas,
        dealerRepeats: winners.contains(dealer));
  }

  // ── main loop ───────────────────────────────────────────────────────
  Future<GameResult> play(List<GamePolicy> policies) async {
    await _deal(policies);
    if (result != null) return result!; // flower_hu straight off the deal
    var cur = dealer;

    while (result == null) {
      final p = players[cur];

      // ---- draw phase ----
      var fromTail = false;
      String tid;
      while (true) {
        if (wall.remaining == 0) {
          _exhaust();
          return result!;
        }
        tid = fromTail ? wall.drawTail().id : wall.draw().id;
        if (!fromTail) turnCount += 1;
        if (tid[0] == 'X') {
          p.flowers.add(int.parse(tid.substring(1)));
          log('flower', {'seat': cur, 'tile': tid});
          if (_flowerEvents(cur)) return result!;
          fromTail = true;
          continue;
        }
        break;
      }
      p.add(tid);
      final drawKind = tid == 'J0' ? kJoker : idToKind(tid);
      log('draw', {'seat': cur, 'tail': fromTail});
      if (fromTail) {
        tailChain += 1;
      } else {
        tailChain = 0;
      }
      p.blockedTurn = false; // 過水 clears on own draw

      // ---- self-draw win? ----
      // in the main draw phase a tail draw only ever follows a flower,
      // so fromTail ⇒ 花摸 (kong replacements go through
      // _replacementDraw, which flags 槓摸 itself)
      if (_canWin(cur) && !p.blockedHand) {
        final flags = WinFlags(
          lastTile: wall.remaining == 0,
          flowerDraw: fromTail,
          kongDraw: false,
          instantEat: _instantEat(cur),
          tailChainN: tailChain >= 2 ? tailChain : 0,
          winClass: _winClass(cur, null),
        );
        if (p.ting || await policies[cur].wantWin(_view(cur))) {
          _lastWinKind[cur] = drawKind;
          _winMethod[cur] = 'self_draw';
          _finishWin([cur], null, {cur: flags});
          return result!;
        }
        // declining 自摸 is allowed without 過水 (VERIFY)
      }

      // ---- ting player: locked, rotate the drawn tile out ----
      if (p.ting) {
        if (drawKind == kJoker) {
          // drew a joker while ting and (somehow) didn't win: rotate it
          // out, unclaimable — VERIFY (near-unreachable, since a wild
          // tile completes any wait)
          p.jokers -= 1;
          log('discard', {'seat': cur, 'kind': kJoker, 'rotated': true});
          cur = (cur + 1) % 4;
          continue;
        }
        p.removeKind(drawKind);
        p.discards.add(drawKind);
        log('discard', {'seat': cur, 'kind': drawKind, 'rotated': true});
        final nxt = await _claims(cur, drawKind, policies);
        if (result != null) return result!;
        cur = nxt;
        continue;
      }

      // ---- kongs on own turn ----
      while (true) {
        final kg = _kongOptions(cur);
        if (kg.isEmpty) break;
        final choice = await policies[cur].wantKong(_view(cur), kg);
        if (choice == null) break;
        final (kind, ktype) = choice;
        if (ktype == 'concealed') {
          p.removeKind(kind, 4);
          p.melds.add((kind, 'kong_concealed'));
          _applyDeltas(midwayDeltas('concealed_kong', cur, _cfg));
          anyMeld = true;
          log('kong', {'seat': cur, 'kind': kind, 'ktype': ktype});
        } else {
          // added: rob window (搶槓)
          log('kong_add_attempt', {'seat': cur, 'kind': kind});
          final robbers = await _robKong(cur, kind, policies);
          if (robbers.isNotEmpty) return result!;
          p.removeKind(kind);
          for (var i = 0; i < p.melds.length; i++) {
            if (p.melds[i].$1 == kind && p.melds[i].$2 == 'pung') {
              p.melds[i] = (kind, 'kong_added');
            }
          }
          anyMeld = true;
          log('kong', {'seat': cur, 'kind': kind, 'ktype': ktype});
        }
        // replacement draw from tail
        final ok = await _replacementDraw(cur, policies, kong: true);
        if (result != null) return result!;
        if (!ok) return result!;
      }

      // ---- ting declaration ----
      if (!p.ting) {
        final d = await policies[cur].wantTing(_view(cur));
        if (d != null) {
          final kDiscard = d;
          p.removeKind(kDiscard);
          if (winningKinds(p.counts, p.jokers, p.melds.length,
                  jokerInEye: opts.jokerInEye)
              .isNotEmpty) {
            p.ting = true;
            p.tingTurn = turnCount;
            // 天叮: 莊 on very first turn; 地叮: 閒 on own first
            // discard, uncalled round — VERIFY
            if (cur == dealer && turnCount == 1 && !anyMeld) {
              p.tingClass = 'heaven';
            } else if (cur != dealer &&
                p.discards.isEmpty &&
                turnCount <= 4 &&
                !anyMeld) {
              p.tingClass = 'earth';
            }
            log('ting', {'seat': cur, 'cls': p.tingClass});
            p.discards.add(kDiscard);
            log('discard',
                {'seat': cur, 'kind': kDiscard, 'rotated': false});
            final nxt = await _claims(cur, kDiscard, policies);
            if (result != null) return result!;
            cur = nxt;
            continue;
          }
          p.counts[kDiscard] += 1; // invalid ting: ignore
        }
      }

      // ---- normal discard ----
      final k = await policies[cur].chooseDiscard(_view(cur));
      assert(k != kJoker, '百搭 may not be discarded (VERIFY)');
      p.removeKind(k);
      p.discards.add(k);
      log('discard', {'seat': cur, 'kind': k, 'rotated': false});
      final nxt = await _claims(cur, k, policies);
      if (result != null) return result!;
      cur = nxt;
    }
    return result!;
  }

  Future<bool> _replacementDraw(int seat, List<GamePolicy> policies,
      {required bool kong}) async {
    final p = players[seat];
    while (true) {
      if (wall.remaining == 0) {
        _exhaust();
        return false;
      }
      final tid = wall.drawTail().id;
      if (tid[0] == 'X') {
        p.flowers.add(int.parse(tid.substring(1)));
        log('flower', {'seat': seat, 'tile': tid});
        if (_flowerEvents(seat)) return false;
        continue;
      }
      p.add(tid);
      tailChain += 1;
      log('draw', {'seat': seat, 'tail': true});
      final k = tid == 'J0' ? kJoker : idToKind(tid);
      if (_canWin(seat) && !p.blockedHand) {
        final flags = WinFlags(
          kongDraw: kong,
          flowerDraw: !kong,
          lastTile: wall.remaining == 0,
          instantEat: _instantEat(seat),
          tailChainN: tailChain >= 2 ? tailChain : 0,
          winClass: '',
        );
        if (p.ting || await policies[seat].wantWin(_view(seat))) {
          _lastWinKind[seat] = k;
          _winMethod[seat] = 'self_draw';
          _finishWin([seat], null, {seat: flags});
          return false;
        }
      }
      return true;
    }
  }

  String _winClass(int seat, int? discarder) {
    // 天/地/人糊 — VERIFY-8 definitions
    if (seat == dealer && turnCount <= 1 && !anyMeld && discarder == null) {
      return 'heaven_earth';
    }
    if (discarder == dealer && turnCount <= 1 && !anyMeld) {
      return 'heaven_earth';
    }
    if (seat != dealer &&
        discarder == null &&
        turnCount <= 4 &&
        !anyMeld) {
      return 'man';
    }
    return '';
  }

  List<(int, String)> _kongOptions(int seat) {
    final p = players[seat];
    final opts = <(int, String)>[];
    if (p.ting) return opts; // no kongs after 叮 (VERIFY)
    for (var k = 0; k < numKinds; k++) {
      if (p.counts[k] == 4) opts.add((k, 'concealed'));
    }
    for (final (k, t) in p.melds) {
      if (t == 'pung' && p.counts[k] >= 1) opts.add((k, 'added'));
    }
    return opts;
  }

  Future<List<int>> _robKong(
      int konger, int kind, List<GamePolicy> policies) async {
    final winners = <int>[];
    for (var off = 1; off < 4; off++) {
      final s = (konger + off) % 4;
      final q = players[s];
      if (q.blockedHand || q.blockedTurn) continue;
      if (_canWin(s, extraKind: kind)) {
        if (q.ting || await policies[s].wantWin(_view(s))) {
          winners.add(s);
        } else {
          q.blockedHand = true; // declined 搶槓 ⇒ 過水成局
          log('pass_rob', {'seat': s});
        }
      }
    }
    if (winners.isNotEmpty) {
      final flags = <int, WinFlags>{};
      for (final w in winners) {
        players[w].counts[kind] += 1;
        _lastWinKind[w] = kind;
        _winMethod[w] = 'rob_kong';
        flags[w] = WinFlags(
            instantEat: _instantEat(w),
            multiWin: winners.length,
            winClass: '');
      }
      _finishWin(winners, konger, flags);
    }
    return winners;
  }

  /// Resolve claims; returns next seat. Sets [result] on win.
  Future<int> _claims(
      int discarder, int kind, List<GamePolicy> policies) async {
    // 1. wins (all simultaneous winners valid)
    final winners = <int>[];
    for (var off = 1; off < 4; off++) {
      final s = (discarder + off) % 4;
      final q = players[s];
      if (q.blockedHand || q.blockedTurn) continue;
      if (_canWin(s, extraKind: kind)) {
        if (q.ting || await policies[s].wantWin(_view(s))) {
          winners.add(s);
        } else {
          if (q.ting) {
            q.blockedHand = true;
          } else {
            q.blockedTurn = true; // 過水: until own next draw
          }
          log('pass_win', {'seat': s});
        }
      }
    }
    if (winners.isNotEmpty) {
      final flags = <int, WinFlags>{};
      for (final w in winners) {
        players[w].counts[kind] += 1;
        _lastWinKind[w] = kind;
        _winMethod[w] = 'discard';
        flags[w] = WinFlags(
          lastTile: wall.remaining == 0,
          instantEat: _instantEat(w),
          multiWin: winners.length,
          winClass: _winClass(w, discarder),
        );
      }
      _finishWin(winners, discarder, flags);
      return -1;
    }
    // 2. pung / exposed kong
    for (var off = 1; off < 4; off++) {
      final s = (discarder + off) % 4;
      final q = players[s];
      if (q.ting) continue;
      final options = <String>[];
      if (q.counts[kind] >= 3) options.add('kong');
      if (q.counts[kind] >= 2) options.add('pung');
      if (options.isEmpty) continue;
      final c = await policies[s].wantClaim(_view(s), kind, options);
      if (c != null && options.contains(c)) {
        players[discarder].discards.removeLast();
        anyMeld = true;
        if (c == 'kong') {
          q.removeKind(kind, 3);
          q.melds.add((kind, 'kong_exposed'));
          log('claim', {'seat': s, 'kind': kind, 'what': 'kong'});
          await _replacementDraw(s, policies, kong: true);
          if (result != null) return -1;
        } else {
          q.removeKind(kind, 2);
          q.melds.add((kind, 'pung'));
          log('claim', {'seat': s, 'kind': kind, 'what': 'pung'});
        }
        final nxt = await _postClaimDiscard(s, policies);
        if (result != null) return -1;
        return nxt;
      }
    }
    // 3. chow (next player only)
    final s = (discarder + 1) % 4;
    final q = players[s];
    if (!q.ting && kind < 27) {
      final lows = [kind - 2, kind - 1, kind];
      final opts = <int>[];
      for (final lo in lows) {
        if (lo < 0 || lo ~/ 9 != kind ~/ 9 || (lo + 2) ~/ 9 != kind ~/ 9) {
          continue;
        }
        final need = [
          for (final x in [lo, lo + 1, lo + 2])
            if (x != kind) x
        ];
        if (need.every((x) => q.counts[x] >= 1)) opts.add(lo);
      }
      if (opts.isNotEmpty) {
        final lo = await policies[s].wantChow(_view(s), kind, opts);
        if (lo != null && opts.contains(lo)) {
          players[discarder].discards.removeLast();
          for (final x in [lo, lo + 1, lo + 2]) {
            if (x != kind) q.removeKind(x);
          }
          q.melds.add((lo, 'chow'));
          anyMeld = true;
          log('claim', {'seat': s, 'kind': lo, 'what': 'chow'});
          final nxt = await _postClaimDiscard(s, policies);
          if (result != null) return -1;
          return nxt;
        }
      }
    }
    return (discarder + 1) % 4;
  }

  /// After a claim the claimer discards; that discard may itself be
  /// claimed (chains recurse). Returns the seat whose turn is next.
  Future<int> _postClaimDiscard(int seat, List<GamePolicy> policies) async {
    final p = players[seat];
    final k = await policies[seat].chooseDiscard(_view(seat));
    assert(k != kJoker);
    p.removeKind(k);
    p.discards.add(k);
    log('discard', {'seat': seat, 'kind': k, 'rotated': false});
    return _claims(seat, k, policies);
  }

  /// 七搶一 / 八仙過海 midway checks. Returns true if 局 ended.
  bool _flowerEvents(int seat) {
    final p = players[seat];
    if (p.flowers.length == 8) {
      _applyDeltas(midwayDeltas('two_tai_flower', seat, _cfg));
      log('flower_hu', {'seat': seat, 'kind': 'eight'});
      result = GameResult('flower_hu',
          seat: seat, deltas: deltas, dealerRepeats: true);
      return true;
    }
    if (p.flowers.length == 7) {
      for (var off = 1; off < 4; off++) {
        final v = (seat + off) % 4;
        if (players[v].flowers.length == 1) {
          _applyDeltas(
              midwayDeltas('seven_rob_one', seat, _cfg, source: v));
          p.flowers.addAll(players[v].flowers);
          players[v].flowers.clear();
          log('flower_hu', {'seat': seat, 'kind': 'seven_rob', 'victim': v});
          result = GameResult('flower_hu',
              seat: seat, deltas: deltas, dealerRepeats: true);
          return true;
        }
      }
    }
    return false;
  }

  void _exhaust() {
    log('exhaust', {});
    result = GameResult('exhaust', deltas: deltas, dealerRepeats: true);
  }
}
