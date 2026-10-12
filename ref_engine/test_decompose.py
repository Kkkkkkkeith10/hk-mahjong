"""Tests for decompose.py — run with: python3 -m pytest test_decompose.py -q"""
from tiles import id_to_kind, NUM_KINDS
from decompose import (wins_standard, enumerate_standard, wins_liku,
                       wins_thirteen_orphans, wins_sixteen_disjoint,
                       win_forms, winning_kinds, shanten)

def H(*ids):
    """Build counts vector + joker count from tile ids."""
    counts = [0] * NUM_KINDS
    jokers = 0
    for tid in ids:
        for t in tid.split():
            if t == "J0":
                jokers += 1
            else:
                counts[id_to_kind(t)] += 1
    return counts, jokers


def test_standard_win_plain():
    # 123m 456m 789m 111p 999s + 東東 = 17
    c, j = H("W1 W2 W3 W4 W5 W6 W7 W8 W9 T1 T1 T1 S9 S9 S9 FE FE")
    assert wins_standard(c, j, 5)

def test_standard_not_win():
    c, j = H("W1 W2 W3 W4 W5 W6 W7 W8 W9 T1 T1 T1 S9 S9 S8 FE FE")
    assert not wins_standard(c, j, 5)

def test_standard_with_exposed_melds():
    # 2 exposed melds -> concealed needs 3 melds + eye = 11 tiles
    c, j = H("W1 W2 W3 W4 W5 W6 T5 T5 T5 DC DC")
    assert wins_standard(c, j, 3)

def test_joker_completes_run_and_eye():
    c, j = H("W1 W2 J0 W4 W5 W6 W7 W8 W9 T1 T1 T1 S9 S9 S9 FE J0")
    assert wins_standard(c, j, 5)          # joker as W3 + eye FE
    c, j = H("W1 W2 J0 W4 W5 W6 W7 W8 W9 T1 T1 T1 S9 S9 S9 FE J0")
    assert not wins_standard(c, j, 5, joker_in_eye=False)

def test_enumerate_multiple_readings():
    # 111 222 333 m can read as 3 triplets or 3 identical runs
    c, j = H("W1 W1 W1 W2 W2 W2 W3 W3 W3 T4 T5 T6 S7 S8 S9 DC DC")
    rs = enumerate_standard(c, j, 5)
    shapes = {tuple(m[1] for m in r[1]) for r in rs}
    assert (True, True, True, False, False) in shapes   # 3 triplets
    assert (False, False, False, False, False) in shapes  # all runs

def test_liku():
    # 7 pairs + triplet
    c, j = H("W1 W1 W2 W2 T3 T3 T7 T7 S5 S5 FE FE DC DC S9 S9 S9")
    assert wins_liku(c, j)
    assert "liku" in win_forms(c, j, 0)
    # 4-of-kind as two pairs
    c, j = H("W1 W1 W1 W1 T3 T3 T7 T7 S5 S5 FE FE DC DC S9 S9 S9")
    assert wins_liku(c, j)

def test_thirteen_orphans():
    # 13 orphans + extra W1 (eye) + meld 456s
    c, j = H("W1 W1 W9 T1 T9 S1 S9 FE FS FW FN DC DF DB S4 S5 S6")
    assert wins_thirteen_orphans(c, j, 0)
    assert "orphans" in win_forms(c, j, 0)
    # with one exposed meld: 14 concealed
    c, j = H("W1 W1 W9 T1 T9 S1 S9 FE FS FW FN DC DF DB")
    assert wins_thirteen_orphans(c, j, 1)

def test_sixteen_disjoint():
    # 16 unconnected + pair on W1: W1 W4 W7, T2 T5 T8, S3 S6 S9 + 7 honors
    c, j = H("W1 W1 W4 W7 T2 T5 T8 S3 S6 S9 FE FS FW FN DC DF DB")
    assert wins_sixteen_disjoint(c, j)
    # W4→W3 connects with W1? |3-1|=2 → connected → fail
    c, j = H("W1 W1 W3 W7 T2 T5 T8 S3 S6 S9 FE FS FW FN DC DF DB")
    assert not wins_sixteen_disjoint(c, j)

def test_winning_kinds_tenpai():
    # 16 tiles waiting on W3/W6 (ryanmen 45 with rest complete)
    c, j = H("W4 W5 W7 W8 W9 T1 T1 T1 S9 S9 S9 FE FE FE DC DC")
    outs = {k for k in winning_kinds(c, j, 0)}
    from tiles import kind_to_id
    ids = {kind_to_id(k) for k in outs}
    assert ids == {"W3", "W6"}

def test_shanten_values():
    # complete win shape → -1
    c, j = H("W1 W2 W3 W4 W5 W6 W7 W8 W9 T1 T1 T1 S9 S9 S9 FE FE")
    assert shanten(c, j, 0) == -1
    # tenpai → 0
    c, j = H("W4 W5 W7 W8 W9 T1 T1 T1 S9 S9 S9 FE FE FE DC DC")
    assert shanten(c, j, 0) == 0
    # 16 random-ish disconnected tiles: high shanten
    c, j = H("W1 W4 W7 T2 T5 T8 S3 S6 S9 FE FS FW FN DC DF DB")
    assert shanten(c, j, 0) >= 5

def test_shanten_with_exposed():
    # 3 exposed melds, concealed 7 tiles: 45m + 111p + DC DC → waits W3/W6
    c, j = H("W4 W5 T1 T1 T1 DC DC")
    assert shanten(c, j, 3) == 0

def test_joker_shanten():
    c, j = H("W4 W5 T1 T1 T1 DC J0")
    assert shanten(c, j, 3) <= 1
