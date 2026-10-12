#!/usr/bin/env python3
"""Reference implementation of mj_core's determinism contract.

Generates test/fixtures/wall_golden.json. The Dart tests assert bit-for-bit
equality against these fixtures, proving lib/src/rng.dart + tile.dart +
wall.dart match this reference exactly.

Contract (mirrors lib/src/rng.dart — keep in sync):
  SplitMix64, 64-bit wrapping; nextBounded(n) = (next() & 0x7FF..F) % n;
  Fisher-Yates top-down; canonical tile order per Tile.canonicalSet.
"""
import json, os

M = (1 << 64) - 1

class SplitMix64:
    def __init__(self, seed): self.state = seed & M
    def next(self):
        self.state = (self.state + 0x9E3779B97F4A7C15) & M
        z = self.state
        z = ((z ^ (z >> 30)) * 0xBF58476D1CE4E5B9) & M
        z = ((z ^ (z >> 27)) * 0x94D049BB133111EB) & M
        return (z ^ (z >> 31)) & M
    def next_bounded(self, n):
        return (self.next() & 0x7FFFFFFFFFFFFFFF) % n
    def shuffle(self, xs):
        for i in range(len(xs) - 1, 0, -1):
            j = self.next_bounded(i + 1)
            xs[i], xs[j] = xs[j], xs[i]

def canonical_set(joker_count=0):
    tiles = []
    for s in "WTS":
        for r in range(1, 10):
            tiles += [f"{s}{r}"] * 4
    for w in ["FE", "FS", "FW", "FN"]:
        tiles += [w] * 4
    for d in ["DC", "DF", "DB"]:
        tiles += [d] * 4
    tiles += [f"X{r}" for r in range(1, 9)]
    tiles += ["J0"] * joker_count
    return tiles

def deal_initial(perm):
    hands, head = [[] for _ in range(4)], 0
    for _ in range(4):
        for seat in range(4):
            hands[seat] += perm[head:head + 4]
            head += 4
    return hands, head

def main():
    fixtures = []
    for seed, jokers in [(42, 0), (42, 4), (20260707, 0), (1, 8)]:
        tiles = canonical_set(jokers)
        SplitMix64(seed).shuffle(tiles)
        hands, head = deal_initial(tiles)
        fixtures.append({
            "seed": seed, "jokerCount": jokers, "tileCount": len(tiles),
            "permutation": tiles, "hands": hands, "headAfterDeal": head,
        })
    # raw RNG check values so a shuffle-level bug is distinguishable from an RNG bug
    r = SplitMix64(42)
    rng_check = [r.next() & M for _ in range(5)]
    out = {
        "contract": "splitmix64/fisher-yates/v1",
        "rngCheck": {"seed": 42, "next5_hex": [f"{v:016x}" for v in rng_check]},
        "fixtures": fixtures,
    }
    path = os.path.join(os.path.dirname(__file__), "..", "test", "fixtures", "wall_golden.json")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        json.dump(out, f, indent=1)
    print(f"wrote {path}: {len(fixtures)} fixtures")
    for fx in fixtures:
        print(f"  seed={fx['seed']} jokers={fx['jokerCount']} n={fx['tileCount']} first8={fx['permutation'][:8]}")

if __name__ == "__main__":
    main()
