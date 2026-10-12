/// Online table — renders the redacted per-seat view served by the `mj`
/// edge function (see mj_core clientView). Own seat always sits at the
/// bottom; the physical seat order rotates around it. Other hands appear
/// only as tile backs (their contents never leave the server).
library;

import 'package:flutter/material.dart';
import 'package:mj_core/mj_core.dart' show idToKind, kindToId;

import '../model/game_controller.dart' show Prompt, PromptType, windNames;
import '../model/online_controller.dart';
import '../theme.dart';
import '../widgets/tile_view.dart';

class OnlineGameScreen extends StatefulWidget {
  final OnlineGameController controller;
  const OnlineGameScreen({super.key, required this.controller});

  @override
  State<OnlineGameScreen> createState() => _OnlineGameScreenState();
}

class _OnlineGameScreenState extends State<OnlineGameScreen> {
  OnlineGameController get c => widget.controller;
  final Set<int> _swapPicked = {}; // indices into humanHand()
  bool _tingArmed = false;
  Prompt? _lastPrompt;

  @override
  void initState() {
    super.initState();
    c.addListener(_onChange);
  }

  void _onChange() {
    if (!identical(c.prompt, _lastPrompt)) {
      _lastPrompt = c.prompt;
      _swapPicked.clear();
      _tingArmed = false;
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    c.removeListener(_onChange);
    super.dispose();
  }

  /// Physical seat shown at relative position [rel] (0=bottom/me, 1=right,
  /// 2=top, 3=left — counter-clockwise, real-table order).
  int _seatAt(int rel) => (c.mySeat + rel) % 4;

  String _wind(int seat) => windNames[(seat - c.dealer + 4) % 4];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MjColors.feltLight,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                _topBar(),
                Expanded(
                  child: Row(
                    children: [
                      Expanded(flex: 5, child: _sidePanel(_seatAt(3))),
                      Expanded(
                        flex: 14,
                        child: Column(
                          children: [
                            Expanded(child: _sidePanel(_seatAt(2))),
                            _centerHub(),
                            Expanded(child: _ownDiscards()),
                          ],
                        ),
                      ),
                      Expanded(flex: 5, child: _sidePanel(_seatAt(1))),
                    ],
                  ),
                ),
                _ownArea(),
              ],
            ),
            if (c.phase == OnlinePhase.finished || c.matchOver)
              _matchEndOverlay(context),
          ],
        ),
      ),
    );
  }

  // ── chrome ────────────────────────────────────────────────────────────
  Widget _topBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: MjColors.cream,
      child: Row(
        children: [
          Text('房 ${c.roomId}',
              style: const TextStyle(
                  fontWeight: FontWeight.w900, color: MjColors.jadeDark)),
          const SizedBox(width: 14),
          Text('第 ${c.handNo} / ${c.totalHands} 局',
              style: const TextStyle(fontWeight: FontWeight.w700)),
          if (c.repeatN > 0)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text('連莊×${c.repeatN}',
                  style: const TextStyle(
                      color: MjColors.coral, fontWeight: FontWeight.w800)),
            ),
          const Spacer(),
          _timerChip(),
          const SizedBox(width: 12),
          Text('剩 ${c.wallRemaining} 隻',
              style: const TextStyle(color: MjColors.charcoalSoft)),
        ],
      ),
    );
  }

  Widget _timerChip() {
    final left = c.timeLeft;
    if (left == null) return const SizedBox.shrink();
    final secs = (left.inMilliseconds / 1000).ceil();
    final mine = c.waitingOn == c.mySeat;
    final who = mine ? '到你喇' : '等緊 ${c.nicknameOf(c.waitingOn ?? 0)}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: mine ? MjColors.coral : MjColors.panel,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text('$who · $secs 秒',
          style: TextStyle(
              color: mine ? Colors.white : MjColors.charcoalSoft,
              fontWeight: FontWeight.w800,
              fontSize: 12)),
    );
  }

  Widget _centerHub() {
    return Container(
      width: 120,
      height: 64,
      decoration: BoxDecoration(
        color: MjColors.wood,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MjColors.woodDark, width: 2),
      ),
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('${_wind(c.mySeat)}位',
              style: const TextStyle(
                  color: MjColors.woodPanel,
                  fontWeight: FontWeight.w900,
                  fontSize: 16)),
          Text('莊：${c.nicknameOf(c.dealer)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: MjColors.woodPanel, fontSize: 11)),
        ],
      ),
    );
  }

  // ── opponent panels ───────────────────────────────────────────────────
  Widget _sidePanel(int seat) {
    final info = c.seatInfo(seat);
    if (info == null) return const SizedBox.shrink();
    final active = c.waitingOn == seat;
    final ting = info['ting'] == true;
    final handSize = info['hand_size'] as int? ?? 0;
    return Container(
      margin: const EdgeInsets.all(4),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: active ? MjColors.mint : MjColors.ivory.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: active ? MjColors.jade : MjColors.outline),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _windBadge(seat),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(c.nicknameOf(seat),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 12)),
                ),
                if (ting)
                  const Text('叮',
                      style: TextStyle(
                          color: MjColors.plum,
                          fontWeight: FontWeight.w900)),
              ],
            ),
            Text('${c.scores[seat]} 分',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: c.scores[seat] < 0
                        ? MjColors.coral
                        : MjColors.charcoalSoft)),
            const SizedBox(height: 3),
            // concealed hand as backs
            Wrap(spacing: 1, runSpacing: 1, children: [
              for (var i = 0; i < handSize; i++)
                const TileView('back', width: 12),
            ]),
            if ((info['melds'] as List).isNotEmpty ||
                (info['flowers'] as List).isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: _meldWrap(info, tileW: 14),
              ),
            if ((info['discards'] as List).isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Wrap(spacing: 1, runSpacing: 1, children: [
                  for (final k in (info['discards'] as List))
                    TileView(kindToId(k as int), width: 14),
                ]),
              ),
          ],
        ),
      ),
    );
  }

  Widget _windBadge(int seat) => Container(
        width: 20,
        height: 20,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: seat == c.dealer ? MjColors.coral : MjColors.panel,
          shape: BoxShape.circle,
        ),
        child: Text(_wind(seat),
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w900,
                color: seat == c.dealer ? Colors.white : MjColors.charcoal)),
      );

  Widget _meldWrap(Map<String, dynamic> info, {double tileW = 16}) {
    final tiles = <String>[];
    for (final m in (info['melds'] as List)) {
      final kind = (m as List)[0] as int;
      final mtype = m[1] as String;
      tiles.addAll(switch (mtype) {
        'chow' => [kindToId(kind), kindToId(kind + 1), kindToId(kind + 2)],
        'pung' => List.filled(3, kindToId(kind)),
        'kong_concealed' => ['back', kindToId(kind), kindToId(kind), 'back'],
        _ => List.filled(4, kindToId(kind)),
      });
    }
    for (final f in (info['flowers'] as List)) {
      tiles.add('X$f');
    }
    return Wrap(spacing: 1, runSpacing: 1, children: [
      for (final id in tiles) TileView(id, width: tileW),
    ]);
  }

  // ── own side ──────────────────────────────────────────────────────────
  Widget _ownDiscards() {
    final info = c.seatInfo(c.mySeat);
    final ds = (info?['discards'] as List?) ?? const [];
    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Wrap(spacing: 2, runSpacing: 2, children: [
          for (final k in ds) TileView(kindToId(k as int), width: 18),
        ]),
      ),
    );
  }

  Widget _ownArea() {
    final info = c.seatInfo(c.mySeat);
    final hand = c.humanHand();
    final discarding = c.prompt.type == PromptType.discard;
    final swapping = c.prompt.type == PromptType.swap;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
      color: MjColors.cream,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _actionBar(),
          Row(
            children: [
              _windBadge(c.mySeat),
              const SizedBox(width: 6),
              Text(c.nicknameOf(c.mySeat),
                  style: const TextStyle(fontWeight: FontWeight.w900)),
              const SizedBox(width: 10),
              Text('${c.scores[c.mySeat]} 分',
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: c.scores[c.mySeat] < 0
                          ? MjColors.coral
                          : MjColors.charcoalSoft)),
              if (info?['ting'] == true)
                const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: Text('已叮',
                      style: TextStyle(
                          color: MjColors.plum, fontWeight: FontWeight.w900)),
                ),
              const Spacer(),
              if (info != null &&
                  ((info['melds'] as List).isNotEmpty ||
                      (info['flowers'] as List).isNotEmpty))
                _meldWrap(info, tileW: 18),
            ],
          ),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < hand.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(right: 2),
                    child: TileView(
                      hand[i],
                      width: 34,
                      raised: swapping && _swapPicked.contains(i),
                      onTap: (discarding || swapping)
                          ? () => _tapTile(i, hand[i])
                          : null,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _tapTile(int index, String id) {
    if (c.prompt.type == PromptType.swap) {
      setState(() {
        if (_swapPicked.contains(index)) {
          _swapPicked.remove(index);
        } else if (_swapPicked.length < c.prompt.n) {
          _swapPicked.add(index);
        }
      });
      return;
    }
    if (c.prompt.type == PromptType.discard) {
      c.answerDiscard(idToKind(id), ting: _tingArmed);
    }
  }

  // ── prompt action bar ─────────────────────────────────────────────────
  Widget _actionBar() {
    final p = c.prompt;
    final buttons = <Widget>[];

    void add(String label, Color color, VoidCallback? onTap) {
      buttons.add(Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: FilledButton(
          style: FilledButton.styleFrom(
              backgroundColor: color,
              padding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 10)),
          onPressed: onTap,
          child: Text(label,
              style:
                  const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
        ),
      ));
    }

    switch (p.type) {
      case PromptType.none:
        return const SizedBox.shrink();
      case PromptType.discard:
        if (!p.canTing) return const SizedBox.shrink();
        buttons.add(Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: FilledButton.tonal(
            style: FilledButton.styleFrom(
                backgroundColor:
                    _tingArmed ? MjColors.plum : MjColors.panel,
                foregroundColor:
                    _tingArmed ? Colors.white : MjColors.charcoal),
            onPressed: () => setState(() => _tingArmed = !_tingArmed),
            child: Text(_tingArmed ? '叮 · 揀隻牌打出' : '叮',
                style: const TextStyle(fontWeight: FontWeight.w900)),
          ),
        ));
      case PromptType.swap:
        add(
            '換牌（${_swapPicked.length}/${p.n}）',
            MjColors.jade,
            _swapPicked.length == p.n
                ? () {
                    final hand = c.humanHand();
                    c.answerSwap(
                        [for (final i in _swapPicked) idToKind(hand[i])]);
                  }
                : null);
      case PromptType.win:
        add('食糊！', MjColors.coral, () => c.answerWin(true));
        add('唔食', MjColors.stone, () => c.answerWin(false));
      case PromptType.kong:
        for (final opt in p.kongOptions) {
          add('槓 ${kindToId(opt.$1)}${opt.$2 == 'concealed' ? '（暗）' : ''}',
              MjColors.brass, () => c.answerKong(opt));
        }
        add('過', MjColors.stone, () => c.answerKong(null));
      case PromptType.claim:
        for (final what in p.claimOptions) {
          if (what == 'pung') {
            add('碰', MjColors.orange, () => c.answerClaim('pung'));
          }
          if (what == 'kong') {
            add('槓', MjColors.brass, () => c.answerClaim('kong'));
          }
        }
        add('過', MjColors.stone, () => c.answerClaim(null));
      case PromptType.chow:
        for (final lo in p.chowLows) {
          add('上 ${kindToId(lo)}-${kindToId(lo + 2)}', MjColors.paleBlue,
              () => c.answerChow(lo));
        }
        add('過', MjColors.stone, () => c.answerChow(null));
    }
    if (buttons.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: buttons),
    );
  }

  // ── match end ─────────────────────────────────────────────────────────
  Widget _matchEndOverlay(BuildContext context) {
    final order = [0, 1, 2, 3]
      ..sort((a, b) => c.scores[b].compareTo(c.scores[a]));
    return Container(
      color: Colors.black45,
      alignment: Alignment.center,
      child: Container(
        width: 420,
        padding: const EdgeInsets.all(20),
        decoration: arcadeCard(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('總結算',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
            const SizedBox(height: 12),
            for (var i = 0; i < 4; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Text('${i + 1}.',
                        style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            color: MjColors.charcoalSoft)),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(c.nicknameOf(order[i]),
                            style: TextStyle(
                                fontWeight: order[i] == c.mySeat
                                    ? FontWeight.w900
                                    : FontWeight.w600))),
                    Text('${c.scores[order[i]]} 分',
                        style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: c.scores[order[i]] < 0
                                ? MjColors.coral
                                : MjColors.jadeDark)),
                  ],
                ),
              ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(backgroundColor: MjColors.jade),
                onPressed: () =>
                    Navigator.popUntil(context, (r) => r.isFirst),
                child: const Text('返回大廳',
                    style: TextStyle(fontWeight: FontWeight.w900)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
