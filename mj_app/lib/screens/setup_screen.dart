/// 開房設定 — per reference 02-room-setup.png: preset cards on top,
/// individual option groups (百搭/換牌/拉·踢半/局數) below, a live 規則摘要
/// strip, and the big 開始 button. Used here for 單機 config; the same
/// widget will back the online 開房 flow in M3.
library;

import 'package:flutter/material.dart';

import '../main.dart';
import '../model/app_settings.dart';
import '../model/game_controller.dart';
import '../theme.dart';
import 'game_screen.dart';

class _Preset {
  final String name;
  final String blurb;
  final int jokers;
  final String swap;
  final bool laOn;
  final Color color;
  const _Preset(this.name, this.blurb, this.jokers, this.swap, this.laOn,
      this.color);
}

const _presets = [
  _Preset('協會新章', '總例標準：無百搭、無換牌、拉·踢半照計', 0, 'off', true,
      MjColors.jade),
  _Preset('新手場', '規則簡化：無百搭、無換牌、唔計拉數', 0, 'off', false,
      MjColors.paleBlue),
  _Preset('百搭歡樂場', '8隻百搭 + 擲骰換牌，刺激啲', 8, 'dice', true,
      MjColors.coral),
];

class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  int jokers = 0;
  String swap = 'off';
  bool laOn = true;
  int totalHands = 8;
  int? presetIdx = 0;

  void _applyPreset(int i) {
    final p = _presets[i];
    setState(() {
      presetIdx = i;
      jokers = p.jokers;
      swap = p.swap;
      laOn = p.laOn;
    });
  }

  void _custom(VoidCallback change) {
    setState(() {
      presetIdx = null;
      change();
    });
  }

  String get _summary {
    final j = jokers == 0 ? '無百搭' : '百搭×$jokers';
    final s = switch (swap) {
      'off' => '無換牌',
      'fixed3' => '換三張',
      _ => '擲骰換牌',
    };
    final l = laOn ? '拉·踢半照計' : '唔計拉數';
    return '$j · $s · $l · $totalHands局';
  }

  void _start() {
    final table = FanTableStore.of(context).working;
    final config = MatchConfig(
        jokers: jokers,
        swap: swap,
        laOn: laOn,
        totalHands: totalHands,
        botDelayMs: AppSettings.instance.botDelayMs);
    Navigator.pushReplacement(
        context,
        MaterialPageRoute(
            builder: (_) => GameScreen(table: table, config: config)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('開房設定 · 單機')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                children: [
                  _sectionLabel('快速預設'),
                  ...List.generate(_presets.length, _presetCard),
                  const SizedBox(height: 14),
                  _sectionLabel('百搭'),
                  _choiceRow<int>(
                    value: jokers,
                    options: const [(0, '唔要'), (4, '4隻'), (8, '8隻')],
                    onPick: (v) => _custom(() => jokers = v),
                  ),
                  const SizedBox(height: 14),
                  _sectionLabel('開局換牌'),
                  _choiceRow<String>(
                    value: swap,
                    options: const [
                      ('off', '唔換'),
                      ('fixed3', '換三張'),
                      ('dice', '擲骰決定'),
                    ],
                    onPick: (v) => _custom(() => swap = v),
                  ),
                  const SizedBox(height: 14),
                  _sectionLabel('拉 · 踢半'),
                  Container(
                    decoration: arcadeCard(),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('出銃唔即付，記拉數（×1.5 覆利）',
                          style: TextStyle(fontSize: 14)),
                      subtitle: const Text('完場未清嘅拉數一筆勾銷',
                          style: TextStyle(
                              fontSize: 12, color: MjColors.charcoalSoft)),
                      value: laOn,
                      onChanged: (v) => _custom(() => laOn = v),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _sectionLabel('局數'),
                  _choiceRow<int>(
                    value: totalHands,
                    options: const [(4, '4局'), (8, '8局'), (16, '16局')],
                    onPick: (v) => setState(() => totalHands = v),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ],
        ),
      ),
      // bottomNavigationBar (not bottomSheet) so Scaffold reserves its
      // height — the old floating sheet overlapped the 拉·踢半 row in
      // landscape. Summary + button sit in one row to keep it short.
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          color: MjColors.cream,
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
          child: Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                  decoration: arcadeCard(color: MjColors.mint, radius: 14),
                  child: Row(
                    children: [
                      const Icon(Icons.receipt_long,
                          size: 18, color: MjColors.jadeDark),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(_summary,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: MjColors.jadeDark)),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: MjColors.coral,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 28, vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
                onPressed: _start,
                child: const Text('開始對局',
                    style: TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w900)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8, top: 4),
        child: Text(t,
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: MjColors.charcoalSoft,
                letterSpacing: 1)),
      );

  Widget _presetCard(int i) {
    final p = _presets[i];
    final selected = presetIdx == i;
    return GestureDetector(
      onTap: () => _applyPreset(i),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: arcadeCard(
            color: selected ? MjColors.mint : MjColors.ivory,
            border: selected ? p.color : MjColors.outline,
            radius: 16),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: p.color.withValues(alpha: 0.15),
                shape: BoxShape.circle,
                border: Border.all(color: p.color, width: 1.4),
              ),
              child: Icon(
                  selected ? Icons.check : Icons.style_outlined,
                  color: p.color,
                  size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.name,
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: p.color)),
                  Text(p.blurb,
                      style: const TextStyle(
                          fontSize: 12, color: MjColors.charcoalSoft)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _choiceRow<T>({
    required T value,
    required List<(T, String)> options,
    required void Function(T) onPick,
  }) {
    return Row(
      children: [
        for (final (v, label) in options)
          Expanded(
            child: GestureDetector(
              onTap: () => onPick(v),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 3),
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: arcadeCard(
                    color: value == v ? MjColors.jade : MjColors.ivory,
                    border:
                        value == v ? MjColors.jadeDark : MjColors.outline,
                    radius: 14),
                child: Center(
                  child: Text(label,
                      style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: value == v
                              ? Colors.white
                              : MjColors.charcoal)),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
