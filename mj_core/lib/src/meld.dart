/// Melds (面子) — 上/碰/槓 exposures and concealed sets.
library;

import 'tile.dart';

enum MeldKind {
  chow, // 上
  pung, // 碰
  concealedKong, // 暗槓
  exposedKong, // 大明槓
  addedKong, // 加槓 (碰 upgraded; the only kong that can be 搶)
}

class Meld {
  final MeldKind kind;
  final List<Tile> tiles;

  /// Seat the claimed tile came from (null for 暗槓 / 加槓 upgrades).
  final int? claimedFromSeat;

  /// Which tile in [tiles] was claimed (for UI rotation), null if none.
  final int? claimedIndex;

  const Meld(this.kind, this.tiles, {this.claimedFromSeat, this.claimedIndex});

  bool get isConcealed => kind == MeldKind.concealedKong;
  bool get isKong =>
      kind == MeldKind.concealedKong ||
      kind == MeldKind.exposedKong ||
      kind == MeldKind.addedKong;
}
