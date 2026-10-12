/// Tile identity for 港式台牌 (144 tiles + optional 百搭 jokers).
///
/// Canonical string ids (stable across client/server/logs — never change):
///   W1–W9 萬  ·  T1–T9 筒  ·  S1–S9 索
///   FE FS FW FN 東南西北  ·  DC DF DB 中發白
///   X1–X4 春夏秋冬  ·  X5–X8 梅蘭菊竹
///   J0 百搭 (only present when the 百搭 room toggle is on)
library;

enum Suit { wan, tong, sok, wind, dragon, flower, joker }

class Tile {
  final Suit suit;

  /// wan/tong/sok: 1–9. wind: 1=東 2=南 3=西 4=北. dragon: 1=中 2=發 3=白.
  /// flower: 1–8 (春夏秋冬梅蘭菊竹). joker: 0.
  final int rank;

  const Tile(this.suit, this.rank);

  bool get isHonor => suit == Suit.wind || suit == Suit.dragon;
  bool get isFlower => suit == Suit.flower;
  bool get isJoker => suit == Suit.joker;
  bool get isSuited =>
      suit == Suit.wan || suit == Suit.tong || suit == Suit.sok;
  bool get isTerminal => isSuited && (rank == 1 || rank == 9);

  static const _windIds = ['FE', 'FS', 'FW', 'FN'];
  static const _dragonIds = ['DC', 'DF', 'DB'];

  String get id => switch (suit) {
        Suit.wan => 'W$rank',
        Suit.tong => 'T$rank',
        Suit.sok => 'S$rank',
        Suit.wind => _windIds[rank - 1],
        Suit.dragon => _dragonIds[rank - 1],
        Suit.flower => 'X$rank',
        Suit.joker => 'J0',
      };

  static Tile fromId(String id) {
    switch (id[0]) {
      case 'W':
        return Tile(Suit.wan, int.parse(id.substring(1)));
      case 'T':
        return Tile(Suit.tong, int.parse(id.substring(1)));
      case 'S':
        return Tile(Suit.sok, int.parse(id.substring(1)));
      case 'F':
        return Tile(Suit.wind, _windIds.indexOf(id) + 1);
      case 'D':
        return Tile(Suit.dragon, _dragonIds.indexOf(id) + 1);
      case 'X':
        return Tile(Suit.flower, int.parse(id.substring(1)));
      case 'J':
        return const Tile(Suit.joker, 0);
    }
    throw ArgumentError.value(id, 'id', 'unknown tile id');
  }

  /// The canonical unshuffled tile set, in fixed order:
  /// 4× each of W1..W9, T1..T9, S1..S9, 東南西北, 中發白 (=136),
  /// then X1..X8 once (=144), then [jokerCount] × J0 (百搭 mode: 0, 4, or 8).
  ///
  /// This exact ordering is part of the determinism contract — the shuffle
  /// golden fixtures depend on it. Do not reorder.
  static List<Tile> canonicalSet({int jokerCount = 0}) {
    assert(jokerCount == 0 || jokerCount == 4 || jokerCount == 8);
    final tiles = <Tile>[];
    for (final suit in [Suit.wan, Suit.tong, Suit.sok]) {
      for (var r = 1; r <= 9; r++) {
        for (var c = 0; c < 4; c++) {
          tiles.add(Tile(suit, r));
        }
      }
    }
    for (var r = 1; r <= 4; r++) {
      for (var c = 0; c < 4; c++) {
        tiles.add(Tile(Suit.wind, r));
      }
    }
    for (var r = 1; r <= 3; r++) {
      for (var c = 0; c < 4; c++) {
        tiles.add(Tile(Suit.dragon, r));
      }
    }
    for (var r = 1; r <= 8; r++) {
      tiles.add(Tile(Suit.flower, r));
    }
    for (var c = 0; c < jokerCount; c++) {
      tiles.add(const Tile(Suit.joker, 0));
    }
    return tiles;
  }

  @override
  bool operator ==(Object other) =>
      other is Tile && other.suit == suit && other.rank == rank;

  @override
  int get hashCode => suit.index * 16 + rank;

  @override
  String toString() => id;
}
