/// The wall: shuffled tile stack, initial deal, and 槓尾 (tail) draws.
library;

import 'rng.dart';
import 'tile.dart';

class Wall {
  final List<Tile> _tiles; // index 0 = first tile drawn from the head
  int _head = 0;
  int _tail; // exclusive; tail draws (補花/槓) come from the end

  Wall._(this._tiles) : _tail = _tiles.length;

  /// Build a shuffled wall from [seed]. Deterministic: seed ⇒ permutation.
  factory Wall.shuffled(int seed, {int jokerCount = 0}) {
    final tiles = Tile.canonicalSet(jokerCount: jokerCount);
    SplitMix64(seed).shuffle(tiles);
    return Wall._(tiles);
  }

  /// For tests/replay: rebuild a wall from an explicit permutation.
  factory Wall.fromIds(List<String> ids) =>
      Wall._([for (final id in ids) Tile.fromId(id)]);

  int get remaining => _tail - _head;
  bool get isExhausted => remaining <= 0; // 流局 threshold handled by engine

  /// Draw from the head (normal turn draw).
  Tile draw() {
    if (isExhausted) throw StateError('wall exhausted');
    return _tiles[_head++];
  }

  /// Draw from the tail (補花 replacement and 槓 replacement).
  Tile drawTail() {
    if (isExhausted) throw StateError('wall exhausted');
    return _tiles[--_tail];
  }

  /// Initial deal: 4 tiles × 4 rounds to each seat (dealer first),
  /// giving every player 16. The dealer's 17th tile is the first turn
  /// draw and is NOT part of the deal (see 02-GAMEPLAY-RULES.md §3).
  /// Flowers are NOT auto-replaced here — 補花 is an engine phase with
  /// its own events, in seat order, drawing from the tail.
  List<List<Tile>> dealInitial() {
    final hands = List.generate(4, (_) => <Tile>[]);
    for (var round = 0; round < 4; round++) {
      for (var seat = 0; seat < 4; seat++) {
        for (var k = 0; k < 4; k++) {
          hands[seat].add(draw());
        }
      }
    }
    return hands;
  }

  /// Full permutation (for seed disclosure / fairness audit at hand end).
  List<String> get permutationIds => [for (final t in _tiles) t.id];
}
