"""Deterministic wall — mirrors mj_core lib/src/rng.dart + wall.dart and
tool/gen_golden.py (the frozen determinism contract). test_engine.py
asserts parity against test/fixtures/wall_golden.json."""

M64 = (1 << 64) - 1


class SplitMix64:
    def __init__(self, seed):
        self.state = seed & M64

    def next(self):
        self.state = (self.state + 0x9E3779B97F4A7C15) & M64
        z = self.state
        z = ((z ^ (z >> 30)) * 0xBF58476D1CE4E5B9) & M64
        z = ((z ^ (z >> 27)) * 0x94D049BB133111EB) & M64
        return (z ^ (z >> 31)) & M64

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


class Wall:
    """head draws move forward; tail draws (flowers/kong replacement)
    move backward from the end."""

    def __init__(self, seed, joker_count=0):
        self.tiles = canonical_set(joker_count)
        SplitMix64(seed).shuffle(self.tiles)
        self.head = 0
        self.tail = len(self.tiles)

    @property
    def remaining(self):
        return self.tail - self.head

    def draw(self):
        t = self.tiles[self.head]
        self.head += 1
        return t

    def draw_tail(self):
        self.tail -= 1
        return self.tiles[self.tail]

    def deal_initial(self):
        hands = [[] for _ in range(4)]
        for _ in range(4):
            for seat in range(4):
                hands[seat] += self.tiles[self.head:self.head + 4]
                self.head += 4
        return hands
