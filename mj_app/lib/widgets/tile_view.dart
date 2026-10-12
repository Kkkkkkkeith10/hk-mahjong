/// Placeholder tile rendering with an asset hook.
///
/// If `assets/tiles/<id>.png` exists it is used; otherwise a drawn
/// placeholder (ivory face, colored glyph) keeps the game fully playable
/// while Keith produces the real art. Tile ids follow mj_core: W1..W9,
/// T1..T9, S1..S9, FE FS FW FN, DC DF DB, J0, X1..X8, plus 'back'.
library;

import 'package:flutter/material.dart';
import 'package:mj_core/mj_core.dart';

import '../theme.dart';

const _numerals = ['一', '二', '三', '四', '五', '六', '七', '八', '九'];
const _winds = ['東', '南', '西', '北'];
const _dragons = ['中', '發', '白'];
const _flowers = ['春', '夏', '秋', '冬', '梅', '蘭', '菊', '竹'];

String kindTileId(int kind) => kind == kJoker ? 'J0' : kindToId(kind);

/// (top glyph, bottom glyph, color) for the placeholder face.
(String, String, Color) tileGlyph(String id) {
  switch (id[0]) {
    case 'W':
      return (_numerals[int.parse(id[1]) - 1], '萬', MjColors.wan);
    case 'T':
      return (_numerals[int.parse(id[1]) - 1], '筒', MjColors.tong);
    case 'S':
      return (_numerals[int.parse(id[1]) - 1], '索', MjColors.sok);
    case 'F':
      final i = ['E', 'S', 'W', 'N'].indexOf(id[1]);
      return (_winds[i], '', MjColors.honor);
    case 'D':
      final i = ['C', 'F', 'B'].indexOf(id[1]);
      final c = [MjColors.dragonRed, MjColors.dragonGreen, MjColors.charcoalSoft][i];
      return (_dragons[i], '', c);
    case 'J':
      return ('百', '搭', MjColors.joker);
    case 'X':
      return (_flowers[int.parse(id[1]) - 1], '花', MjColors.flower);
  }
  return ('?', '', MjColors.charcoal);
}

class TileView extends StatelessWidget {
  final String id; // tile id, or 'back'
  final double width;
  final bool raised;
  final bool rotated; // 叮 discard marker
  final VoidCallback? onTap;

  const TileView(this.id,
      {super.key,
      this.width = 34,
      this.raised = false,
      this.rotated = false,
      this.onTap});

  @override
  Widget build(BuildContext context) {
    final h = width * 1.38;
    // The tile PNGs carry their own face, rounded corners and drop shadow,
    // so when the asset loads we show it bare — no extra frame behind it
    // (a painted slab under the transparent margins double-frames the art).
    final face = Image.asset(
      'assets/tiles/$id.png',
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
      errorBuilder: (_, __, ___) => _drawnFallback(),
    );
    Widget tile = SizedBox(width: width, height: h, child: face);
    if (rotated) {
      tile = RotatedBox(quarterTurns: 1, child: tile);
    }
    if (raised) {
      tile = Transform.translate(offset: Offset(0, -width * 0.3), child: tile);
    }
    if (onTap != null) {
      tile = GestureDetector(onTap: onTap, behavior: HitTestBehavior.opaque, child: tile);
    }
    return tile;
  }

  /// Drawn placeholder used only if the asset for [id] is missing.
  Widget _drawnFallback() {
    if (id == 'back') {
      return Container(
        decoration: BoxDecoration(
          color: MjColors.tileBack,
          borderRadius: BorderRadius.circular(width * 0.16),
          border: Border.all(color: MjColors.feltEdge),
        ),
      );
    }
    final (top, bottom, color) = tileGlyph(id);
    return Container(
      decoration: BoxDecoration(
        color: MjColors.tileFace,
        borderRadius: BorderRadius.circular(width * 0.16),
        border: Border.all(color: MjColors.tileEdge, width: 1.1),
        boxShadow: const [
          BoxShadow(
              color: Colors.black12, blurRadius: 2, offset: Offset(0, 1.5)),
        ],
      ),
      child: FittedBox(
        fit: BoxFit.contain,
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(top,
                  style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w800,
                      height: 1.05)),
              if (bottom.isNotEmpty)
                Text(bottom,
                    style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w800,
                        height: 1.05)),
            ],
          ),
        ),
      ),
    );
  }
}
