"""Tests for engine.py + wall.py — run: python3 -m pytest test_engine.py -q

Wall parity is asserted against the frozen determinism contract in
mj_core/test/fixtures/wall_golden.json. Game-flow tests rig the wall
directly (the engine never validates tile multiplicity, so rigged walls
may repeat tiles freely).
"""
import json
import os

from engine import Engine, Options, Policy, is_flower
from settle import LaLedger
from tiles import id_to_kind, JOKER
from wall import Wall, SplitMix64
from fans import FanTable

FIX = os.path.join(os.path.dirname(__file__), "..", "mj_core", "test",
                   "fixtures", "wall_golden.json")
TABLE = FanTable()

K = id_to_kind   # "S5" -> kind int


# ── wall determinism parity ─────────────────────────────────────────────

def test_rng_golden():
    g = json.load(open(FIX))
    r = SplitMix64(g["rngCheck"]["seed"])
    got = [format(r.next(), "016x") for _ in range(5)]
    assert got == g["rngCheck"]["next5_hex"]


def test_wall_golden_parity():
    g = json.load(open(FIX))
    for fx in g["fixtures"]:
        w = Wall(fx["seed"], fx["jokerCount"])
        assert len(w.tiles) == fx["tileCount"]
        assert w.tiles == fx["permutation"], fx["seed"]


# ── rigging helpers ─────────────────────────────────────────────────────

# W1+W2 are connected, so this can never be 十六不搭; nowhere near a
# standard win either.
JUNK = ["W1", "W2", "W4", "W7", "T2", "T5", "T8", "S3", "S6", "S9",
        "FE", "FS", "FW", "FN", "DC", "DF"]


def waiter(eye="S5"):
    """16 tiles waiting solely on `eye` (single-tile eye wait)."""
    return (["W1"] * 3 + ["W2", "W3", "W4"] + ["W5", "W6", "W7"]
            + ["W8"] * 3 + ["S1"] * 3 + [eye])


def rig(hands, draws=(), tail=(), opts=None, dealer=0, ledger=None):
    eng = Engine(1, opts or Options(), dealer=dealer, table=TABLE,
                 ledger=ledger)
    tiles = []
    for r in range(4):
        for s in range(4):
            tiles += hands[s][4 * r:4 * (r + 1)]
    tiles += list(draws)
    tiles += list(tail)[::-1]     # first tail draw pops the last element
    eng.wall.tiles = tiles
    eng.wall.head = 0
    eng.wall.tail = len(tiles)
    return eng


class SP(Policy):
    """Scripted policy: queues for each decision, safe fallbacks."""

    def __init__(self, discards=(), wins=None, ting=(), kongs=(),
                 claims=(), chows=()):
        self.discards = list(discards)
        self.wins = list(wins) if wins is not None else None
        self.tings = list(ting)
        self.kongs = list(kongs)
        self.claims = list(claims)
        self.chows = list(chows)
        self.win_calls = 0

    def choose_swap(self, view, n):
        out, c = [], view["counts"].copy()
        for k in range(len(c)):
            while c[k] and len(out) < n:
                c[k] -= 1
                out.append(k)
        return out

    def choose_discard(self, view):
        if self.discards:
            return self.discards.pop(0)
        for k, n in enumerate(view["counts"]):
            if n:
                return k
        raise AssertionError("nothing to discard")

    def want_win(self, view):
        self.win_calls += 1
        if self.wins:
            return self.wins.pop(0)
        return True if self.wins is None else True

    def want_ting(self, view):
        return self.tings.pop(0) if self.tings else None

    def want_kong(self, view, options):
        if self.kongs and self.kongs[0] in options:
            return self.kongs.pop(0)
        return None

    def want_claim(self, view, kind, options):
        if self.claims and self.claims[0] in options:
            return self.claims.pop(0)
        return None

    def want_chow(self, view, kind, low_options):
        if self.chows and self.chows[0] in low_options:
            return self.chows.pop(0)
        return None


def pay(deltas):
    out = {}
    for d in deltas:
        out[(d.frm, d.to)] = out.get((d.frm, d.to), 0) + d.amount
    return out


def hand_invariant(eng):
    for p in eng.players:
        assert p.hand_size() + 3 * len(p.melds) in (16, 17)


# ── game flow ───────────────────────────────────────────────────────────

def test_discard_win():
    eng = rig([JUNK, waiter("S5"), JUNK, JUNK], draws=["S5"])
    pol = [SP(discards=[K("S5")]), SP(), SP(), SP()]
    res = eng.play(pol)
    assert res["kind"] == "win" and res["discarder"] == 0
    (w, r), = res["winners"]
    assert w == 1 and r["total"] > 0
    # 全銃制 + dealer in the pair ⇒ total + 1番
    assert pay(res["deltas"]) == {(0, 1): r["total"] + 1}


def test_self_draw_dealer_heaven():
    eng = rig([waiter("S5"), JUNK, JUNK, JUNK], draws=["S5"])
    res = eng.play([SP(), SP(), SP(), SP()])
    assert res["kind"] == "win" and res["discarder"] is None
    (w, r), = res["winners"]
    assert w == 0 and r["total"] >= 120          # 天糊 fires
    got = pay(res["deltas"])
    assert set(got) == {(1, 0), (2, 0), (3, 0)}
    assert all(v == r["total"] + 1 for v in got.values())   # dealer pair


def test_pung_then_turn_order():
    hands = [JUNK, JUNK, ["T5", "T5"] + JUNK[:14], JUNK]
    eng = rig(hands, draws=["DB", "W2"])
    pol = [SP(discards=[K("T5")]), SP(), SP(claims=["pung"]), SP()]
    res = eng.play(pol)
    assert res["kind"] == "exhaust"
    ev = eng.events
    i = next(j for j, e in enumerate(ev) if e["type"] == "claim")
    assert ev[i] == {"type": "claim", "seat": 2, "kind": K("T5"),
                     "what": "pung"}
    # claimer discards, then the draw goes to seat 3 (claimer's 下家)
    nxt = next(e for e in ev[i + 1:] if e["type"] == "draw")
    assert nxt["seat"] == 3
    hand_invariant(eng)


def test_guo_shui_blocks_until_own_draw():
    # seat2 waits on S5; declines the first one ⇒ 過水 until own draw
    eng = rig([JUNK, JUNK, waiter("S5"), JUNK],
              draws=["S5",         # dealer draws & discards S5 (declined)
                     "S5",         # seat1 draws & discards S5 (blocked!)
                     "DB",         # seat2 draws junk (block clears)
                     "S5"])        # seat3 draws & discards S5 → win
    pol = [SP(discards=[K("S5")]), SP(discards=[K("S5")]),
           SP(discards=[K("DB")], wins=[False, True]),
           SP(discards=[K("S5")])]
    res = eng.play(pol)
    assert res["kind"] == "win" and res["discarder"] == 3
    assert res["winners"][0][0] == 2
    passes = [e for e in eng.events if e["type"] == "pass_win"]
    assert len(passes) == 1 and passes[0]["seat"] == 2
    assert pol[2].win_calls == 2   # never consulted while blocked


def test_double_win_and_settle_order():
    eng = rig([JUNK, waiter("S5"), JUNK, waiter("S5")], draws=["S5"])
    pol = [SP(discards=[K("S5")]), SP(), SP(), SP()]
    res = eng.play(pol)
    assert res["kind"] == "win"
    winners = [w for w, _ in res["winners"]]
    assert sorted(winners) == [1, 3]
    got = pay(res["deltas"])
    assert set(got) == {(0, 1), (0, 3)}


def test_concealed_kong_reward_and_replacement():
    hands = [["DF"] * 4 + JUNK[:12], JUNK, JUNK, JUNK]
    eng = rig(hands, draws=["DB"], tail=["W9"])
    pol = [SP(kongs=[(K("DF"), "concealed")]), SP(), SP(), SP()]
    res = eng.play(pol)
    assert res["kind"] == "exhaust"
    assert pay(res["deltas"]) == {(1, 0): 5, (2, 0): 5, (3, 0): 5}
    assert (K("DF"), "kong_concealed") in eng.players[0].melds
    hand_invariant(eng)


def test_rob_kong():
    hands = [JUNK,                          # dealer, discards T5
             ["T5", "T5"] + JUNK[:14],      # pungs, later adds 4th
             JUNK,
             waiter("T5")]                  # robs the 加槓
    eng = rig(hands, draws=["DB",   # d1 dealer
                            "W2",   # d2 seat2
                            "DB",   # d3 seat3 (clears its 過水)
                            "W2",   # d4 seat0
                            "T5"])  # d5 seat1 → 加槓 → rob
    pol = [SP(discards=[K("T5")]),
           SP(claims=["pung"], kongs=[(K("T5"), "added")]),
           SP(),
           SP(discards=[K("DB")], wins=[False, True])]
    res = eng.play(pol)
    assert res["kind"] == "win" and res["discarder"] == 1
    (w, r), = res["winners"]
    assert w == 3
    assert eng.win_method[3] == "rob_kong"
    assert any(f == "rob_kong" for f, n, p_ in r["fans"])   # 搶槓 10


def test_ting_heaven_rotation_and_autowin():
    eng = rig([waiter("S5") , JUNK, JUNK, JUNK],
              draws=["DB",                      # dealer 17th → 天叮
                     "W2", "W2", "W2",          # seats 1-3
                     "S5"])                     # dealer rotates→ wins自摸
    pol = [SP(ting=[K("DB")]), SP(), SP(), SP()]
    res = eng.play(pol)
    tings = [e for e in eng.events if e["type"] == "ting"]
    assert tings == [{"type": "ting", "seat": 0, "cls": "heaven"}]
    assert res["kind"] == "win" and res["discarder"] is None
    (w, r), = res["winners"]
    assert w == 0
    ids = {f for f, n, p_ in r["fans"]}
    assert "heaven_ting" in ids


def test_ting_rotated_discards():
    # non-dealer ting; drawn tiles are rotated out automatically
    eng = rig([JUNK, waiter("S5"), JUNK, JUNK],
              draws=["W2", "DB",               # dealer, seat1 (叮 with DB)
                     "W2", "W2", "W2",         # seats 2,3,0
                     "T2"])                    # seat1 draws junk → rotate
    pol = [SP(), SP(ting=[K("DB")]), SP(), SP()]
    res = eng.play(pol)
    assert res["kind"] == "exhaust"
    tings = [e for e in eng.events if e["type"] == "ting"]
    assert tings == [{"type": "ting", "seat": 1, "cls": "earth"}]
    rot = [e for e in eng.events
           if e["type"] == "discard" and e.get("rotated")]
    assert rot == [{"type": "discard", "seat": 1, "kind": K("T2"),
                    "rotated": True}]


def test_flower_replacement_at_deal():
    hands = [JUNK, JUNK[:15] + ["X3"], JUNK, JUNK]
    eng = rig(hands, draws=[], tail=["S9"])
    res = eng.play([SP(), SP(), SP(), SP()])
    assert res["kind"] == "exhaust"
    assert eng.players[1].flowers == [3]
    assert eng.players[1].hand_size() == 16


def test_eight_flowers_la_to_ledger():
    led = LaLedger()
    hands = [[f"X{i}" for i in range(1, 9)] + JUNK[:8], JUNK, JUNK, JUNK]
    eng = rig(hands, tail=["W2"] * 8, ledger=led)
    res = eng.play([SP(), SP(), SP(), SP()])
    assert res["kind"] == "flower_hu" and res["seat"] == 0
    assert res["dealer_repeats"]
    # 兩台花 rewards are 拉'd, not paid (flowerWinLa)
    assert res["deltas"] == []
    assert {k: v["amount"] for k, v in led.led.items()} == \
        {(0, 1): 40, (0, 2): 40, (0, 3): 40}


def test_swap_fixed3():
    eng = rig([JUNK, JUNK, JUNK, JUNK], draws=["W2"],
              opts=Options(swap="fixed3"))
    res = eng.play([SP(), SP(), SP(), SP()])
    assert res["kind"] == "exhaust"
    swaps = [e for e in eng.events if e["type"] == "swap"]
    assert len(swaps) == 1 and all(len(g) == 3 for g in swaps[0]["gives"])
    for p in eng.players:
        assert p.hand_size() == 16 or p is eng.players[0]
    hand_invariant(eng)


def test_chow_next_player_only():
    hands = [JUNK, ["W2", "W3"] + JUNK[:14], JUNK, JUNK]
    eng = rig(hands, draws=["W1", "T2"])
    pol = [SP(discards=[K("W1")]), SP(chows=[K("W1")]), SP(), SP()]
    res = eng.play(pol)
    assert res["kind"] == "exhaust"
    claims = [e for e in eng.events if e["type"] == "claim"]
    assert claims and claims[0] == {"type": "claim", "seat": 1,
                                    "kind": K("W1"), "what": "chow"}
    assert (K("W1"), "chow") in eng.players[1].melds
    hand_invariant(eng)


def test_exhaust_dealer_repeats():
    eng = rig([JUNK, JUNK, JUNK, JUNK], draws=["W2", "W2"])
    res = eng.play([SP(), SP(), SP(), SP()])
    assert res["kind"] == "exhaust" and res["dealer_repeats"]
