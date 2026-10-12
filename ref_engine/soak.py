"""Self-play soak — run: python3 soak.py [n_games]

Plays full 局 with 4 L1 bots across the room-option matrix and checks
invariants on every game:
  * terminates with a legal result kind
  * money is zero-sum and every Delta is non-negative
  * per-player tile conservation: hand + 3×melds ∈ {16, 17}
  * score_win never errors on a claimed win (asserted inside the engine)
  * la ledger only ever holds positive amounts
"""
import sys
import time
from collections import Counter

from ai import L1Policy
from engine import Engine, Options
from fans import FanTable
from settle import LaLedger

TABLE = FanTable()


def run_game(seed, jokers=0, swap="off"):
    led = LaLedger()
    eng = Engine(seed, Options(jokers=jokers, swap=swap),
                 dealer=seed % 4, repeat_n=seed % 3, table=TABLE,
                 ledger=led)
    res = eng.play([L1Policy() for _ in range(4)])

    assert res["kind"] in ("win", "exhaust", "flower_hu"), res
    net = [0, 0, 0, 0]
    for d in eng.deltas:
        assert d.amount >= 0, d
        net[d.frm] -= d.amount
        net[d.to] += d.amount
    assert sum(net) == 0
    for (c, dbt), rec in led.led.items():
        assert rec["amount"] > 0 and rec["kou"] >= 1 and c != dbt
    for p in eng.players:
        assert p.hand_size() + 3 * len(p.melds) in (16, 17), \
            (p.hand_size(), p.melds)
    return res


def main(n=1000):
    kinds = Counter()
    t0 = time.time()
    i = 0
    while i < n:
        for jokers in (0, 4, 8):
            for swap in ("off", "fixed3", "dice"):
                res = run_game(1000 + i, jokers, swap)
                kinds[res["kind"]] += 1
                i += 1
                if i >= n:
                    break
            if i >= n:
                break
    dt = time.time() - t0
    print(f"{n} games in {dt:.1f}s ({n / dt:.0f}/s) — {dict(kinds)}")


if __name__ == "__main__":
    main(int(sys.argv[1]) if len(sys.argv) > 1 else 1000)
