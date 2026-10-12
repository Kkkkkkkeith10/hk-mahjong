"""Fast soak slice for CI — full 1000-game run lives in soak.py."""
from soak import run_game


def test_soak_matrix():
    i = 0
    for jokers in (0, 4, 8):
        for swap in ("off", "fixed3", "dice"):
            for s in range(4):
                res = run_game(7000 + i, jokers, swap)
                assert res["kind"] in ("win", "exhaust", "flower_hu")
                i += 1
