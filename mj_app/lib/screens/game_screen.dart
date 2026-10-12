/// 對局枱面 — landscape table per references 04/05/06:
/// jade felt, centre hub (局數/連莊/餘牌/圈風), four seats (bottom = 你,
/// right/top/left = bots), discard rivers around the hub, own 16-tile hand
/// along the bottom, action pills stacked bottom-right (食/碰/槓/上/叮/過),
/// and the win-settlement overlay (番 rows, payments, 拉數紀錄, 繼續).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mj_core/mj_core.dart';

import '../model/app_settings.dart';
import '../model/game_controller.dart';
import '../theme.dart';
import '../widgets/tile_view.dart';

class GameScreen extends StatefulWidget {
  final FanTable table;
  final MatchConfig config;
  const GameScreen({super.key, required this.table, required this.config});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen>
    with TickerProviderStateMixin {
  late final GameController c;
  final List<int> _swapPicked = []; // hand indices picked for 換牌
  bool _tingArmed = false; // 叮 toggle during discard prompt
  int? _liftedIdx; // two-tap discard: index of the lifted (selected) tile
  Prompt? _lastPrompt; // to reset local prompt state on change

  // gentle repeating pulse: active-seat chips + latest-discard glow
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulse;

  // callout bubble lifecycle (「碰！」 pops in, lingers, fades)
  int _shownCalloutId = -1;
  bool _calloutVisible = false;
  Timer? _calloutTimer;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700))
      ..repeat(reverse: true);
    _pulse = CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut);
    // orientation is locked to landscape app-wide in main()
    c = GameController(widget.table, widget.config);
    c.addListener(_onChange);
    c.startMatch();
  }

  void _onChange() {
    if (!mounted) return;
    if (!identical(c.prompt, _lastPrompt)) {
      _lastPrompt = c.prompt;
      _swapPicked.clear();
      _tingArmed = false;
      _liftedIdx = null;
    }
    // new callout bubble → show, then auto-fade
    final co = c.callout;
    if (co != null && co.id != _shownCalloutId) {
      _shownCalloutId = co.id;
      _calloutVisible = true;
      _calloutTimer?.cancel();
      _calloutTimer = Timer(const Duration(milliseconds: 2200), () {
        if (mounted) setState(() => _calloutVisible = false);
      });
    }
    setState(() {});
  }

  @override
  void dispose() {
    _calloutTimer?.cancel();
    _pulseCtrl.dispose();
    c.removeListener(_onChange);
    c.dispose();
    super.dispose();
  }

  // ── build ─────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MjColors.felt,
      body: SafeArea(
        child: Stack(
          children: [
            // wooden table rim + felt surface (reference 04: the pale jade
            // felt sits inside a warm wooden frame)
            Positioned.fill(
              child: GestureDetector(
                // tapping empty felt cancels a lifted (two-tap) hand tile
                behavior: HitTestBehavior.opaque,
                onTap: _cancelLift,
                child: Container(
                margin: const EdgeInsets.all(4),
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: MjColors.wood,
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(color: MjColors.woodDark, width: 2),
                  boxShadow: const [
                    BoxShadow(
                        color: Colors.black26,
                        blurRadius: 10,
                        offset: Offset(0, 4)),
                  ],
                ),
                child: Container(
                  decoration: BoxDecoration(
                    color: MjColors.feltLight,
                    borderRadius: BorderRadius.circular(19),
                    border: Border.all(color: MjColors.feltEdge, width: 2),
                    // reference 04 is a bright, pale table — keep the jade
                    // weave texture but wash it toward the reference tone
                    image: const DecorationImage(
                      image: AssetImage('assets/table/felt_jade.png'),
                      fit: BoxFit.cover,
                      opacity: 0.55,
                    ),
                  ),
                ),
              ),
              ),
            ),
            _seatArea(2, Alignment.topCenter),
            _seatArea(3, Alignment.centerLeft),
            _seatArea(1, Alignment.centerRight),
            Align(alignment: Alignment.center, child: _hub()),
            _rivers(),
            Align(alignment: Alignment.bottomCenter, child: _humanArea()),
            _calloutLayer(),
            Positioned(right: 12, bottom: 12, child: _actionPills()),
            Positioned(
                left: 10,
                top: 10,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _exitButton(),
                    const SizedBox(width: 8),
                    _rulesSummary(),
                  ],
                )),
            Positioned(right: 12, top: 10, child: _topControls()),
            if (c.handResult != null && !c.matchOver) _winOverlay(),
            if (c.matchOver) _matchEndOverlay(),
          ],
        ),
      ),
    );
  }

  Widget _exitButton() => GestureDetector(
        onTap: () => showDialog<void>(
          context: context,
          builder: (dctx) => AlertDialog(
            backgroundColor: MjColors.ivory,
            title: const Text('離開對局？'),
            content: const Text('依局進度唔會保存。'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(dctx),
                  child: const Text('繼續打')),
              FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: MjColors.coral),
                onPressed: () {
                  Navigator.pop(dctx);
                  Navigator.pop(context);
                },
                child: const Text('離開'),
              ),
            ],
          ),
        ),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: arcadeCard(radius: 12),
          child: const Icon(Icons.logout, size: 18, color: MjColors.charcoal),
        ),
      );

  // ── top-left 規則摘要 (reference 04) ──────────────────────────────────
  Widget _rulesSummary() {
    Widget cell(String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 7),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label,
                  style: const TextStyle(
                      fontSize: 10, color: MjColors.charcoalSoft)),
              Text(value,
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      color: MjColors.charcoal)),
            ],
          ),
        );
    final cfg = c.config;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: arcadeCard(radius: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          cell('百搭', cfg.jokers == 0 ? '無' : '${cfg.jokers}隻'),
          _summaryDivider(),
          cell(
              '換牌',
              switch (cfg.swap) {
                'off' => '無',
                'fixed3' => '換三',
                _ => '擲骰',
              }),
          _summaryDivider(),
          cell('拉/踢半', cfg.laOn ? '計' : '唔計'),
          _summaryDivider(),
          cell('局數', '${cfg.totalHands}局'),
        ],
      ),
    );
  }

  Widget _summaryDivider() =>
      Container(width: 1, height: 22, color: MjColors.outline);

  // ── top-right 音效/說明 round buttons (reference 04) ──────────────────
  Widget _topControls() {
    Widget round(IconData icon, VoidCallback onTap) => GestureDetector(
          onTap: onTap,
          child: Container(
            margin: const EdgeInsets.only(left: 8),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: MjColors.ivory,
              shape: BoxShape.circle,
              border: Border.all(color: MjColors.outline, width: 1.2),
              boxShadow: const [
                BoxShadow(
                    color: Colors.black12,
                    blurRadius: 4,
                    offset: Offset(0, 2)),
              ],
            ),
            child: Icon(icon, size: 18, color: MjColors.charcoal),
          ),
        );
    final s = AppSettings.instance;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        round(s.soundOn ? Icons.volume_up : Icons.volume_off, () async {
          await s.setSoundOn(!s.soundOn);
          setState(() {});
        }),
        round(Icons.question_mark, () => showDialog<void>(
              context: context,
              builder: (dctx) => AlertDialog(
                backgroundColor: MjColors.ivory,
                title: const Text('快速提示'),
                content: const Text(
                    '揀一隻牌打出；有得食/碰/槓/上會彈掣。\n'
                    '差一隻聽糊可以撳「叮」再打牌，叮咗唔可以改牌。\n'
                    '全銃制：邊個出銃邊個找數；自摸三家夾。\n'
                    '完整規則喺主頁「規則書」。'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(dctx),
                      child: const Text('明白')),
                ],
              ),
            )),
      ],
    );
  }

  // ── centre hub (reference 04: wooden SQUARE, wind letters on all four
  // sides, 餘牌 + 局數 stacked in the middle, 連莊 pips along the bottom) ──
  Widget _hub() {
    final remaining = c.engine?.wall.remaining ?? 0;

    // wind letter chip for one edge; lit + pulsing when that seat is on turn
    Widget windChip(int seat) {
      final active = c.turnSeat == seat;
      final chip = Container(
        width: 22,
        height: 22,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? MjColors.coral : MjColors.woodPanel,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
              color: active ? MjColors.coralDark : MjColors.woodDark,
              width: 1),
        ),
        child: Text(_wind(seat),
            style: TextStyle(
                fontSize: 12,
                height: 1.0,
                fontWeight: FontWeight.w900,
                color: active ? Colors.white : MjColors.charcoalSoft)),
      );
      if (!active) return chip;
      return AnimatedBuilder(
        animation: _pulse,
        builder: (_, child) =>
            Transform.scale(scale: 1.0 + 0.18 * _pulse.value, child: child),
        child: chip,
      );
    }

    return Container(
      width: 148,
      height: 148,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: MjColors.wood,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: MjColors.woodDark, width: 2),
        boxShadow: const [
          BoxShadow(
              color: Colors.black26, blurRadius: 8, offset: Offset(0, 4)),
        ],
      ),
      child: Container(
        decoration: BoxDecoration(
          color: MjColors.woodPanel,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: MjColors.woodDark, width: 1),
        ),
        child: Stack(
          children: [
            // four seat winds around the edges (bottom = 你)
            Align(
                alignment: const Alignment(0, -0.92), child: windChip(2)),
            Align(
                alignment: const Alignment(0, 0.92), child: windChip(0)),
            Align(
                alignment: const Alignment(-0.9, 0), child: windChip(3)),
            Align(alignment: const Alignment(0.9, 0), child: windChip(1)),
            // centre stack: 餘牌 / big wind disc / 局數
            Align(
              alignment: const Alignment(0, -0.05),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('餘牌 $remaining',
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: MjColors.charcoalSoft)),
                  const SizedBox(height: 3),
                  Container(
                    width: 38,
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: MjColors.coral,
                      shape: BoxShape.circle,
                      border:
                          Border.all(color: MjColors.coralDark, width: 2),
                    ),
                    child: Text(_wind(c.dealer),
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 19,
                            height: 1.0,
                            fontWeight: FontWeight.w900)),
                  ),
                  const SizedBox(height: 3),
                  Text('第 ${c.handNo} / ${c.config.totalHands} 局',
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w900)),
                ],
              ),
            ),
            // 連莊 pips hugging the bottom edge, beside 你's wind chip
            Align(
              alignment: const Alignment(0, 0.62),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('連莊',
                      style: TextStyle(
                          fontSize: 9,
                          color: c.repeatN > 0
                              ? MjColors.coralDark
                              : MjColors.charcoalSoft,
                          fontWeight: FontWeight.w700)),
                  for (var i = 0; i < 4; i++)
                    Container(
                      width: 7,
                      height: 7,
                      margin: const EdgeInsets.only(left: 3),
                      decoration: BoxDecoration(
                        color: i < c.repeatN
                            ? MjColors.coral
                            : MjColors.outline,
                        shape: BoxShape.circle,
                      ),
                    ),
                  if (c.repeatN > 4)
                    Padding(
                      padding: const EdgeInsets.only(left: 3),
                      child: Text('×${c.repeatN}',
                          style: const TextStyle(
                              fontSize: 9,
                              color: MjColors.coralDark,
                              fontWeight: FontWeight.w900)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── seats ─────────────────────────────────────────────────────────────
  String _wind(int seat) => windNames[(seat - c.dealer + 4) % 4];

  // ── action callout bubbles (「碰！」「叮！」 beside the acting seat) ──
  Widget _calloutLayer() {
    final co = c.callout;
    if (co == null) return const SizedBox.shrink();
    final align = switch (co.seat) {
      0 => const Alignment(0, 0.52),
      1 => const Alignment(0.66, -0.12),
      2 => const Alignment(0, -0.60),
      _ => const Alignment(-0.66, -0.12),
    };
    return IgnorePointer(
      child: Align(
        alignment: align,
        child: AnimatedOpacity(
          opacity: _calloutVisible ? 1 : 0,
          duration: const Duration(milliseconds: 260),
          child: TweenAnimationBuilder<double>(
            key: ValueKey(co.id),
            tween: Tween(begin: 0.3, end: 1.0),
            duration: const Duration(milliseconds: 420),
            curve: Curves.elasticOut,
            builder: (_, s, child) =>
                Transform.scale(scale: s, child: child),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
              decoration: BoxDecoration(
                color: MjColors.ivory,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: MjColors.coral, width: 3),
                boxShadow: const [
                  BoxShadow(
                      color: Colors.black38,
                      blurRadius: 8,
                      offset: Offset(0, 3)),
                ],
              ),
              child: Text(co.text,
                  style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: MjColors.coralDark,
                      letterSpacing: 2)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _seatArea(int seat, Alignment align) {
    if (seat == 0) return const SizedBox.shrink();
    final p = c.engine?.players[seat];
    final active = c.turnSeat == seat;

    // reference 04 seat card: big avatar bubble, name + score, wind chip,
    // gold circled tile count hanging off the corner.
    Widget card = Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(10, 8, 26, 8),
          decoration: arcadeCard(
              color: active ? MjColors.mint : MjColors.ivory,
              border: active ? MjColors.jade : MjColors.outline,
              radius: 18),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: MjColors.brass, width: 2),
                ),
                child: CircleAvatar(
                    radius: 19,
                    backgroundColor: MjColors.panel,
                    backgroundImage: AssetImage(avatarAssets[seat])),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: seat == c.dealer
                            ? MjColors.coral
                            : MjColors.brass,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(_wind(seat),
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w900)),
                    ),
                    const SizedBox(width: 5),
                    Text(aiNames[seat],
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w800)),
                    if (p?.ting == true) ...[
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: MjColors.plum,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text('叮',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w900)),
                      ),
                    ],
                  ]),
                  Text('${c.scores[seat]} 分',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: c.scores[seat] < 0
                              ? MjColors.coralDark
                              : MjColors.jadeDark)),
                ],
              ),
            ],
          ),
        ),
        Positioned(
          right: -6,
          bottom: -6,
          child: Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: MjColors.brass,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: const [
                BoxShadow(
                    color: Colors.black26,
                    blurRadius: 3,
                    offset: Offset(0, 1)),
              ],
            ),
            child: Text('${p?.handSize ?? 0}',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w900)),
          ),
        ),
      ],
    );

    // active seat's plaque gently breathes so the eye tracks whose turn it is
    if (active) {
      card = AnimatedBuilder(
        animation: _pulse,
        builder: (_, child) =>
            Transform.scale(scale: 1.0 + 0.04 * _pulse.value, child: child),
        child: card,
      );
    }

    // rack: face-down hand + melds/flowers; vertical for the side seats
    Widget rack = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (p != null) _backRow(p.handSize),
        if (p != null && (p.melds.isNotEmpty || p.flowers.isNotEmpty))
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: _meldRow(p, tileW: 20),
          ),
      ],
    );
    if (seat == 1) rack = RotatedBox(quarterTurns: 3, child: rack);
    if (seat == 3) rack = RotatedBox(quarterTurns: 1, child: rack);

    final content = switch (seat) {
      2 => Column(mainAxisSize: MainAxisSize.min, children: [
          card,
          const SizedBox(height: 5),
          rack,
        ]),
      3 => Row(mainAxisSize: MainAxisSize.min, children: [
          card,
          const SizedBox(width: 6),
          rack,
        ]),
      _ => Row(mainAxisSize: MainAxisSize.min, children: [
          rack,
          const SizedBox(width: 6),
          card,
        ]),
    };
    return Align(
      alignment: align,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: content,
      ),
    );
  }

  Widget _backRow(int n) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < n; i++)
            const Padding(
              padding: EdgeInsets.only(right: 1.5),
              child: TileView('back', width: 15),
            ),
        ],
      );

  Widget _meldRow(PlayerState p, {double tileW = 20}) {
    final groups = <Widget>[];
    for (var m = 0; m < p.melds.length; m++) {
      final (kind, mtype) = p.melds[m];
      final ids = switch (mtype) {
        'chow' => [kindToId(kind), kindToId(kind + 1), kindToId(kind + 2)],
        'pung' => List.filled(3, kindToId(kind)),
        'kong_concealed' => ['back', kindToId(kind), kindToId(kind), 'back'],
        _ => List.filled(4, kindToId(kind)), // kong_exposed / kong_added
      };
      Widget group = Row(mainAxisSize: MainAxisSize.min, children: [
        for (final id in ids)
          Padding(
              padding: const EdgeInsets.only(right: 1),
              child: TileView(id, width: tileW)),
        const SizedBox(width: 5),
      ]);
      // the newest meld slides/pops into the exposed row
      if (m == p.melds.length - 1) {
        group = TweenAnimationBuilder<double>(
          key: ValueKey('meld-${p.melds.length}-$mtype-$kind'),
          tween: Tween(begin: 0.0, end: 1.0),
          duration: const Duration(milliseconds: 380),
          curve: Curves.easeOutBack,
          builder: (_, t, child) => Opacity(
            opacity: t.clamp(0.0, 1.0),
            child: Transform.scale(
                scale: 0.4 + 0.6 * t,
                child: Transform.translate(
                    offset: Offset(0, 8 * (1 - t)), child: child)),
          ),
          child: group,
        );
      }
      groups.add(group);
    }
    for (final f in p.flowers) {
      groups.add(Padding(
          padding: const EdgeInsets.only(right: 1),
          child: TileView('X$f', width: tileW)));
    }
    return Row(mainAxisSize: MainAxisSize.min, children: groups);
  }

  // ── discard rivers ────────────────────────────────────────────────────
  /// The newest table-wide discard: pops in with a scale, then keeps a
  /// pulsing gold glow until it's claimed or superseded.
  Widget _latestDiscardTile(int seat, int idx, int kind) {
    return TweenAnimationBuilder<double>(
      key: ValueKey('ld-$seat-$idx'),
      tween: Tween(begin: 1.45, end: 1.0),
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutBack,
      builder: (_, s, child) => Transform.scale(scale: s, child: child),
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (_, child) => Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
                color: MjColors.brass
                    .withValues(alpha: 0.35 + 0.65 * _pulse.value),
                width: 2),
            boxShadow: [
              BoxShadow(
                  color: MjColors.brass
                      .withValues(alpha: 0.25 + 0.35 * _pulse.value),
                  blurRadius: 7,
                  spreadRadius: 1),
            ],
          ),
          child: child,
        ),
        child: TileView(kindToId(kind), width: 21),
      ),
    );
  }

  Widget _rivers() {
    Widget river(int seat, Alignment align, EdgeInsets pad) {
      final ds = c.engine?.players[seat].discards ?? const <int>[];
      if (ds.isEmpty) return const SizedBox.shrink();
      final last = c.lastDiscard;
      return Align(
        alignment: align,
        child: Padding(
          padding: pad,
          child: SizedBox(
            width: 190,
            child: Wrap(
              spacing: 1,
              runSpacing: 1,
              alignment: WrapAlignment.center,
              children: [
                for (var i = 0; i < ds.length; i++)
                  if (last != null && last.$1 == seat && last.$2 == i)
                    _latestDiscardTile(seat, i, ds[i])
                  else
                    TileView(kindToId(ds[i]), width: 21),
              ],
            ),
          ),
        ),
      );
    }

    return Stack(children: [
      river(2, const Alignment(0, -0.42), EdgeInsets.zero),
      river(3, const Alignment(-0.42, 0), EdgeInsets.zero),
      river(1, const Alignment(0.42, 0), EdgeInsets.zero),
      river(0, const Alignment(0, 0.32), EdgeInsets.zero),
    ]);
  }

  // ── human area ────────────────────────────────────────────────────────
  Widget _humanArea() {
    final p = c.engine?.players[0];
    final hand = c.humanHand();
    final discarding = c.prompt.type == PromptType.discard;
    final swapping = c.prompt.type == PromptType.swap;

    // reference 04: the hand dominates the bottom edge — scale tiles to
    // fill the width (17 tiles + badge), clamped for sane extremes.
    final w = MediaQuery.sizeOf(context).width;
    // leave room for the fixed action stack hugging the right edge
    final tileW = ((w - 270) / 18).clamp(32.0, 56.0);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (p != null && (p.melds.isNotEmpty || p.flowers.isNotEmpty))
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: _meldRow(p, tileW: tileW * 0.62),
            ),
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _seatBadgeSelf(p),
              const SizedBox(width: 10),
              for (var i = 0; i < hand.length; i++)
                Padding(
                  padding: const EdgeInsets.only(right: 3),
                  child: _handTile(
                    hand[i],
                    tileW: tileW,
                    isNew: discarding && i == c.newTileIdx,
                    raised: (swapping && _swapPicked.contains(i)) ||
                        (discarding && i == _liftedIdx),
                    onTap: (discarding || swapping)
                        ? () => _tapHandTile(i, hand[i])
                        : null,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// A hand tile; the freshly drawn tile (isNew) drops in from above and
  /// stays slightly lifted so the player can spot it instantly.
  Widget _handTile(String id,
      {required double tileW,
      required bool isNew,
      required bool raised,
      VoidCallback? onTap}) {
    final tile =
        TileView(id, width: tileW, raised: raised, onTap: onTap);
    if (!isNew) return tile;
    return TweenAnimationBuilder<double>(
      key: ValueKey('new-$id-${c.newTileIdx}'),
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutBack,
      builder: (_, t, child) => Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(0, -14 * (1 - t) - 6),
          child: child,
        ),
      ),
      child: tile,
    );
  }

  Widget _seatBadgeSelf(PlayerState? p) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: arcadeCard(
            color: c.turnSeat == 0 ? MjColors.mint : MjColors.ivory,
            border: c.turnSeat == 0 ? MjColors.jade : MjColors.outline,
            radius: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              CircleAvatar(
                  radius: 11,
                  backgroundColor: MjColors.brass,
                  backgroundImage: AssetImage(avatarAssets[0])),
              const SizedBox(width: 4),
              Text(_wind(0),
                  style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      color: MjColors.brassDark)),
              const SizedBox(width: 4),
              const Text('你',
                  style:
                      TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
              if (p?.ting == true)
                const Text(' 叮',
                    style: TextStyle(
                        fontSize: 11,
                        color: MjColors.plum,
                        fontWeight: FontWeight.w900)),
            ]),
            Text('${c.scores[0]} 分',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: c.scores[0] < 0
                        ? MjColors.coralDark
                        : MjColors.jadeDark)),
          ],
        ),
      );

  void _tapHandTile(int i, String id) {
    if (c.prompt.type == PromptType.swap) {
      if (id == 'J0') {
        _toast('百搭唔可以換出');
        return;
      }
      setState(() {
        if (_swapPicked.contains(i)) {
          _swapPicked.remove(i);
        } else if (_swapPicked.length < c.prompt.n) {
          _swapPicked.add(i);
        }
      });
      return;
    }
    // discard — two-tap: first tap lifts the tile, tapping the SAME tile
    // again plays it; tapping another tile switches the lift; tapping the
    // empty felt (see build background) cancels.
    if (id == 'J0') {
      _toast('百搭唔可以打出');
      return;
    }
    if (_liftedIdx != i) {
      setState(() => _liftedIdx = i);
      return;
    }
    _liftedIdx = null;
    c.answerDiscard(idToKind(id), ting: _tingArmed);
  }

  void _cancelLift() {
    if (_liftedIdx != null) setState(() => _liftedIdx = null);
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
          content: Text(msg), duration: const Duration(seconds: 1)));
  }

  // ── action pills ──────────────────────────────────────────────────────
  // reference 04/05: chunky rounded-square buttons stacked vertically on
  // the right edge, one bold character each, white ring + drop shadow.
  // Only the buttons that are usable RIGHT NOW appear (sliding in from the
  // right edge); the column is empty the rest of the time so the table
  // stays clean. 叮 shows only when the hand can actually declare it.
  Widget _pill(String label, Color color, VoidCallback? onTap,
      {Widget? extra}) {
    final enabled = onTap != null;
    final bg = enabled ? color : MjColors.stone.withValues(alpha: 0.55);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(top: 8),
        constraints: const BoxConstraints(minWidth: 58, minHeight: 48),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: Colors.white.withValues(alpha: enabled ? 0.85 : 0.4),
              width: 2),
          boxShadow: enabled
              ? const [
                  BoxShadow(
                      color: Colors.black38,
                      blurRadius: 5,
                      offset: Offset(0, 3)),
                ]
              : const [],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(label,
                style: TextStyle(
                    color: Colors.white
                        .withValues(alpha: enabled ? 1.0 : 0.65),
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    shadows: enabled
                        ? const [
                            Shadow(
                                color: Colors.black26,
                                blurRadius: 2,
                                offset: Offset(0, 1)),
                          ]
                        : const [])),
            if (extra != null) ...[const SizedBox(width: 6), extra],
          ],
        ),
      ),
    );
  }

  /// Small tile-preview chips shown ABOVE the fixed stack when an action
  /// needs the player to pick between options (multiple 上, 暗槓/加槓).
  Widget _optionChip(List<Widget> tiles, VoidCallback onTap,
      {String? label}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(top: 6),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: arcadeCard(color: MjColors.ivory, radius: 12),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (label != null) ...[
            Text(label,
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w900)),
            const SizedBox(width: 5),
          ],
          ...tiles,
        ]),
      ),
    );
  }

  /// Titled ivory panel that groups multiple option chips (reference 05's
  /// 「冠積選擇」card sitting beside the pill stack).
  Widget _optionPanel(String title, List<Widget> chips) {
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
      decoration: arcadeCard(color: MjColors.ivory, radius: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 6,
              height: 14,
              margin: const EdgeInsets.only(right: 6),
              decoration: BoxDecoration(
                  color: MjColors.coral,
                  borderRadius: BorderRadius.circular(3)),
            ),
            Text(title,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: MjColors.charcoal)),
          ]),
          ...chips,
        ],
      ),
    );
  }

  Widget _actionPills() {
    final p = c.prompt;
    final above = <Widget>[]; // hint cards / option choosers
    // resolved callbacks for the six fixed buttons (null = greyed)
    VoidCallback? onSik, onPung, onKong, onSheung, onTing, onGwo;

    switch (p.type) {
      case PromptType.none:
        break;
      case PromptType.swap:
        above.add(Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: arcadeCard(radius: 14),
          child: Text('揀 ${p.n} 隻換畀下家（${_swapPicked.length}/${p.n}）',
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w800)),
        ));
        if (_swapPicked.length == p.n) {
          above.add(_pill('換牌', MjColors.jade, () {
            final hand = c.humanHand();
            c.answerSwap([for (final i in _swapPicked) idToKind(hand[i])]);
          }));
        }
      case PromptType.discard:
        if (p.canTing) {
          onTing = () => setState(() => _tingArmed = !_tingArmed);
        }
      case PromptType.win:
        onSik = () => c.answerWin(true);
        onGwo = () => c.answerWin(false);
      case PromptType.kong:
        if (p.kongOptions.length == 1) {
          onKong = () => c.answerKong(p.kongOptions.single);
        } else {
          above.add(_optionPanel('槓牌選擇', [
            for (final opt in p.kongOptions)
              _optionChip(
                [TileView(kindTileId(opt.$1), width: 24)],
                () => c.answerKong(opt),
                label: opt.$2 == 'concealed' ? '暗槓' : '加槓',
              ),
          ]));
        }
        onGwo = () => c.answerKong(null);
      case PromptType.claim:
        for (final what in p.claimOptions) {
          if (what == 'pung') onPung = () => c.answerClaim('pung');
          if (what == 'kong') onKong = () => c.answerClaim('kong');
        }
        onGwo = () => c.answerClaim(null);
      case PromptType.chow:
        if (p.chowLows.length == 1) {
          onSheung = () => c.answerChow(p.chowLows.single);
        } else {
          above.add(_optionPanel('上牌選擇', [
            for (final lo in p.chowLows)
              _optionChip(
                [
                  for (var k = lo; k < lo + 3; k++)
                    Padding(
                      padding: const EdgeInsets.only(left: 1),
                      child: TileView(kindToId(k), width: 22),
                    ),
                ],
                () => c.answerChow(lo),
              ),
          ]));
        }
        onGwo = () => c.answerChow(null);
    }

    // build only the actionable pills, each sliding in from the right with
    // a small stagger; 叮 gets a gentle attention pulse until armed.
    final pills = <Widget>[];
    void addPill(String keyId, String label, Color color, VoidCallback? cb,
        {bool pulse = false}) {
      if (cb == null) return;
      Widget w = _pill(label, color, cb);
      if (pulse) {
        w = AnimatedBuilder(
          animation: _pulse,
          builder: (_, child) => Transform.scale(
              scale: 1.0 + 0.05 * _pulse.value, child: child),
          child: w,
        );
      }
      final idx = pills.length;
      pills.add(TweenAnimationBuilder<double>(
        key: ValueKey('pill-$keyId-${identityHashCode(p)}'),
        tween: Tween(begin: 0, end: 1),
        duration: Duration(milliseconds: 200 + idx * 55),
        curve: Curves.easeOutBack,
        builder: (_, t, child) => Opacity(
          opacity: t.clamp(0.0, 1.0),
          child: Transform.translate(
              offset: Offset(46 * (1 - t), 0), child: child),
        ),
        child: w,
      ));
    }

    addPill('sik', '食', MjColors.coral, onSik);
    addPill('pung', '碰', MjColors.orange, onPung);
    addPill('kong', '槓', MjColors.teal, onKong);
    addPill('sheung', '上', MjColors.paleBlue, onSheung);
    addPill('ting', _tingArmed ? '叮✓' : '叮', MjColors.plum, onTing,
        pulse: !_tingArmed);
    addPill('gwo', '過', MjColors.stone, onGwo);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [...above, ...pills],
    );
  }

  // ── win / hand-end overlay ────────────────────────────────────────────
  Widget _winOverlay() {
    final res = c.handResult!;
    final title = switch (res.kind) {
      'win' => res.discarder == null ? '自摸！' : '食出銃！',
      'flower_hu' => '花糊！',
      _ => '流局',
    };
    return _overlayShell(
      title: title,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (seat, sr) in res.winners) _winnerPanel(seat, sr),
          if (res.kind == 'flower_hu' && res.seat != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text('${aiNames[res.seat!]} 八隻花，花糊即食',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
          if (res.kind == 'exhaust')
            const Padding(
              padding: EdgeInsets.only(bottom: 6),
              child: Text('摸完都冇人食，呢局打和',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: MjColors.charcoalSoft)),
            ),
          if (c.handDeltas.isNotEmpty) _paymentsPanel(),
          if (c.ledgerRows().isNotEmpty) _ledgerPanel(),
        ],
      ),
      button: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: MjColors.jade,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        onPressed: c.continueMatch,
        child: Text(
            c.handNo >= c.config.totalHands ? '睇總結算' : '繼續 · 下一局',
            style: const TextStyle(
                fontSize: 16, fontWeight: FontWeight.w900)),
      ),
    );
  }

  /// Reference 06: the winner's full hand laid out in one tile row —
  /// melds first, then the concealed tiles rebuilt from engine counts.
  Widget _winnerHandRow(int seat) {
    final p = c.engine?.players[seat];
    if (p == null) return const SizedBox.shrink();
    final tiles = <Widget>[];
    void add(String id) {
      final i = tiles.length;
      tiles.add(Padding(
        padding: const EdgeInsets.only(right: 2),
        child: TweenAnimationBuilder<double>(
          key: ValueKey('wh-$seat-$i'),
          tween: Tween(begin: 0, end: 1),
          duration: Duration(milliseconds: 240 + i * 45),
          curve: Curves.easeOutBack,
          builder: (_, t, child) => Opacity(
            opacity: t.clamp(0.0, 1.0),
            child: Transform.translate(
                offset: Offset(0, 10 * (1 - t)), child: child),
          ),
          child: TileView(id, width: 26),
        ),
      ));
    }
    for (final (kind, mtype) in p.melds) {
      final ids = switch (mtype) {
        'chow' => [kindToId(kind), kindToId(kind + 1), kindToId(kind + 2)],
        'pung' => List.filled(3, kindToId(kind)),
        'kong_concealed' => ['back', kindToId(kind), kindToId(kind), 'back'],
        _ => List.filled(4, kindToId(kind)),
      };
      ids.forEach(add);
      tiles.add(const SizedBox(width: 6));
    }
    for (var k = 0; k < p.counts.length; k++) {
      for (var i = 0; i < p.counts[k]; i++) {
        add(kindToId(k));
      }
    }
    for (var i = 0; i < p.jokers; i++) {
      add('J0');
    }
    if (tiles.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF3E8E6B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MjColors.woodDark, width: 2),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(mainAxisSize: MainAxisSize.min, children: tiles),
      ),
    );
  }

  Widget _winnerPanel(int seat, ScoreResult sr) {
    final table = c.table;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: arcadeCard(color: MjColors.mint, radius: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            CircleAvatar(
                radius: 12,
                backgroundColor: MjColors.brass,
                backgroundImage: AssetImage(avatarAssets[seat])),
            const SizedBox(width: 6),
            Text('${aiNames[seat]} 食糊',
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: MjColors.jadeDark)),
          ]),
          const SizedBox(height: 6),
          _winnerHandRow(seat),
          for (final (id, n, pts) in sr.fans)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 1.5),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                        (table.byId[id]?.name ?? id) +
                            (n > 1 ? ' ×$n' : ''),
                        style: const TextStyle(fontSize: 13)),
                  ),
                  Text('$pts番',
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w800)),
                ],
              ),
            ),
          const SizedBox(height: 8),
          // reference 06: big red 合計 total block
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: MjColors.coral,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: MjColors.coralDark, width: 2),
            ),
            child: Row(
              children: [
                const Expanded(
                    child: Text('合計',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            color: Colors.white))),
                TweenAnimationBuilder<double>(
                  key: ValueKey('total-$seat-${sr.total}'),
                  tween: Tween(begin: 0, end: sr.total.toDouble()),
                  duration: const Duration(milliseconds: 900),
                  curve: Curves.easeOutCubic,
                  builder: (_, v, __) => Text('${v.round()} 番',
                      style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: Colors.white)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _paymentsPanel() => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: arcadeCard(radius: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('找數',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            for (final d in c.handDeltas)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 1.5),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                          '${aiNames[d.frm]} → ${aiNames[d.to]}',
                          style: const TextStyle(fontSize: 13)),
                    ),
                    Text('${d.amount} 分',
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
          ],
        ),
      );

  Widget _ledgerPanel({List<(int, int, int, int)>? rows, bool wiped = false}) {
    final data = rows ?? c.ledgerRows();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: arcadeCard(color: MjColors.panel, radius: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(wiped ? '拉數紀錄（完場勾銷）' : '拉數紀錄（未清）',
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          for (final (cr, db, amt, kou) in data)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 1.5),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${aiNames[db]} 欠 ${aiNames[cr]}'
                      '${kou > 0 ? '（${kou}扣）' : ''}',
                      style: TextStyle(
                          fontSize: 13,
                          decoration:
                              wiped ? TextDecoration.lineThrough : null),
                    ),
                  ),
                  Text('$amt 分',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          decoration:
                              wiped ? TextDecoration.lineThrough : null)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ── match end ─────────────────────────────────────────────────────────
  Widget _matchEndOverlay() {
    final order = [0, 1, 2, 3]
      ..sort((a, b) => c.scores[b].compareTo(c.scores[a]));
    return _overlayShell(
      title: '完場結算',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: arcadeCard(color: MjColors.mint, radius: 14),
            child: Column(
              children: [
                for (var i = 0; i < 4; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        Text('${i + 1}.',
                            style: const TextStyle(
                                fontWeight: FontWeight.w900)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(aiNames[order[i]],
                              style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800)),
                        ),
                        Text('${c.scores[order[i]]} 分',
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w900,
                                color: c.scores[order[i]] < 0
                                    ? MjColors.coralDark
                                    : MjColors.jadeDark)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          if ((c.wipedLedger ?? const []).isNotEmpty)
            _ledgerPanel(rows: c.wipedLedger, wiped: true),
        ],
      ),
      button: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: MjColors.coral,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        onPressed: () => Navigator.pop(context),
        child: const Text('返回主頁',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
      ),
    );
  }

  Widget _overlayShell(
      {required String title,
      required Widget body,
      required Widget button}) {
    // reference 06: wide cream card with a tilted coral banner title
    // popping over its top edge, gold trim. The whole card fades/settles
    // in and the banner slams down from oversized for drama.
    return Positioned.fill(
      child: TweenAnimationBuilder<double>(
        key: ValueKey('overlay-$title'),
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
        builder: (_, t, child) => Opacity(
          opacity: t.clamp(0.0, 1.0),
          child: Transform.scale(scale: 0.92 + 0.08 * t, child: child),
        ),
        child: Container(
        color: Colors.black38,
        alignment: Alignment.center,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 430),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 20),
                padding: const EdgeInsets.fromLTRB(18, 34, 18, 16),
                decoration: BoxDecoration(
                  color: MjColors.ivory,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: MjColors.brass, width: 2),
                  boxShadow: const [
                    BoxShadow(
                        color: Colors.black38,
                        blurRadius: 14,
                        offset: Offset(0, 6)),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Flexible(child: SingleChildScrollView(child: body)),
                    const SizedBox(height: 8),
                    button,
                  ],
                ),
              ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Center(
                  child: TweenAnimationBuilder<double>(
                    key: ValueKey('banner-$title'),
                    tween: Tween(begin: 0, end: 1),
                    duration: const Duration(milliseconds: 480),
                    curve: Curves.elasticOut,
                    builder: (_, t, child) => Transform.scale(
                        scale: 2.2 - 1.2 * t.clamp(0.0, 1.35),
                        child: Opacity(
                            opacity: t.clamp(0.0, 1.0), child: child)),
                    child: Transform.rotate(
                    angle: -0.045,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 26, vertical: 8),
                      decoration: BoxDecoration(
                        color: MjColors.coral,
                        borderRadius: BorderRadius.circular(14),
                        border:
                            Border.all(color: MjColors.brass, width: 2),
                        boxShadow: const [
                          BoxShadow(
                              color: Colors.black38,
                              blurRadius: 6,
                              offset: Offset(0, 3)),
                        ],
                      ),
                      child: Text(title,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 21,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              letterSpacing: 2,
                              shadows: [
                                Shadow(
                                    color: Colors.black26,
                                    blurRadius: 2,
                                    offset: Offset(0, 1)),
                              ])),
                    ),
                  ),
                  ),
                ),
              ),
            ],
          ),
        ),
        ),
      ),
    );
  }
}
