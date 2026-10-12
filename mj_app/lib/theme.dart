/// Bright-arcade theme — colors and text styles lifted from
/// game-design-doc/reference-photos/bright-arcade-ui (see its README:
/// bright cream/ivory surfaces, jade/mint panels & felt, coral/jade/
/// brass/pale-blue accents, charcoal text, readability before decoration).
library;

import 'package:flutter/material.dart';

abstract final class MjColors {
  // surfaces
  static const cream = Color(0xFFF6EDDC); // app background
  static const ivory = Color(0xFFFBF6EA); // cards
  static const panel = Color(0xFFF1E5CE); // inset panels
  static const feltLight = Color(0xFFCBE6D2); // table felt
  static const felt = Color(0xFFB6DCC3);
  static const feltEdge = Color(0xFF8FBF9F);
  static const mint = Color(0xFFDCEFE2); // light jade panels

  // accents
  static const coral = Color(0xFFE2554A); // 食 / primary red actions
  static const coralDark = Color(0xFFC44337);
  static const jade = Color(0xFF2F8F6B); // 碰 / confirm green
  static const jadeDark = Color(0xFF237455);
  static const brass = Color(0xFFC9A24B); // 槓 / gold trims, coins
  static const brassDark = Color(0xFFA98430);
  static const paleBlue = Color(0xFF7FA8CF); // 上
  static const plum = Color(0xFFB05A8C); // 叮
  static const stone = Color(0xFF9AA79B); // 過 / disabled
  static const orange = Color(0xFFDE8A3B); // 碰 (reference action stack)
  static const teal = Color(0xFF3B9E93); // 槓 (reference action stack)

  // wooden centre hub (reference 04: brown wood square, cream inner)
  static const wood = Color(0xFF9C7A50);
  static const woodDark = Color(0xFF6F5433);
  static const woodPanel = Color(0xFFF7EBD3);

  // text & lines
  static const charcoal = Color(0xFF463D33);
  static const charcoalSoft = Color(0xFF6E6355);
  static const outline = Color(0xFFD8C9A8);

  // tiles (placeholder art)
  static const tileFace = Color(0xFFFDFAF0);
  static const tileEdge = Color(0xFFE3D7BC);
  static const tileBack = Color(0xFF6FAF8C);
  static const wan = Color(0xFFC0392B); // 萬 red
  static const tong = Color(0xFF2C5F9E); // 筒 blue
  static const sok = Color(0xFF2E7D4F); // 索 green
  static const honor = Color(0xFF463D33);
  static const dragonRed = Color(0xFFC0392B); // 中
  static const dragonGreen = Color(0xFF2E7D4F); // 發
  static const flower = Color(0xFFB05A8C);
  static const joker = Color(0xFFB8860B);
}

ThemeData mjTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: MjColors.jade,
      surface: MjColors.cream,
      primary: MjColors.jade,
      secondary: MjColors.coral,
      onSurface: MjColors.charcoal,
    ),
    scaffoldBackgroundColor: MjColors.cream,
    fontFamily: null, // system CJK font; brand font is an asset-phase item
  );
  return base.copyWith(
    appBarTheme: const AppBarTheme(
      backgroundColor: MjColors.cream,
      foregroundColor: MjColors.charcoal,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
          color: MjColors.charcoal, fontSize: 20, fontWeight: FontWeight.w700),
    ),
    cardTheme: CardThemeData(
      color: MjColors.ivory,
      elevation: 1.5,
      shadowColor: Colors.black26,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: MjColors.outline),
      ),
    ),
    dividerTheme: const DividerThemeData(color: MjColors.outline),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? Colors.white : MjColors.stone),
      trackColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected)
              ? MjColors.jade
              : MjColors.panel),
    ),
  );
}

/// The chunky rounded "arcade card" look used across the reference shots.
BoxDecoration arcadeCard(
        {Color color = MjColors.ivory,
        Color border = MjColors.outline,
        double radius = 18}) =>
    BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: border, width: 1.2),
      boxShadow: const [
        BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 3)),
      ],
    );
