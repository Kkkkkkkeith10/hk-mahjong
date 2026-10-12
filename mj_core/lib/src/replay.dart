/// Deterministic-replay driver — the multiplayer "step engine".
///
/// The Engine in engine.dart is a seeded async loop that only blocks at
/// GamePolicy decision points, and the bots (L1Policy) are RNG-free. So a
/// whole match is a pure function of (rules, ordered human answers): to
/// advance a server-side game we never persist engine internals — we store
/// the [MatchRules] plus the append-only [SeatAction] log, rebuild the
/// engine from seed, replay every recorded answer through [_ScriptedSeat]
/// policies, and run until the match either finishes or parks at the next
/// unanswered prompt (a never-completing Future freezes the loop mid-await).
/// A full 局 replays in well under a millisecond, and the engine's rule
/// code is executed byte-identically — zero risk of multiplayer rules
/// drifting from the golden-fixture-tested single-player rules.
///
/// DETERMINISM SCOPE: replays are bit-stable within one runtime. rng.dart
/// documents VM/AOT-only 64-bit semantics, so a hosted game must always be
/// replayed by the same runtime that started it (the server). Clients never
/// replay — they render redacted views the server sends.
///
/// Wire shapes (all JSON-safe):
///   prompt/answer type . answer value
///   'swap'    . List<int> kinds to pass (length n)
///   'discard' . int kind
///   'win'     . bool
///   'ting'    . int? kind rotated out while declaring 叮 (null = decline)
///   'kong'    . [kind, ktype]? from the offered options (null = decline)
///   'claim'   . 'pung' | 'kong' | null
///   'chow'    . int? low kind of the run (null = decline)
///
/// 叮 gating: the engine asks wantTing on EVERY main turn; like the app's
/// HumanPolicy, [_ScriptedSeat] only surfaces the prompt when some discard
/// leaves the hand ready ([canDeclareTing]) and auto-answers null
/// otherwise, so ineligible turns cost no network round trip. The gate is
/// deterministic, so the action log stays replay-stable.
library;

import 'dart:async';

import 'ai.dart';
import 'decompose.dart';
import 'engine.dart';
import 'fan_table.dart';
import 'kinds.dart';
import 'rng.dart';
import 'settle.dart';

/// Invalid, out-of-order, or malformed action. The server maps this to a
/// clean rejection; engine state is never corrupted because replays are
/// rebuilt from scratch per action.
class ReplayException implements Exception {
  final String message;
  ReplayException(this.message);
  @override
  String toString() => 'ReplayException: $message';
}

/// One recorded human answer (see wire shapes in the library doc).
class SeatAction {
  final int seat;
  final String type;
  final Object? value;
  const SeatAction(this.seat, this.type, this.value);

  Map<String, dynamic> toJson() => {'seat': seat, 'type': type, 'value': value};

  factory SeatAction.fromJson(Map<String, dynamic> j) =>
      SeatAction(j['seat'] as int, j['type'] as String, j['value']);

  @override
  String toString() => 'SeatAction($seat, $type, $value)';
}

/// The decision the match is waiting on (exactly one at any moment — the
/// engine asks seats strictly sequentially).
class PendingPrompt {
  final int seat;
  final String type;

  /// Prompt-specific context: swap {'n'}, kong {'options': [[kind,ktype]..]},
  /// claim {'kind', 'options'}, chow {'kind', 'lows'}, ting/discard/win {}.
  final Map<String, dynamic> args;
  const PendingPrompt(this.seat, this.type, this.args);

  Map<String, dynamic> toJson() => {'seat': seat, 'type': type, 'args': args};

  factory PendingPrompt.fromJson(Map<String, dynamic> j) => PendingPrompt(
      j['seat'] as int,
      j['type'] as String,
      Map<String, dynamic>.from(j['args'] as Map));

  @override
  String toString() => 'PendingPrompt($seat, $type, $args)';
}

/// Room-level game settings — everything needed to reproduce the match.
/// Mirrors the app's MatchConfig but lives in mj_core so server code can
/// share it. Hand seeds derive from [seed] via SplitMix64 (not math.Random,
/// whose sequence is not part of any contract we control).
class MatchRules {
  final int seed;
  final int totalHands;
  final int jokers; // 0 | 4 | 8
  final String swap; // off | fixed3 | dice
  final bool laOn;
  const MatchRules(
      {required this.seed,
      this.totalHands = 8,
      this.jokers = 0,
      this.swap = 'off',
      this.laOn = true});

  Map<String, dynamic> toJson() => {
        'seed': seed,
        'total_hands': totalHands,
        'jokers': jokers,
        'swap': swap,
        'la_on': laOn,
      };

  factory MatchRules.fromJson(Map<String, dynamic> j) => MatchRules(
        seed: j['seed'] as int,
        totalHands: j['total_hands'] as int? ?? 8,
        jokers: j['jokers'] as int? ?? 0,
        swap: j['swap'] as String? ?? 'off',
        laOn: j['la_on'] as bool? ?? true,
      );
}

/// True when some discard leaves the hand ready to declare 叮. Shared gate
/// for scripted seats, the app's HumanPolicy, and timeout auto-answers.
bool canDeclareTing(Map<String, dynamic> view) =>
    _firstTingDiscard(view) != null;

/// The lowest kind whose discard leaves the hand ready, or null. This is
/// exactly L1Policy.wantTing's choice — reused for AI-takeover timeouts.
int? _firstTingDiscard(Map<String, dynamic> view) {
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

/// Where a replay stopped.
class MatchSnapshot {
  /// 1-based; the hand the match is in (or the last played hand if over).
  final int handNo;
  final int dealer;
  final int repeatN;
  final List<int> scores; // cumulative 分 after every settled hand
  final Engine engine; // current (suspended) or last finished hand
  final GameResult? handResult; // set when the current hand just finished
  final PendingPrompt? pending; // null ⇔ hand boundary or match over
  final bool matchOver;
  final List<(int, int, int, int)> ledgerRows; // (creditor,debtor,amt,kou)
  final List<(int, int, int, int)>? wipedLedger; // set at match end

  const MatchSnapshot({
    required this.handNo,
    required this.dealer,
    required this.repeatN,
    required this.scores,
    required this.engine,
    required this.handResult,
    required this.pending,
    required this.matchOver,
    required this.ledgerRows,
    required this.wipedLedger,
  });
}

/// FIFO of recorded answers, consumed in prompt order across the match.
class _Feed {
  final List<SeatAction> actions;
  int cursor = 0;
  _Feed(this.actions);

  bool get exhausted => cursor >= actions.length;

  SeatAction take(int seat, String type) {
    final a = actions[cursor];
    if (a.seat != seat || a.type != type) {
      throw ReplayException(
          'action #$cursor is $a but the engine is prompting $type@seat$seat');
    }
    cursor += 1;
    return a;
  }
}

/// Per-hand suspension bookkeeping shared by the four policies.
class _HandRun {
  final _Feed feed;
  final Completer<void> parked = Completer();
  PendingPrompt? pending;
  _HandRun(this.feed);

  /// Answer from the feed, or park the engine and surface [prompt].
  FutureOr<T> next<T>(PendingPrompt prompt, T Function(Object?) decode) {
    if (!feed.exhausted) {
      return decode(feed.take(prompt.seat, prompt.type).value);
    }
    pending = prompt;
    if (!parked.isCompleted) parked.complete();
    return Completer<T>().future; // never completes — engine freezes here
  }
}

int _asKind(Object? v, String what) {
  if (v is! int || v < 0 || v >= numKinds) {
    throw ReplayException('$what must be a kind int 0..${numKinds - 1}: $v');
  }
  return v;
}

/// A human seat driven by the action log. Validates every answer against
/// the live view so a malformed/hostile action raises [ReplayException]
/// instead of corrupting engine state (engine asserts vanish in release).
class _ScriptedSeat extends GamePolicy {
  final int seat;
  final _HandRun run;
  _ScriptedSeat(this.seat, this.run);

  @override
  FutureOr<List<int>> chooseSwap(Map<String, dynamic> view, int n) =>
      run.next(PendingPrompt(seat, 'swap', {'n': n}), (v) {
        if (v is! List || v.length != n) {
          throw ReplayException('swap answer must be a list of $n kinds: $v');
        }
        final counts = [...(view['counts'] as List<int>)];
        final kinds = <int>[];
        for (final e in v) {
          final k = _asKind(e, 'swap kind');
          if (counts[k] <= 0) {
            throw ReplayException('swap kind $k not in hand');
          }
          counts[k] -= 1;
          kinds.add(k);
        }
        return kinds;
      });

  @override
  FutureOr<int> chooseDiscard(Map<String, dynamic> view) =>
      run.next(PendingPrompt(seat, 'discard', const {}), (v) {
        final k = _asKind(v, 'discard');
        if ((view['counts'] as List<int>)[k] <= 0) {
          throw ReplayException('discard kind $k not in hand');
        }
        return k;
      });

  @override
  FutureOr<bool> wantWin(Map<String, dynamic> view) =>
      run.next(PendingPrompt(seat, 'win', const {}), (v) {
        if (v is! bool) throw ReplayException('win answer must be bool: $v');
        return v;
      });

  @override
  FutureOr<int?> wantTing(Map<String, dynamic> view) {
    if (!canDeclareTing(view)) return null; // gate: no prompt, no action
    return run.next(PendingPrompt(seat, 'ting', const {}), (v) {
      if (v == null) return null;
      final k = _asKind(v, 'ting discard');
      if ((view['counts'] as List<int>)[k] <= 0) {
        throw ReplayException('ting discard kind $k not in hand');
      }
      return k;
    });
  }

  @override
  FutureOr<(int, String)?> wantKong(
      Map<String, dynamic> view, List<(int, String)> options) {
    final opts = [
      for (final (k, t) in options) [k, t]
    ];
    return run.next(PendingPrompt(seat, 'kong', {'options': opts}), (v) {
      if (v == null) return null;
      if (v is! List || v.length != 2) {
        throw ReplayException('kong answer must be [kind, ktype]: $v');
      }
      final choice = (_asKind(v[0], 'kong kind'), v[1] as String);
      if (!options.contains(choice)) {
        throw ReplayException('kong $choice not among offered $options');
      }
      return choice;
    });
  }

  @override
  FutureOr<String?> wantClaim(
          Map<String, dynamic> view, int kind, List<String> options) =>
      run.next(
          PendingPrompt(seat, 'claim', {'kind': kind, 'options': options}),
          (v) {
        if (v == null) return null;
        if (v is! String || !options.contains(v)) {
          throw ReplayException('claim $v not among offered $options');
        }
        return v;
      });

  @override
  FutureOr<int?> wantChow(
          Map<String, dynamic> view, int kind, List<int> lowOptions) =>
      run.next(
          PendingPrompt(seat, 'chow', {'kind': kind, 'lows': lowOptions}),
          (v) {
        if (v == null) return null;
        final lo = _asKind(v, 'chow low');
        if (!lowOptions.contains(lo)) {
          throw ReplayException('chow low $lo not among offered $lowOptions');
        }
        return lo;
      });
}

/// Rebuild-and-replay a match. Stateless: call [run] with the full action
/// log each time; append the incoming action first to try it.
class MatchDriver {
  final FanTable table;
  final MatchRules rules;
  final Set<int> humanSeats;
  MatchDriver(this.table, this.rules, this.humanSeats) {
    if (humanSeats.any((s) => s < 0 || s > 3)) {
      throw ArgumentError('humanSeats must be within 0..3: $humanSeats');
    }
  }

  Future<MatchSnapshot> run(List<SeatAction> actions) async {
    for (final a in actions) {
      if (!humanSeats.contains(a.seat)) {
        throw ReplayException('seat ${a.seat} is a bot, cannot act: $a');
      }
    }
    final seeds = SplitMix64(rules.seed ^ 0x5EED);
    final ledger = LaLedger(table.settlement.laLedger);
    final scores = [0, 0, 0, 0];
    var dealer = 0;
    var repeatN = 0;
    final feed = _Feed(actions);

    Engine? lastEngine;
    GameResult? lastResult;
    var handNo = 0;
    while (handNo < rules.totalHands) {
      handNo += 1;
      final eng = Engine(seeds.nextBounded(1 << 30), table,
          opts: EngineOptions(
              jokers: rules.jokers, swap: rules.swap, laOn: rules.laOn),
          dealer: dealer,
          repeatN: repeatN,
          ledger: rules.laOn ? ledger : null);
      lastEngine = eng;
      final hand = _HandRun(feed);
      final policies = <GamePolicy>[
        for (var s = 0; s < 4; s++)
          humanSeats.contains(s) ? _ScriptedSeat(s, hand) : L1Policy()
      ];

      GameResult? res;
      Object? failure;
      // ignore: unawaited_futures
      eng.play(policies).then((r) {
        res = r;
        if (!hand.parked.isCompleted) hand.parked.complete();
      }, onError: (Object e) {
        failure = e;
        if (!hand.parked.isCompleted) hand.parked.complete();
      });
      await hand.parked.future;
      if (failure != null) throw failure!;

      if (res == null) {
        // Parked at an unanswered prompt: this is the resume point.
        return MatchSnapshot(
          handNo: handNo,
          dealer: dealer,
          repeatN: repeatN,
          scores: scores,
          engine: eng,
          handResult: null,
          pending: hand.pending,
          matchOver: false,
          ledgerRows: _rows(ledger),
          wipedLedger: null,
        );
      }
      lastResult = res;
      for (final d in eng.deltas) {
        scores[d.frm] -= d.amount;
        scores[d.to] += d.amount;
      }
      if (res!.dealerRepeats) {
        repeatN += 1; // 連莊拉一
      } else {
        dealer = (dealer + 1) % 4;
        repeatN = 0;
      }
    }
    if (!feed.exhausted) {
      throw ReplayException(
          'match is over but ${feed.actions.length - feed.cursor} '
          'action(s) were never prompted for');
    }
    final wiped = ledger.matchEnd(); // ruling 2026-07-07: wipe unresolved 拉
    return MatchSnapshot(
      handNo: handNo,
      dealer: dealer,
      repeatN: repeatN,
      scores: scores,
      engine: lastEngine!,
      handResult: lastResult,
      pending: null,
      matchOver: true,
      ledgerRows: _rows(ledger),
      wipedLedger: wiped,
    );
  }

  static List<(int, int, int, int)> _rows(LaLedger l) => [
        for (final e in l.led.entries)
          (e.key.$1, e.key.$2, e.value.amount, e.value.kou)
      ];
}

/// What one player is allowed to see, JSON-safe for the wire. Own hand in
/// full; other hands only as tile counts (never contents). The event log is
/// deliberately NOT included — engine events leak the deal.
Map<String, dynamic> clientView(MatchSnapshot snap, int seat) {
  final eng = snap.engine;
  final p = eng.players[seat];
  return {
    'seat': seat,
    'hand_no': snap.handNo,
    'dealer': snap.dealer,
    'repeat_n': snap.repeatN,
    'scores': snap.scores,
    'match_over': snap.matchOver,
    'wall_remaining': eng.wall.remaining,
    'counts': [...p.counts],
    'jokers': p.jokers,
    'players': [
      for (var s = 0; s < 4; s++)
        {
          'hand_size': eng.players[s].handSize,
          'melds': [
            for (final (k, t) in eng.players[s].melds) [k, t]
          ],
          'flowers': [...eng.players[s].flowers],
          'discards': [...eng.players[s].discards],
          'ting': eng.players[s].ting,
        }
    ],
    'ledger': [
      for (final (c, d, amt, kou) in snap.ledgerRows) [c, d, amt, kou]
    ],
    'prompt': snap.pending != null && snap.pending!.seat == seat
        ? snap.pending!.toJson()
        : null,
    'waiting_on': snap.pending?.seat,
  };
}

/// The answer L1Policy would give to [pending] — used for turn-timer
/// expiry and grace/AI takeover so a stalled seat plays on sensibly.
Object? botAnswerFor(MatchSnapshot snap, PendingPrompt pending) {
  final view = _viewFor(snap.engine, pending.seat);
  final bot = L1Policy();
  switch (pending.type) {
    case 'swap':
      return bot.chooseSwap(view, pending.args['n'] as int);
    case 'discard':
      return bot.chooseDiscard(view);
    case 'win':
      return true; // always take a valid win
    case 'ting':
      return _firstTingDiscard(view);
    case 'kong':
      return null; // timeout: decline optional kong
    case 'claim':
      return null; // timeout: pass
    case 'chow':
      return null; // timeout: pass
    default:
      throw ReplayException('unknown prompt type ${pending.type}');
  }
}

/// Engine._view is private; rebuild the same shape from public state.
Map<String, dynamic> _viewFor(Engine eng, int seat) {
  final p = eng.players[seat];
  return {
    'seat': seat,
    'counts': [...p.counts],
    'jokers': p.jokers,
    'melds': [...p.melds],
    'flowers': [...p.flowers],
    'ting': p.ting,
    'discards': [
      for (final q in eng.players) [...q.discards]
    ],
    'wall_remaining': eng.wall.remaining,
    'dealer': eng.dealer,
  };
}
