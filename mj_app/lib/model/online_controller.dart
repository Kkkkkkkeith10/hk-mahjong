/// View-model for ONLINE sessions — the remote twin of GameController.
///
/// The server (edge function `mj`) owns the match: it replays the action log
/// through the same mj_core engine and returns a redacted per-seat view.
/// This controller polls `state`, converts the wire prompt into the same
/// [Prompt] shape the local table uses, answers via `act`, and fires
/// `timeout` when a turn deadline lapses (grace / AI-takeover, ruling
/// 2026-06: any player may fire it; the server applies the L1 bot answer).
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:mj_core/mj_core.dart';

import 'game_controller.dart' show Prompt, PromptType;
import 'online_client.dart';

enum OnlinePhase { connecting, waiting, playing, finished, error }

class OnlinePlayer {
  final int seat;
  final String nickname;
  final bool isBot;
  final bool isAway;
  const OnlinePlayer(this.seat, this.nickname, this.isBot, this.isAway);
}

class OnlineGameController extends ChangeNotifier {
  final OnlineClient client;
  final String roomId;
  final int mySeat;

  OnlineGameController(
      {required this.roomId, required this.mySeat, OnlineClient? client})
      : client = client ?? OnlineClient.instance;

  OnlinePhase phase = OnlinePhase.connecting;
  String? errorText;

  Map<String, dynamic> room = const {};
  List<OnlinePlayer> roster = const [];
  Map<String, dynamic>? view; // clientView JSON (see mj_core replay.dart)

  Prompt prompt = Prompt.none;
  DateTime? deadline; // parsed room.turn_deadline
  int? waitingOn; // seat the match is parked on (null between polls)

  Timer? _poll;
  Timer? _tick; // countdown repaint + timeout firing
  bool _acting = false; // one in-flight act at a time
  int _timeoutFiredVersion = -1;
  int? _stashedDiscard; // chosen while answering a 叮 prompt with 叮 off
  bool _disposed = false;

  int get version => (room['version'] as int?) ?? -1;
  bool get isOwner => false; // waiting room handles ownership; not needed here
  Map<String, dynamic> get rules =>
      (room['rules'] as Map?)?.cast<String, dynamic>() ?? const {};

  // ── lifecycle ─────────────────────────────────────────────────────────
  void startPolling() {
    _poll ??= Timer.periodic(const Duration(milliseconds: 1200), (_) {
      refresh();
    });
    _tick ??= Timer.periodic(const Duration(milliseconds: 400), (_) {
      _onTick();
    });
    refresh();
  }

  Future<void> refresh() async {
    if (_disposed || _acting) return;
    try {
      final s = await client.state(roomId);
      if (_disposed) return;
      _apply(s);
    } on OnlineException catch (e) {
      // transient poll errors keep the last good state; hard 4xx surface
      if (e.status == 403 || e.status == 404) {
        phase = OnlinePhase.error;
        errorText = e.message;
        _notify();
      }
    } catch (_) {
      // network hiccup — next poll retries
    }
  }

  void _apply(Map<String, dynamic> s) {
    room = (s['room'] as Map).cast<String, dynamic>();
    roster = [
      for (final p in (s['players'] as List? ?? const []))
        OnlinePlayer(
          p['seat'] as int,
          (p['nickname'] as String?) ?? '',
          p['is_bot'] == true,
          p['is_away'] == true,
        )
    ];
    final status = room['status'] as String?;
    final dl = room['turn_deadline'] as String?;
    deadline = dl == null ? null : DateTime.tryParse(dl);

    if (s['view'] != null) {
      view = (s['view'] as Map).cast<String, dynamic>();
      waitingOn = view!['waiting_on'] as int?;
    }

    if (status == 'finished' || (view?['match_over'] == true)) {
      phase = OnlinePhase.finished;
      prompt = Prompt.none;
    } else if (status == 'playing') {
      phase = OnlinePhase.playing;
      _applyPrompt();
    } else if (status == 'waiting') {
      phase = OnlinePhase.waiting;
    }
    _notify();
  }

  // ── wire prompt → UI prompt ───────────────────────────────────────────
  void _applyPrompt() {
    final p = view?['prompt'] as Map?;
    if (p == null) {
      prompt = Prompt.none;
      _stashedDiscard = null;
      return;
    }
    final args = (p['args'] as Map?)?.cast<String, dynamic>() ?? const {};
    switch (p['type'] as String) {
      case 'swap':
        prompt = Prompt(PromptType.swap, n: args['n'] as int);
      case 'ting':
        // engine asks 叮 on every main turn; only surface the toggle when a
        // discard actually leaves the hand ready (mirrors HumanPolicy)
        if (_canDeclareTing()) {
          prompt = const Prompt(PromptType.discard, canTing: true);
        } else {
          prompt = Prompt.none;
          _autoAct('ting', null);
        }
      case 'discard':
        final stash = _stashedDiscard;
        if (stash != null) {
          _stashedDiscard = null;
          prompt = Prompt.none;
          _autoAct('discard', stash); // picked during the 叮 prompt
        } else {
          prompt = const Prompt(PromptType.discard);
        }
      case 'win':
        prompt = const Prompt(PromptType.win);
      case 'kong':
        prompt = Prompt(PromptType.kong, kongOptions: [
          for (final o in (args['options'] as List))
            ((o as List)[0] as int, o[1] as String)
        ]);
      case 'claim':
        prompt = Prompt(PromptType.claim,
            claimKind: args['kind'] as int,
            claimOptions: [for (final o in (args['options'] as List)) o as String]);
      case 'chow':
        prompt = Prompt(PromptType.chow,
            claimKind: args['kind'] as int,
            chowLows: [for (final l in (args['lows'] as List)) l as int]);
      default:
        prompt = Prompt.none;
    }
  }

  bool _canDeclareTing() {
    final v = view;
    if (v == null) return false;
    final counts = [for (final c in (v['counts'] as List)) c as int];
    final jk = v['jokers'] as int;
    final me = (v['players'] as List)[mySeat] as Map;
    final nm = (me['melds'] as List).length;
    for (var k = 0; k < numKinds; k++) {
      if (counts[k] == 0) continue;
      counts[k] -= 1;
      final ok = winningKinds(counts, jk, nm).isNotEmpty;
      counts[k] += 1;
      if (ok) return true;
    }
    return false;
  }

  // ── UI → server (prompt answers; same method names as GameController) ─
  void answerSwap(List<int> kinds) => _answer('swap', kinds);

  void answerDiscard(int kind, {bool ting = false}) {
    // A 'ting' wire prompt is shown as discard+叮toggle. 叮 on → ting kind;
    // 叮 off → decline ting now, discard the same tile when prompted next.
    final wireType = (view?['prompt'] as Map?)?['type'];
    if (wireType == 'ting') {
      if (ting) {
        _answer('ting', kind);
      } else {
        _stashedDiscard = kind;
        _answer('ting', null);
      }
    } else {
      _answer('discard', kind);
    }
  }

  void answerWin(bool yes) => _answer('win', yes);
  void answerKong((int, String)? choice) =>
      _answer('kong', choice == null ? null : [choice.$1, choice.$2]);
  void answerClaim(String? what) => _answer('claim', what);
  void answerChow(int? lo) => _answer('chow', lo);

  void _answer(String type, Object? value) {
    prompt = Prompt.none;
    _notify();
    _autoAct(type, value);
  }

  Future<void> _autoAct(String type, Object? value) async {
    if (_acting || _disposed) return;
    _acting = true;
    try {
      await client.act(roomId, type, value);
    } on OnlineException {
      // 400 illegal / 409 raced — the follow-up refresh re-syncs the prompt
      _stashedDiscard = null;
    } catch (_) {
      // network error — refresh re-syncs
    } finally {
      _acting = false;
    }
    await refresh();
  }

  // ── turn timer ────────────────────────────────────────────────────────
  Duration? get timeLeft {
    final d = deadline;
    if (d == null || phase != OnlinePhase.playing) return null;
    final left = d.difference(DateTime.now());
    return left.isNegative ? Duration.zero : left;
  }

  void _onTick() {
    if (_disposed || phase != OnlinePhase.playing) return;
    final d = deadline;
    if (d != null) {
      // repaint countdown
      _notify();
      // grace expired → any player may apply the bot answer (once/version)
      if (DateTime.now().isAfter(d.add(const Duration(milliseconds: 700))) &&
          _timeoutFiredVersion != version) {
        _timeoutFiredVersion = version;
        _fireTimeout();
      }
    }
  }

  Future<void> _fireTimeout() async {
    try {
      await client.timeout(roomId);
    } catch (_) {
      // someone else fired it first / deadline refreshed — refresh anyway
    }
    await refresh();
  }

  // ── view helpers for widgets ─────────────────────────────────────────
  List<int> get scores =>
      [for (final s in (view?['scores'] as List? ?? [0, 0, 0, 0])) s as int];
  int get handNo => (view?['hand_no'] as int?) ?? 0;
  int get totalHands => (rules['total_hands'] as int?) ?? 8;
  int get dealer => (view?['dealer'] as int?) ?? 0;
  int get repeatN => (view?['repeat_n'] as int?) ?? 0;
  int get wallRemaining => (view?['wall_remaining'] as int?) ?? 0;
  bool get matchOver => view?['match_over'] == true;

  Map<String, dynamic>? seatInfo(int seat) {
    final ps = view?['players'] as List?;
    if (ps == null || seat >= ps.length) return null;
    return (ps[seat] as Map).cast<String, dynamic>();
  }

  String nicknameOf(int seat) {
    for (final p in roster) {
      if (p.seat == seat) {
        if (p.isBot) return '電腦 ${seat + 1}';
        return p.nickname.isEmpty ? '玩家 ${seat + 1}' : p.nickname;
      }
    }
    return '電腦 ${seat + 1}';
  }

  /// Own hand as sorted tile ids (jokers last), from the redacted view.
  List<String> humanHand() {
    final v = view;
    if (v == null) return const [];
    final out = <String>[];
    final counts = v['counts'] as List;
    for (var k = 0; k < numKinds; k++) {
      for (var i = 0; i < (counts[k] as int); i++) {
        out.add(kindToId(k));
      }
    }
    for (var i = 0; i < (v['jokers'] as int); i++) {
      out.add('J0');
    }
    return out;
  }

  /// Ledger rows (creditor, debtor, amount, kou) — same shape as local.
  List<(int, int, int, int)> ledgerRows() => [
        for (final r in (view?['ledger'] as List? ?? const []))
          ((r as List)[0] as int, r[1] as int, r[2] as int, r[3] as int)
      ];

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _poll?.cancel();
    _tick?.cancel();
    super.dispose();
  }
}
