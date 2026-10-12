/// 主頁 — styled after reference 01-home-landing.png, recreated in code:
/// neon seals + fanned-tile plaque banner, three pastel illustrated mode
/// cards (drawn placeholders where the reference has painted art), the
/// felt table-status panel, utility cards and the bottom nav strip.
/// 開房/入房 go online through OnlineLobbyScreen (Supabase edge function).
library;

import 'package:flutter/material.dart';

import '../model/game_controller.dart' show avatarAssets;
import '../theme.dart';
import 'fan_editor_screen.dart';
import 'online_lobby_screen.dart';
import 'rules_screen.dart';
import 'settings_screen.dart';
import 'setup_screen.dart';

/// Reference-matched pastel palette for the three mode cards.
class _CardStyle {
  final Color bg; // card background
  final Color border; // slightly darker rim
  final Color title; // big label color
  const _CardStyle(this.bg, this.border, this.title);
}

const _roomStyle =
    _CardStyle(Color(0xFFF6CDC2), Color(0xFFE5A08F), Color(0xFFD8432F));
const _joinStyle =
    _CardStyle(Color(0xFFCDE5C0), Color(0xFF9CC48A), Color(0xFF3E8E41));
const _soloStyle =
    _CardStyle(Color(0xFFBFD9F1), Color(0xFF8FB4DB), Color(0xFF3573B9));

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});


  void _toast(BuildContext context, String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
          SnackBar(content: Text(msg), duration: const Duration(seconds: 1)));
  }

  @override
  Widget build(BuildContext context) {
    // landscape phone layout: hero on the left, actions on the right,
    // utilities live in the bottom nav strip.
    return Scaffold(
      backgroundColor: MjColors.cream,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1100),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          flex: 9,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _profileStrip(),
                              const SizedBox(height: 10),
                              Expanded(child: _heroBanner()),
                            ],
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          flex: 11,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(child: _modeCards(context)),
                              const SizedBox(height: 10),
                              _tableStatusPanel(context),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            _bottomNav(context),
          ],
        ),
      ),
    );
  }

  // ── header ────────────────────────────────────────────────────────────
  Widget _profileStrip() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: arcadeCard(),
        child: Row(
          children: [
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: MjColors.brass, width: 2),
              ),
              child: CircleAvatar(
                  radius: 20,
                  backgroundColor: MjColors.panel,
                  backgroundImage: AssetImage(avatarAssets[0])),
            ),
            const SizedBox(width: 10),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('燒賣仔',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                Text('茶餐廳常客',
                    style: TextStyle(
                        fontSize: 11, color: MjColors.charcoalSoft)),
              ],
            ),
            const Spacer(),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: MjColors.mint,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: MjColors.jade, width: 1.2),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.circle, size: 9, color: MjColors.jade),
                  SizedBox(width: 6),
                  Text('單機版',
                      style: TextStyle(
                          color: MjColors.jadeDark,
                          fontSize: 12,
                          fontWeight: FontWeight.w800)),
                ],
              ),
            ),
          ],
        ),
      );

  // ── hero banner — cream plaque, fanned tiles, neon seals ──────────────
  Widget _neonSeal(String text, Color glow) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.75),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: glow, width: 2),
          boxShadow: [
            BoxShadow(
                color: glow.withValues(alpha: 0.55),
                blurRadius: 10,
                spreadRadius: 1),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final ch in text.characters)
              Text(ch,
                  style: TextStyle(
                      fontSize: 17,
                      height: 1.25,
                      fontWeight: FontWeight.w900,
                      color: glow,
                      shadows: [
                        Shadow(
                            color: glow.withValues(alpha: 0.6),
                            blurRadius: 6),
                      ])),
          ],
        ),
      );

  Widget _fannedTile(String id, double angle, double dx, double dy) =>
      Transform.translate(
        offset: Offset(dx, dy),
        child: Transform.rotate(
          angle: angle,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              boxShadow: const [
                BoxShadow(
                    color: Colors.black26,
                    blurRadius: 5,
                    offset: Offset(0, 3)),
              ],
            ),
            child: SizedBox(
                width: 58,
                height: 80,
                child:
                    Image.asset('assets/tiles/$id.png', fit: BoxFit.contain)),
          ),
        ),
      );

  Widget _heroBanner() {
    // little confetti dashes flanking the 麻雀 line, like the reference
    Widget dash(Color c, double angle) => Transform.rotate(
          angle: angle,
          child: Container(
            width: 14,
            height: 5,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
                color: c, borderRadius: BorderRadius.circular(3)),
          ),
        );
    Widget confetti({required bool flip}) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            dash(MjColors.jade, flip ? 0.5 : -0.5),
            dash(MjColors.coral, flip ? -0.3 : 0.3),
            dash(MjColors.brass, flip ? 0.4 : -0.4),
          ],
        );

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFEFF7EA), Color(0xFFFBF3DF)],
        ),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: MjColors.brass, width: 2),
        boxShadow: const [
          BoxShadow(
              color: Colors.black12, blurRadius: 8, offset: Offset(0, 4)),
        ],
      ),
      child: Row(
        children: [
          _neonSeal('發財', const Color(0xFF35B39A)),
          Expanded(
            // scale the whole plaque composition to the available height
            // (landscape phones give this column much less room)
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // fanned tiles poking over the plaque
                SizedBox(
                  height: 86,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _fannedTile('DF', -0.16, 10, 4),
                      _fannedTile('X5', 0.10, -6, 0),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                // plaque proper
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 26, vertical: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFDF6E6),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(
                        color: const Color(0xFFE0C08D), width: 4),
                    boxShadow: const [
                      BoxShadow(
                          color: Colors.black12,
                          blurRadius: 6,
                          offset: Offset(0, 3)),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('香港十六張',
                          style: TextStyle(
                              fontSize: 30,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF2F7D4F),
                              letterSpacing: 5,
                              shadows: [
                                Shadow(
                                    color: Colors.white,
                                    offset: Offset(0, 2),
                                    blurRadius: 0),
                              ])),
                      const SizedBox(height: 2),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          confetti(flip: false),
                          const SizedBox(width: 12),
                          const Text('麻 雀',
                              style: TextStyle(
                                  fontSize: 44,
                                  height: 1.05,
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFFC63B28),
                                  letterSpacing: 8,
                                  shadows: [
                                    Shadow(
                                        color: Color(0x33000000),
                                        offset: Offset(0, 3),
                                        blurRadius: 2),
                                  ])),
                          const SizedBox(width: 12),
                          confetti(flip: true),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                const Text('港式台牌 · 茶餐廳風味',
                    style: TextStyle(
                        color: MjColors.charcoalSoft, fontSize: 12)),
              ],
              ),
            ),
          ),
          _neonSeal('茶餐廳', const Color(0xFFE86A6A)),
        ],
      ),
    );
  }

  // ── mode cards (reference: pastel card, art panel, big title, arrow) ──
  Widget _modeCard(
    BuildContext context, {
    required _CardStyle style,
    required Widget art,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 5),
          padding: const EdgeInsets.fromLTRB(9, 9, 9, 10),
          decoration: BoxDecoration(
            color: style.bg,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: style.border, width: 2),
            boxShadow: const [
              BoxShadow(
                  color: Colors.black12, blurRadius: 7, offset: Offset(0, 4)),
            ],
          ),
          child: Column(
            children: [
              // art panel — placeholder illustration area; flexes with the
              // landscape height and scales its art to fit
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.8),
                        width: 1.5),
                  ),
                  padding: const EdgeInsets.all(16),
                  // SizedBox.expand forces the FittedBox to fill the panel so
                  // BoxFit.contain scales the art UP (inside Center the
                  // FittedBox shrink-wraps and never upscales)
                  child: SizedBox.expand(
                      child: FittedBox(fit: BoxFit.contain, child: art)),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontSize: 24,
                          height: 1.0,
                          fontWeight: FontWeight.w900,
                          color: style.title,
                          letterSpacing: 3,
                          shadows: const [
                            Shadow(
                                color: Colors.white,
                                offset: Offset(0, 1.5),
                                blurRadius: 0),
                          ])),
                  const SizedBox(width: 6),
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(color: style.border, width: 1.5),
                    ),
                    child: Icon(Icons.chevron_right,
                        size: 18, color: style.title),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(subtitle,
                  style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: MjColors.charcoalSoft)),
            ],
          ),
        ),
      ),
    );
  }

  // placeholder arts, drawn to sit comfortably in the white panel
  // portrait-aspect felt table so BoxFit.contain fills the tall card panel
  Widget _artMiniTable() => Container(
        width: 92,
        height: 116,
        decoration: BoxDecoration(
          color: const Color(0xFF3E8E6B),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: MjColors.woodDark, width: 4),
          boxShadow: const [
            BoxShadow(
                color: Colors.black26, blurRadius: 4, offset: Offset(0, 3)),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // wind hub
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: const Color(0xFF2B241C),
                shape: BoxShape.circle,
                border: Border.all(color: MjColors.brass, width: 1.6),
              ),
              child: const Center(
                child: Text('東',
                    style: TextStyle(
                        fontSize: 13,
                        height: 1.0,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFFE8564A))),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < 3; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 1),
                    child: SizedBox(
                        width: 17,
                        height: 24,
                        child: Image.asset('assets/tiles/back.png',
                            fit: BoxFit.contain)),
                  ),
              ],
            ),
          ],
        ),
      );

  Widget _artBigTile() => Transform.rotate(
        angle: -0.12,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            boxShadow: const [
              BoxShadow(
                  color: Colors.black26, blurRadius: 6, offset: Offset(2, 4)),
            ],
          ),
          child: SizedBox(
              width: 62,
              height: 86,
              child: Image.asset('assets/tiles/DF.png', fit: BoxFit.contain)),
        ),
      );

  Widget _artRobot() => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // antenna
          Container(
            width: 10,
            height: 10,
            decoration: const BoxDecoration(
                color: Color(0xFFF2B33D), shape: BoxShape.circle),
          ),
          Container(width: 3, height: 7, color: const Color(0xFF9AA79B)),
          // head
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: const Color(0xFFF4EBD7),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFD8C9A8), width: 2),
              boxShadow: const [
                BoxShadow(
                    color: Colors.black26,
                    blurRadius: 4,
                    offset: Offset(0, 3)),
              ],
            ),
            child: Container(
              width: 62,
              height: 42,
              decoration: BoxDecoration(
                color: const Color(0xFF23211C),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.circle, size: 11, color: Color(0xFFF2B33D)),
                    SizedBox(width: 14),
                    Icon(Icons.circle, size: 11, color: Color(0xFFF2B33D)),
                  ],
                ),
              ),
            ),
          ),
        ],
      );

  Widget _modeCards(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _modeCard(context,
              style: _roomStyle,
              art: _artMiniTable(),
              title: '開房',
              subtitle: '邀請好友開房',
              onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) =>
                          const OnlineLobbyScreen(createMode: true)))),
          _modeCard(context,
              style: _joinStyle,
              art: _artBigTile(),
              title: '入房',
              subtitle: '加入好友房間',
              onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) =>
                          const OnlineLobbyScreen(createMode: false)))),
          _modeCard(context,
              style: _soloStyle,
              art: _artRobot(),
              title: '單機',
              subtitle: '與電腦對戰',
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const SetupScreen()))),
        ],
      );

  // ── felt table-status panel (reference: dark felt, hub, live info) ────
  Widget _tableStatusPanel(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF3E8E6B),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: MjColors.woodDark, width: 3),
          image: const DecorationImage(
            image: AssetImage('assets/table/felt_jade.png'),
            fit: BoxFit.cover,
            opacity: 0.45,
          ),
          boxShadow: const [
            BoxShadow(
                color: Colors.black26, blurRadius: 7, offset: Offset(0, 4)),
          ],
        ),
        child: Row(
          children: [
            // mini hub, like the wooden dice hub in the reference art
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF2B241C),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: MjColors.brass, width: 2),
              ),
              child: const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('東',
                      style: TextStyle(
                          color: Color(0xFFE8564A),
                          fontSize: 18,
                          fontWeight: FontWeight.w900)),
                  Text('1 局',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w800)),
                ],
              ),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('開張新枱',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          shadows: [
                            Shadow(color: Colors.black38, blurRadius: 3),
                          ])),
                  SizedBox(height: 2),
                  Text('標準 8 局 · 全銃制 · 協會新章',
                      style: TextStyle(
                          fontSize: 12, color: Color(0xFFDFF0E4))),
                ],
              ),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: MjColors.coral,
                padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(
                        color: Colors.white.withValues(alpha: 0.7),
                        width: 1.5)),
              ),
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const SetupScreen())),
              child: const Text('即刻開局',
                  style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w900)),
            ),
          ],
        ),
      );

  // ── bottom nav — 首頁 active; utilities live here in landscape ───────
  Widget _bottomNav(BuildContext context) {
    Widget navItem(String label, IconData icon, bool active,
            VoidCallback onTap) =>
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: active
                        ? const BoxDecoration(
                            color: MjColors.coral, shape: BoxShape.circle)
                        : null,
                    child: Icon(icon,
                        size: 20,
                        color:
                            active ? Colors.white : MjColors.charcoalSoft),
                  ),
                  Text(label,
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight:
                              active ? FontWeight.w900 : FontWeight.w600,
                          color: active
                              ? MjColors.coralDark
                              : MjColors.charcoalSoft)),
                ],
              ),
            ),
          ),
        );
    return Container(
      decoration: const BoxDecoration(
        color: MjColors.ivory,
        border: Border(top: BorderSide(color: MjColors.outline, width: 1.2)),
      ),
      child: Row(
        children: [
          navItem('首頁', Icons.home, true, () {}),
          navItem('規則書', Icons.menu_book_outlined, false,
              () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const RulesScreen()))),
          navItem('番表管理', Icons.tune, false,
              () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const FanEditorScreen()))),
          navItem('設定', Icons.settings_outlined, false,
              () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const SettingsScreen()))),
          navItem('更多', Icons.more_horiz, false,
              () => _toast(context, '活動/商店/成就 稍後推出')),
        ],
      ),
    );
  }
}
