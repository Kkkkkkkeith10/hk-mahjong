"""Tests for fans.py — anchored on 總例 p.11 worked examples.
Run: python3 -m pytest test_fans.py -q"""
import pytest
from tiles import id_to_kind, NUM_KINDS
from fans import Ctx, FanTable, score_win

TABLE = FanTable()


def H(s):
    counts = [0] * NUM_KINDS
    jokers = 0
    for t in s.split():
        if t == "J0":
            jokers += 1
        else:
            counts[id_to_kind(t)] += 1
    return counts, jokers


def score(hand, win="S9", method="self_draw", **kw):
    c, j = H(hand)
    ctx = Ctx(counts=c, jokers=j, win_kind=id_to_kind(win),
              win_method=method, **kw)
    return score_win(ctx, TABLE)


def ids(res):
    return {f for f, n, p in res["fans"]}


def times(res, fid):
    for f, n, p in res["fans"]:
        if f == fid:
            return n
    return 0


# ── 總例 p.11 單式結算 worked examples ──────────────────────────────────

def test_p11_ex1_one_seongfung_one_bungo():
    # 567m + 567t 567t: 一個相逢 + 一副般高 only (共用率50% blocks 2nd 相逢)
    r = score("W5 W6 W7 T5 T6 T7 T5 T6 T7 S1 S2 S3 FE FE FE DC DC",
              win="W5")
    assert times(r, "mixed_double_seq") == 1
    assert times(r, "identical_seq_pair") == 1


def test_p11_ex2_two_seongfung_double_bungo():
    # 567m 567m 567t 567t: 兩個相逢 + 雙般高, 而非四個相逢
    # (S123 run so the hand is not also a 嚦咕)
    r = score("W5 W6 W7 W5 W6 W7 T5 T6 T7 T5 T6 T7 S1 S2 S3 DC DC",
              win="W5")
    assert times(r, "mixed_double_seq") == 2
    assert times(r, "double_identical_seq") == 1
    assert times(r, "identical_seq_pair") == 0   # suppressed by 雙般高
    assert times(r, "four_same_seq") == 0        # 而非四同順


def test_p11_ex3_two_pure_dragons():
    # 123 123 456 789 789 same suit: 兩條清龍 (share 456 = 33% < 50%)
    r = score("W1 W2 W3 W1 W2 W3 W4 W5 W6 W7 W8 W9 W7 W8 W9 DC DC",
              win="W1")
    assert times(r, "closed_pure_dragon") == 2


# ── pattern families ────────────────────────────────────────────────────

def test_triple_meet_suppresses_pairs():
    r = score("W5 W6 W7 T5 T6 T7 S5 S6 S7 S1 S2 S3 FE FE FE DC DC",
              win="W5")
    assert times(r, "closed_triple_meet") == 1
    assert times(r, "mixed_double_seq") == 0


def test_open_variant_on_discard_win():
    # same hand, win by discard on S5 → the S567 run is 明 → 明三相逢
    r = score("W5 W6 W7 T5 T6 T7 S5 S6 S7 S1 S2 S3 FE FE FE DC DC",
              win="S5", method="discard")
    # 高點法 may still prefer 暗 reading only if placement allows; S5 only
    # fits the 567s run (S345 impossible: S1S2S3 used) or... S3 S4? not held.
    assert times(r, "open_triple_meet") == 1


def test_step_high_and_suppression():
    # 清一色 123 234 345 + 456? no — use 雜三步高: 123m 234t 345s
    r = score("W1 W2 W3 T2 T3 T4 S3 S4 S5 T7 T7 T7 FE FE FE DC DC",
              win="W1")
    assert times(r, "closed_mixed_3step") == 1


def test_pure_dragon_vs_step():
    r = score("W1 W2 W3 W4 W5 W6 W7 W8 W9 T1 T1 T1 S9 S9 S9 FE FE",
              win="W1")
    assert times(r, "closed_pure_dragon") == 1


def test_terminal_seq():
    r = score("W1 W2 W3 W7 W8 W9 T2 T3 T4 S5 S6 S7 DC DC DC FE FE",
              win="W1")
    assert times(r, "terminal_seq") == 1


def test_all_triplets_and_concealed_counts():
    r = score("W2 W2 W2 T5 T5 T5 S8 S8 S8 FE FE FE DC DC DC FN FN",
              win="W2", method="self_draw")
    s = ids(r)
    assert "all_concealed_triplets" in s   # 坎坎糊 absorbs 對對/門清/自摸
    assert "all_triplets" not in s
    assert "five_concealed" not in s       # suppressed (engineering fix)


def test_all_triplets_discard():
    r = score("W2 W2 W2 T5 T5 T5 S8 S8 S8 FE FE FE DC DC DC FN FN",
              win="W2", method="discard")
    s = ids(r)
    assert "all_triplets" in s
    # W2 triplet completed by discard → 明刻 → only 四暗刻
    assert "four_concealed" in s
    assert "all_concealed_triplets" not in s


def test_same_rank_triplets():
    r = score("W4 W4 W4 T4 T4 T4 S4 S4 S4 S1 S2 S3 FE FE FE DC DC",
              win="S1")
    assert times(r, "three_same_triplet") == 1
    assert times(r, "two_same_triplet") == 0


def test_dragons_and_winds():
    r = score("DC DC DC DF DF DF DB DB DB W1 W2 W3 T4 T5 T6 FE FE",
              win="W1")
    assert "big_three_dragons" in ids(r)
    r = score("DC DC DC DF DF DF W1 W2 W3 T4 T5 T6 S7 S8 S9 DB DB",
              win="W1")
    assert "small_three_dragons" in ids(r)


def test_suit_fans():
    r = score("W1 W1 W1 W2 W3 W4 W5 W6 W7 W7 W8 W9 FE FE FE W9 W9",
              win="W2")
    assert "mixed_one_suit" in ids(r)
    r = score("W1 W1 W1 W2 W3 W4 W5 W6 W7 W7 W8 W9 W5 W5 W5 W9 W9",
              win="W2")
    assert "pure_one_suit" in ids(r)
    assert "mixed_one_suit" not in ids(r)


def test_common_hand():
    r = score("W1 W2 W3 W4 W5 W6 T2 T3 T4 T6 T7 T8 S3 S4 S5 S8 S8",
              win="W1")
    assert "big_common" in ids(r)          # no honors, no flowers
    assert "common_hand" not in ids(r)


def test_four_to_x():
    # 4× W3: eye + two runs → 四歸二
    r = score("W3 W3 W1 W2 W3 W2 W3 W4 T5 T6 T7 FE FE FE DC DC DC",
              win="T5")
    assert any(f in ids(r) for f in ("closed_four_to_two",
                                     "open_four_to_two"))


def test_exposed_melds_and_mun_ching():
    c, j = H("W1 W2 W3 T5 T5 T5 DC DC")
    ctx = Ctx(counts=c, jokers=j,
              exposed=[(id_to_kind("S4"), "chow"),
                       (id_to_kind("FE"), "pung"),
                       (id_to_kind("W9"), "kong_exposed")],
              win_kind=id_to_kind("W1"), win_method="discard")
    r = score_win(ctx, TABLE)
    s = ids(r)
    assert "mun_ching" not in s
    assert times(r, "kong") == 1
    assert "honor_tiles" in s              # FE pung


def test_mun_ting_stacks_mun_mo():
    # p.11 item 13: 門叮15 + 門摸5 = 20番; 叮/門清/自摸 absorbed
    r = score("W1 W2 W3 W4 W5 W6 W7 W8 W9 T1 T1 T1 S9 S9 S9 FE FE",
              win="W1", method="self_draw", ting=True)
    s = ids(r)
    assert {"mun_ting", "mun_mo"} <= s
    assert not {"ting", "mun_ching", "self_draw"} & s


# ── special forms ───────────────────────────────────────────────────────

def test_liku_base_and_dragon():
    r = score("DC DC DF DF DB DB W1 W1 T3 T3 S5 S5 FE FE S9 S9 S9",
              win="W1")
    s = ids(r)
    assert "liku_liku" in s
    assert "dragon_liku" in s
    assert "mun_ching" not in s            # suppressed by 嚦咕


def test_liku_chain_pairs():
    r = score("W1 W1 W2 W2 W3 W3 W4 W4 W5 W5 T7 T7 S2 S2 S9 S9 S9",
              win="W1")
    assert "five_chain_pairs" in ids(r)


def test_liku_two_eat_additive():
    # 112233445566m + 77t + 999s: 7 pairs+triplet AND 123m123m456m456m
    # +S999+T7眼 — 嚦咕兩食 adds both readings
    hand = "W1 W1 W2 W2 W3 W3 W4 W4 W5 W5 W6 W6 T7 T7 S9 S9 S9"
    r = score(hand, win="W1")
    assert r["form"] == "liku_two_eat"
    assert "liku_liku" in ids(r)


def test_thirteen_orphans():
    r = score("W1 W1 W9 T1 T9 S1 S9 FE FS FW FN DC DF DB S4 S5 S6",
              win="W1")
    assert "thirteen_orphans" in ids(r)


def test_sixteen_disjoint():
    r = score("W1 W1 W4 W7 T2 T5 T8 S3 S6 S9 FE FS FW FN DC DF DB",
              win="W1")
    s = ids(r)
    assert "sixteen_disjoint" in s
    assert "disjoint_mixed_dragon" in s    # 147/258/369 across suits
    assert "small_five_types" not in s     # suppressed


# ── flowers / situational ───────────────────────────────────────────────

def test_flowers():
    r = score("W1 W2 W3 W4 W5 W6 W7 W8 W9 T1 T1 T1 S9 S9 S9 FE FE",
              win="W1", flowers=(1, 2, 3, 4, 5), seat=0)
    assert times(r, "flower_tile") == 5
    assert times(r, "seat_flower") == 2    # X1 + X5 for East
    assert times(r, "one_set_flowers") == 1


def test_no_honor_no_flower():
    r = score("W1 W2 W3 W4 W5 W6 T2 T3 T4 T6 T7 T8 S3 S4 S5 S8 S8",
              win="W1")
    s = ids(r)
    assert "no_honor_no_flower" in s
    assert not {"no_honors", "no_flowers"} & s


def test_tail_chain_formula():
    r = score("W1 W2 W3 W4 W5 W6 W7 W8 W9 T1 T1 T1 S9 S9 S9 FE FE",
              win="W1", method="self_draw", tail_chain_n=3)
    assert times(r, "tail_chain_draw") == 3
    pts = [p for f, n, p in r["fans"] if f == "tail_chain_draw"][0]
    assert pts == 20                       # 5×2² 尾牌連摸


def test_dealer_repeat_linear():
    r = score("W1 W2 W3 W4 W5 W6 W7 W8 W9 T1 T1 T1 S9 S9 S9 FE FE",
              win="W1", dealer=True, dealer_repeat_n=3)
    pts = [p for f, n, p in r["fans"] if f == "dealer_repeat"][0]
    assert pts == 6                        # 拉莊 2n


def test_wait_shapes():
    # tanki on FE (eye wait, multiple outs? FE single → outs={FE}? single)
    # use a two-out eye-ish case instead: 45m waiting 3/6 → no wait fan
    c, j = H("W3 W4 W5 T1 T1 T1 DC DC")
    ctx = Ctx(counts=c, jokers=j,
              exposed=[(id_to_kind("S1"), "chow"),
                       (id_to_kind("S4"), "chow"),
                       (id_to_kind("S7"), "chow")],
              win_kind=id_to_kind("W3"), win_method="discard")
    r = score_win(ctx, TABLE)
    s = ids(r)
    assert not {"single_wait", "false_single", "pair_eye_wait",
                "pair_call_win"} & s
    # 卡窿: 46m waiting 5 only → 獨獨 (one out)
    c2, j2 = H("W4 W6 W5 T1 T1 T1 DC DC")
    ctx2 = Ctx(counts=c2, jokers=j2,
               exposed=[(id_to_kind("S1"), "chow"),
                        (id_to_kind("S4"), "chow"),
                        (id_to_kind("S7"), "chow")],
               win_kind=id_to_kind("W5"), win_method="discard")
    r2 = score_win(ctx2, TABLE)
    assert "single_wait" in ids(r2)


def test_not_a_win():
    r = score("W1 W2 W4 W4 W5 W6 W7 W8 W9 T1 T1 T1 S9 S9 S8 FE FE",
              win="W1")
    assert r.get("error") == "not_a_win"
