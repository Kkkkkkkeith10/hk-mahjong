/// 設定 — bot pacing (電腦出牌速度) and sound toggle. Values persist via
/// AppSettings (shared_preferences). The sound pack itself is a later
/// asset-phase item; the toggle is wired now so the preference carries over.
library;

import 'package:flutter/material.dart';

import '../model/app_settings.dart';
import '../theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final s = AppSettings.instance;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('設定')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _label('電腦出牌速度'),
          Row(
            children: [
              for (final (ms, name) in const [
                (300, '快'),
                (550, '中'),
                (900, '慢'),
              ])
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      s.setBotDelayMs(ms);
                      setState(() {});
                    },
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: arcadeCard(
                          color: s.botDelayMs == ms
                              ? MjColors.jade
                              : MjColors.ivory,
                          border: s.botDelayMs == ms
                              ? MjColors.jadeDark
                              : MjColors.outline,
                          radius: 14),
                      child: Center(
                        child: Text(name,
                            style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: s.botDelayMs == ms
                                    ? Colors.white
                                    : MjColors.charcoal)),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 18),
          _label('音效'),
          Container(
            decoration: arcadeCard(),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('遊戲音效', style: TextStyle(fontSize: 14)),
              subtitle: const Text('音效包稍後更新加入',
                  style: TextStyle(
                      fontSize: 12, color: MjColors.charcoalSoft)),
              value: s.soundOn,
              onChanged: (v) {
                s.setSoundOn(v);
                setState(() {});
              },
            ),
          ),
          const SizedBox(height: 18),
          _label('關於'),
          Container(
            decoration: arcadeCard(),
            padding: const EdgeInsets.all(14),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('香港十六張麻雀',
                    style:
                        TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
                SizedBox(height: 4),
                Text('版本 1.0.0',
                    style: TextStyle(
                        fontSize: 12, color: MjColors.charcoalSoft)),
                SizedBox(height: 8),
                Text(
                  '規則依照香港麻雀協會《港式台牌總例》（2025-07-28 修訂版）。'
                  '單機版所有數據只儲存喺你部機入面。',
                  style: TextStyle(fontSize: 12.5, height: 1.6),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8, top: 4),
        child: Text(t,
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: MjColors.charcoalSoft,
                letterSpacing: 1)),
      );
}
