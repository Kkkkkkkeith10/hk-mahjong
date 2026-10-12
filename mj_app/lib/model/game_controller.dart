/// GameClient (view-model layer) for LOCAL sessions — 08-INTEGRATION §1.
///
/// Runs mj_core's Engine with seat 0 = human (HumanPolicy: prompts resolved
/// by UI taps via Completers) and seats 1-3 = L1Policy bots (paced with a
/// short delay so play is watchable). Owns the match loop: dealer rotation,
/// 連莊/拉N, the persistent 拉 ledger between 局, cumulative scores, and the
/// match-end ledger wipe (Keith's ruling 2026-07-07).
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:mj_core/mj_core.dart';

/// Room options chosen in the setup wizard.
class MatchConfig {
  final int jokers; // 0 | 4 | 8
  final String swap; // off | fixed3 | dice
  final bool laOn;
  final int totalHands; // 局數
  final int? seed; // null = random
  final int botDelayMs; // bot pacing (settings: 快300/中550/慢900)
  const MatchConfig(
      {this.jokers = 0,
      this.swap = 'off',
      this.laOn = true,
      this.totalHands = 8,
      this.seed,
      this.botDelayMs = 550});
}

enum PromptType { none, swap, discard, win, kong, claim, chow }

/// What the UI must ask the human right now.
class Prompt {
  final PromptType type;
  final int n; // swap: tiles to give
  final bool canTing; // discard: 叮 available (main-turn discard)
  final List<(int, String)> kongOptions;
  final int claimKind; // claim/chow: the discarded kind
  final List<String> claimOptions;
  final List<int> chowLows;
  const Prompt(this.type,
      {this.n = 0,
      this.canTing = false,
      this.kongOptions = const [],
      this.claimKind = -1,
      this.claimOptions = const [],
      this.chowLows = const []});
  static const none = Prompt(PromptType.none);
}

const aiNames = ['你', '奶茶三少', '蛋撻哥', '菠蘿包仔'];
const windNames = ['東', '南', '西', '北'];

/// Seat → avatar asset (茶餐廳 mascots; seat 0 = 燒賣仔 = the player).
const avatarAssets = [
  'assets/avatars/siumai_jai.png',
  'assets/avatars/milk_tea_sam_si.png',
  'assets/avatars/egg_tart_go.png',
  'assets/avatars/pineapple_bun_jai.png',
];

/// A callout bubble to show at a seat (「碰！」「叮！」…). [id] increments so
/// the UI can animate every new bubble even if the text repeats.
typedef Callout = ({int seat, String text, int id});

/// Slows a bot down so its moves are visible. [delay] is a callback so the
/// controller can stretch the beat right after a claim/kong/ting callout,
/// giving the player time to read the bubble.
class PacedPolicy extends GamePolicy {
  final GamePolicy inner;
  final Duration Function() delay;
  PacedPolicy(this.inner, this.delay);

  Future<T> _p<T>(FutureOr<T> Function() f) async {
    await Future<void>.delayed(delay());
    return f();
  }

  @override
  FutureOr<List<int>> chooseSwap(Map<String, dynamic> v, int n) =>
      _p(() => inner.chooseSwap(v, n));
  @override
  FutureOr<int> chooseDiscard(Map<String, dynamic> v) =>
      _p(() => inner.chooseDiscard(v));
  @override
  FutureOr<bool> wantWin(Map<String, dynamic> v) => _p(() => inner.wantWin(v));
  @override
  FutureOr<int?> wantTing(Map<String, dynamic> v) => _p(() => inner.wantTing(v));
  @override
  FutureOr<(int, String)?> wantKong(
          Map<String, dynamic> v, List<(int, String)> o) =>
      _p(() => inner.wantKong(v, o));
  @override
  FutureOr<String?> wantClaim(
          Map<String, dynamic> v, int kind, List<String> o) =>
      _p(() => inner.wantClaim(v, kind, o));
  @override
  FutureOr<int?> wantChow(Map<String, dynamic> v, int kind, List<int> lows) =>
      _p(() => inner.wantChow(v, kind, lows));
}

/// Seat 0. Every decision surfaces as a [Prompt] on the controller and
/// blocks the engine until the UI answers.
class HumanPolicy extends GamePolicy {
  final GameController c;
  HumanPolicy(this.c);

  int? _stashedDiscard; // chosen while answering wantTing with 叮 off

  Completer<List<int>>? swapC;
  Completer<int?>? tingC;
  Completer<int>? discardC;
  Completer<bool>? winC;
  Completer<(int, String)?>? kongC;
  Completer<String?>? claimC;
  Completer<int?>? chowC;

  @override
  Future<List<int>> chooseSwap(Map<String, dynamic> v, int n) {
    swapC = Completer();
    c._show(Prompt(PromptType.swap, n: n));
    return swapC!.future;
  }

  @override
  Future<int?> wantTing(Map<String, dynamic> v) {
    // The engine asks this on EVERY main turn; only offer the 叮 button
    // when some discard actually leaves the hand ready (mirrors AiPolicy).
    if (!_canDeclareTing(v)) return Future.value(null);
    tingC = Completer();
    c._show(const Prompt(PromptType.discard, canTing: true));
    return tingC!.future;
  }

  static bool _canDeclareTing(Map<String, dynamic> v) {
    final counts = v['counts'] as List<int>;
    final jk = v['jokers'] as int;
    final nm = (v['melds'] as List).length;
    for (var k = 0; k < numKinds; k++) {
      if (counts[k] == 0) continue;
      counts[k] -= 1;
      final ok = winningKinds(counts, jk, nm).isNotEmpty;
      counts[k] += 1;
      if (ok) return true;
    }
    return false;
  }

  @override
  FutureOr<int> chooseDiscard(Map<String, dynamic> v) {
    final s = _stashedDiscard;
    if (s != null) {
      _stashedDiscard = null;
      return s; // already picked during the wantTing prompt
    }
    discardC = Completer();
    c._show(const Prompt(PromptType.discard));
    return discardC!.future;
  }

  @override
  Future<bool> wantWin(Map<String, dynamic> v) {
    winC = Completer();
    c._show(const Prompt(PromptType.win));
    return winC!.future;
  }

  @override
  Future<(int, String)?> wantKong(
      Map<String, dynamic> v, List<(int, String)> options) {
    kongC = Completer();
    c._show(Prompt(PromptType.kong, kongOptions: options));
    return kongC!.future;
  }

  @override
  Future<String?> wantClaim(
      Map<String, dynamic> v, int kind, List<String> options) {
    claimC = Completer();
    c._show(Prompt(PromptType.claim, claimKind: kind, claimOptions: options));
    return claimC!.future;
  }

  @override
  Future<int?> wantChow(Map<String, dynamic> v, int kind, List<int> lows) {
    chowC = Completer();
    c._show(Prompt(PromptType.chow, claimKind: kind, chowLows: lows));
    return chowC!.future;
  }
}

class GameController extends ChangeNotifier {
  final FanTable table;
  final MatchConfig config;
  final math.Random _rand;

  late LaLedger ledger;
  Engine? engine;
  HumanPolicy? human;

  int dealer = 0;
  int repeatN = 0;
  int handNo = 0; // 1-based once playing
  final List<int> scores = [0, 0, 0, 0]; // cumulative 分
  Prompt prompt = Prompt.none;
  int turnSeat = -1; // seat that last drew/discarded (table highlight)
  Map<String, dynamic>? lastEvent;
  Callout? callout; // latest action bubble (any seat)
  int _calloutSeq = 0;
  DateTime _calloutAt = DateTime.fromMillisecondsSinceEpoch(0);
  (int, int)? lastDiscard; // (seat, riverIndex) of the newest discard
  List<String> _handSnap = const []; // human hand before the latest draw
  int? newTileIdx; // index (in sorted humanHand) of the freshly drawn tile
  GameResult? handResult; // set while the win overlay is up
  List<Delta> handDeltas = const []; // this 局's paid lines
  List<(int, int, int, int)>? wipedLedger; // match end panel
  bool matchOver = false;
  bool _disposed = false;

  GameController(this.table, this.config)
      : _rand = math.Random(config.seed) {
    ledger = LaLedger(table.settlement.laLedger);
  }

  // ── engine → UI ──────────────────────────────────────────────────────
  void _show(Prompt p) {
    prompt = p;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _onEvent(Map<String, dynamic> e) {
    lastEvent = e;
    final s = e['seat'];
    final type = e['type'];
    if (s is int &&
        const {'draw', 'discard', 'claim', 'kong', 'ting'}
            .contains(type)) {
      turnSeat = s;
    }
    // action callouts (「碰！」 bubble at the acting seat)
    if (s is int) {
      final text = switch (type) {
        'claim' => switch (e['what']) {
            'pung' => '碰！',
            'kong' => '槓！',
            'chow' => '上！',
            _ => null,
          },
        'kong' => e['ktype'] == 'concealed' ? '暗槓！' : '槓！',
        'ting' => '叮！',
        'flower_hu' => '花糊！',
        _ => null,
      };
      if (text != null) {
        callout = (seat: s, text: text, id: ++_calloutSeq);
        _calloutAt = DateTime.now();
      }
    }
    if (type == 'discard' && s is int) {
      final n = engine?.players[s].discards.length ?? 0;
      lastDiscard = (s, n - 1);
    } else if (const {'claim', 'win'}.contains(type)) {
      lastDiscard = null; // tile taken / hand over
    }
    // freshly drawn tile: the engine adds the tile BEFORE logging 'draw',
    // so diffing the snapshot taken at the previous event finds it.
    if (engine != null) {
      if (type == 'draw' && s == 0) {
        newTileIdx = _diffNewTile(_handSnap, humanHand());
      } else {
        _handSnap = humanHand();
        if ((type == 'discard' && s == 0) || type == 'claim') {
          newTileIdx = null;
        }
      }
    }
    _notify();
  }

  /// Multiset diff of the sorted hand: exactly one added tile → its index.
  static int? _diffNewTile(List<String> before, List<String> now) {
    if (now.length != before.length + 1) return null;
    final counts = <String, int>{};
    for (final id in before) {
      counts[id] = (counts[id] ?? 0) + 1;
    }
    String? added;
    for (final id in now) {
      final left = counts[id] ?? 0;
      if (left == 0) {
        if (added != null) return null;
        added = id;
      } else {
        counts[id] = left - 1;
      }
    }
    return added == null ? null : now.indexOf(added);
  }

  /// Bot pacing: base delay, stretched while a fresh callout is on screen so
  /// the player can read 「碰！」/「叮！」 before play rushes on.
  Duration _pace() {
    final base = config.botDelayMs;
    final sinceCallout =
        DateTime.now().difference(_calloutAt).inMilliseconds;
    return Duration(milliseconds: sinceCallout < 1800 ? base + 800 : base);
  }

  // ── UI → engine (prompt answers) ─────────────────────────────────────
  void answerSwap(List<int> kinds) {
    prompt = Prompt.none;
    human?.swapC?.complete(kinds);
    _notify();
  }

  /// Tile tapped during the discard prompt. [ting] = 叮 toggle state.
  void answerDiscard(int kind, {bool ting = false}) {
    final h = human!;
    prompt = Prompt.none;
    if (h.tingC != null && !h.tingC!.isCompleted) {
      if (ting) {
        h.tingC!.complete(kind);
      } else {
        h._stashedDiscard = kind;
        h.tingC!.complete(null);
      }
    } else {
      h.discardC?.complete(kind);
    }
    _notify();
  }

  void answerWin(bool yes) {
    prompt = Prompt.none;
    human?.winC?.complete(yes);
    _notify();
  }

  void answerKong((int, String)? choice) {
    prompt = Prompt.none;
    human?.kongC?.complete(choice);
    _notify();
  }

  void answerClaim(String? what) {
    prompt = Prompt.none;
    human?.claimC?.complete(what);
    _notify();
  }

  void answerChow(int? lo) {
    prompt = Prompt.none;
    human?.chowC?.complete(lo);
    _notify();
  }

  // ── match loop ───────────────────────────────────────────────────────
  Future<void> startMatch() async {
    while (handNo < config.totalHands && !_disposed) {
      handNo += 1;
      await _playHand();
      if (_disposed) return;
      // wait for the overlay's 繼續 tap
      await _continueRequested.future;
      _continueRequested = Completer();
      handResult = null;
      _notify();
    }
    if (_disposed) return;
    // match end: unresolved 拉 ledgers are wiped (ruling 2026-07-07)
    wipedLedger = ledger.matchEnd();
    matchOver = true;
    _notify();
  }

  Completer<void> _continueRequested = Completer();

  /// Win-overlay 繼續 button.
  void continueMatch() {
    if (!_continueRequested.isCompleted) _continueRequested.complete();
  }

  Future<void> _playHand() async {
    final seed = _rand.nextInt(1 << 30);
    final eng = Engine(seed, table,
        opts: EngineOptions(
            jokers: config.jokers, swap: config.swap, laOn: config.laOn),
        dealer: dealer,
        repeatN: repeatN,
        ledger: config.laOn ? ledger : null);
    final h = HumanPolicy(this);
    engine = eng;
    human = h;
    turnSeat = dealer;
    callout = null;
    lastDiscard = null;
    _handSnap = const [];
    newTileIdx = null;
    eng.onEvent = _onEvent;
    _notify();

    final res = await eng.play([
      h,
      PacedPolicy(L1Policy(), _pace),
      PacedPolicy(L1Policy(), _pace),
      PacedPolicy(L1Policy(), _pace),
    ]);
    if (_disposed) return;

    for (final d in eng.deltas) {
      scores[d.frm] -= d.amount;
      scores[d.to] += d.amount;
    }
    handDeltas = [...eng.deltas];
    handResult = res;
    prompt = Prompt.none;
    if (res.dealerRepeats) {
      repeatN += 1; // 連莊拉一
    } else {
      dealer = (dealer + 1) % 4;
      repeatN = 0;
    }
    _notify();
  }

  // ── view helpers for widgets ─────────────────────────────────────────
  /// Human hand as sorted tile ids (jokers last).
  List<String> humanHand() {
    final p = engine?.players[0];
    if (p == null) return const [];
    final out = <String>[];
    for (var k = 0; k < numKinds; k++) {
      for (var i = 0; i < p.counts[k]; i++) {
        out.add(kindToId(k));
      }
    }
    for (var i = 0; i < p.jokers; i++) {
      out.add('J0');
    }
    return out;
  }

  /// Ledger rows for the strip/panels: (creditor, debtor, amount, kou).
  List<(int, int, int, int)> ledgerRows() => [
        for (final e in ledger.led.entries)
          (e.key.$1, e.key.$2, e.value.amount, e.value.kou)
      ];

  @override
  void dispose() {
    _disposed = true;
    // release a blocked engine future so nothing leaks
    continueMatch();
    super.dispose();
  }
}
