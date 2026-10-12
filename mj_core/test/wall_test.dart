import 'dart:convert';
import 'dart:io';

import 'package:mj_core/mj_core.dart';
import 'package:test/test.dart';

void main() {
  group('canonical tile set', () {
    test('144 tiles, correct multiplicities', () {
      final tiles = Tile.canonicalSet();
      expect(tiles.length, 144);
      final counts = <String, int>{};
      for (final t in tiles) {
        counts[t.id] = (counts[t.id] ?? 0) + 1;
      }
      expect(counts.length, 42); // 27 suited + 7 honors + 8 flowers
      for (final e in counts.entries) {
        expect(e.value, e.key.startsWith('X') ? 1 : 4,
            reason: 'multiplicity of ${e.key}');
      }
    });

    test('joker variants', () {
      expect(Tile.canonicalSet(jokerCount: 4).length, 148);
      expect(Tile.canonicalSet(jokerCount: 8).length, 152);
    });

    test('id round-trip', () {
      for (final t in Tile.canonicalSet(jokerCount: 4)) {
        expect(Tile.fromId(t.id), t);
      }
    });
  });

  group('determinism contract (golden fixtures)', () {
    late Map<String, dynamic> golden;

    setUpAll(() {
      golden = jsonDecode(
              File('test/fixtures/wall_golden.json').readAsStringSync())
          as Map<String, dynamic>;
      expect(golden['contract'], 'splitmix64/fisher-yates/v1');
    });

    test('raw RNG matches reference (seed 42, first 5 values)', () {
      // Unsigned 64-bit hex: toRadixString on a negative VM int prints a
      // signed value, so format the two 32-bit halves separately.
      String hex64(int v) =>
          (v >>> 32).toRadixString(16).padLeft(8, '0') +
          (v & 0xFFFFFFFF).toRadixString(16).padLeft(8, '0');
      final check = golden['rngCheck'] as Map<String, dynamic>;
      final rng = SplitMix64(check['seed'] as int);
      for (final hex in (check['next5_hex'] as List).cast<String>()) {
        expect(hex64(rng.next()), hex);
      }
    });

    test('wall permutation + deal match reference for every fixture', () {
      for (final fx in (golden['fixtures'] as List)) {
        final f = fx as Map<String, dynamic>;
        final wall = Wall.shuffled(f['seed'] as int,
            jokerCount: f['jokerCount'] as int);
        expect(wall.permutationIds, (f['permutation'] as List).cast<String>(),
            reason: 'seed=${f['seed']} jokers=${f['jokerCount']}');
        final hands = wall.dealInitial();
        final expected = (f['hands'] as List)
            .map((h) => (h as List).cast<String>())
            .toList();
        for (var seat = 0; seat < 4; seat++) {
          expect([for (final t in hands[seat]) t.id], expected[seat],
              reason: 'seat $seat');
        }
        expect((f['tileCount'] as int) - wall.remaining,
            f['headAfterDeal'] as int);
      }
    });

    test('same seed twice ⇒ identical, different seed ⇒ different', () {
      expect(Wall.shuffled(7).permutationIds, Wall.shuffled(7).permutationIds);
      expect(Wall.shuffled(7).permutationIds,
          isNot(Wall.shuffled(8).permutationIds));
    });
  });

  group('wall mechanics', () {
    test('deal gives 4×16 and head/tail draws never collide', () {
      final wall = Wall.shuffled(99);
      final hands = wall.dealInitial();
      expect(hands.every((h) => h.length == 16), isTrue);
      expect(wall.remaining, 144 - 64);
      final seen = <Tile>[...hands.expand((h) => h)];
      seen.add(wall.draw());
      seen.add(wall.drawTail());
      while (!wall.isExhausted) {
        seen.add(wall.draw());
      }
      expect(seen.length, 144);
      expect(() => wall.draw(), throwsStateError);
      expect(() => wall.drawTail(), throwsStateError);
    });
  });
}
