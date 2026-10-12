"""Golden-fixture exporter — run: python3 gen_fixtures.py

Writes to ../mj_core/test/fixtures/ (consumed by the Dart port's
fixture-replay tests):

  fans_golden.json    ctx → expected fan list/total, harvested from
                      self-play wins across the option matrix plus the
                      hand-crafted cases from test_fans.py's 總例 examples
  settle_golden.json  settle_win call sequences → expected instant deltas
                      + ledger state (拉/踢半/斬拉/wipe lifecycle)
  game_golden.json    seed+options → full event log + result, replayed
                      with the deterministic L1 policy
"""
import dataclasses
import json
import os

import engine as engine_mod
from ai import L1Policy
from engine import Engine, Options
from fans import Ctx, FanTable, score_win
from settle import Delta, LaLedger, settle_win
from tiles import id_to_kind

OUT = os.path.join(os.path.dirname(__file__), "..", "mj_core", "test",
                   "fixtures")
TABLE = FanTable()


def ctx_to_json(ctx):
    d = dataclasses.asdict(ctx)
    d["counts"] = list(d["counts"])
    d["flowers"] = list(d["flowers"])
    d["exposed"] = [[k, t] for k, t in d["exposed"]]
    return d


def res_to_json(r):
    return {"total": r["total"], "form": r["form"],
            "fans": sorted([f, n, p] for f, n, p in r["fans"])}


# ── fans golden ─────────────────────────────────────────────────────────

def H(s):
    c = [0] * 34
    jk = 0
    for t in s.split():
        if t == "J0":
            jk += 1
        else:
            c[id_to_kind(t)] += 1
    return c, jk


HAND_CASES = [  # the 總例 p.11 worked examples + special forms
    ("W5 W6 W7 T5 T6 T7 S5 S6 S7 W1 W1 W1 T2 T2 T2 S8 S8",
     dict(win_kind=id_to_kind("S8"), win_method="self_draw")),
    ("W5 W6 W7 W5 W6 W7 T5 T6 T7 T5 T6 T7 S1 S2 S3 DC DC",
     dict(win_kind=id_to_kind("DC"), win_method="self_draw")),
    ("W1 W2 W3 W4 W5 W6 W7 W8 W9 W7 W8 W9 T1 T1 T1 S5 S5",
     dict(win_kind=id_to_kind("S5"), win_method="self_draw")),
    ("W1 W1 W2 W2 W3 W3 W4 W4 W5 W5 W6 W6 T7 T7 S9 S9 S9",
     dict(win_kind=id_to_kind("S9"), win_method="self_draw")),
    ("W1 W9 T1 T9 S1 S9 FE FS FW FN DC DF DB W1 T2 T3 T4",
     dict(win_kind=id_to_kind("W1"), win_method="self_draw")),
]


def gen_fans(n_games=400):
    cases = []
    for hand, kw in HAND_CASES:
        c, jk = H(hand)
        ctx = Ctx(counts=c, jokers=jk, **kw)
        r = score_win(ctx, TABLE)
        assert "error" not in r, (hand, r)
        cases.append({"ctx": ctx_to_json(ctx), "expect": res_to_json(r)})

    # harvest self-play wins (ctx captured at the engine's score call)
    real = engine_mod.score_win
    captured = []

    def recorder(ctx, table):
        r = real(ctx, table)
        if "error" not in r:
            captured.append({"ctx": ctx_to_json(ctx),
                             "expect": res_to_json(r)})
        return r

    engine_mod.score_win = recorder
    try:
        i = 0
        while i < n_games:
            for jokers in (0, 4, 8):
                for swap in ("off", "fixed3", "dice"):
                    eng = Engine(2000 + i, Options(jokers=jokers,
                                                   swap=swap),
                                 dealer=i % 4, table=TABLE,
                                 ledger=LaLedger())
                    eng.play([L1Policy() for _ in range(4)])
                    i += 1
                    if i >= n_games:
                        break
                if i >= n_games:
                    break
    finally:
        engine_mod.score_win = real
    cases += captured
    return {"contract": "fans/v1", "cases": cases}


# ── settle golden ───────────────────────────────────────────────────────

SETTLE_SCRIPTS = [
    # (name, [call dicts]) — mirror of test_settle.py lifecycles
    ("discard_plain", [dict(fan=50, w=1, d=3, dealer=0, rep=0)]),
    ("self_draw", [dict(fan=50, w=1, d=None, dealer=0, rep=0)]),
    ("dealer_repeat", [dict(fan=30, w=0, d=None, dealer=0, rep=2)]),
    ("la_compound", [dict(fan=5, w=0, d=1, dealer=2, rep=0),
                     dict(fan=10, w=0, d=1, dealer=2, rep=0)]),
    ("la_collect", [dict(fan=50, w=0, d=1, dealer=2, rep=0),
                    dict(fan=20, w=0, d=3, dealer=2, rep=0)]),
    ("la_kick_half", [dict(fan=51, w=0, d=1, dealer=2, rep=0),
                      dict(fan=30, w=1, d=0, dealer=2, rep=0)]),
    ("la_self_draw_resolves", [dict(fan=50, w=0, d=1, dealer=3, rep=0),
                               dict(fan=41, w=2, d=0, dealer=3, rep=0),
                               dict(fan=10, w=0, d=None, dealer=3,
                                    rep=0)]),
    ("zhan_and_wipe", [dict(fan=10, w=0, d=1, dealer=2, rep=0),
                       dict(fan=10, w=0, d=1, dealer=2, rep=0),
                       dict(fan=10, w=0, d=1, dealer=2, rep=0),
                       dict(zhan=[0, 1]),
                       dict(fan=7, w=2, d=3, dealer=0, rep=0),
                       dict(wipe=True)]),
]


def gen_settle():
    cases = []
    for name, script in SETTLE_SCRIPTS:
        led = LaLedger()
        steps = []
        for call in script:
            if "zhan" in call:
                d = led.zhan_la(*call["zhan"])
                steps.append({"call": call,
                              "instant": [dataclasses.asdict(d)]})
            elif "wipe" in call:
                steps.append({"call": call, "wiped": led.match_end()})
            else:
                inst = settle_win(call["fan"], call["w"], call["d"],
                                  call["dealer"], call["rep"], led)
                steps.append({"call": call,
                              "instant": [dataclasses.asdict(x)
                                          for x in inst]})
            steps[-1]["ledger"] = {f"{c},{d_}": rec for (c, d_), rec
                                   in sorted(led.led.items())}
        cases.append({"name": name, "steps": steps})
    return {"contract": "settle/v1", "cases": cases}


# ── game golden ─────────────────────────────────────────────────────────

def delta_json(d):
    return dataclasses.asdict(d)


def gen_games(n=24):
    cases = []
    i = 0
    while i < n:
        for jokers in (0, 4, 8):
            for swap in ("off", "fixed3", "dice"):
                seed = 5000 + i
                led = LaLedger()
                eng = Engine(seed, Options(jokers=jokers, swap=swap),
                             dealer=i % 4, repeat_n=i % 3, table=TABLE,
                             ledger=led)
                res = eng.play([L1Policy() for _ in range(4)])
                out = {"kind": res["kind"],
                       "deltas": [delta_json(d) for d in eng.deltas],
                       "ledger": {f"{c},{d_}": rec for (c, d_), rec
                                  in sorted(led.led.items())},
                       "dealer_repeats": res["dealer_repeats"]}
                if res["kind"] == "win":
                    out["winners"] = [[w, res_to_json(r)]
                                      for w, r in res["winners"]]
                    out["discarder"] = res["discarder"]
                cases.append({"seed": seed, "jokers": jokers,
                              "swap": swap, "dealer": i % 4,
                              "repeat_n": i % 3, "events": eng.events,
                              "result": out})
                i += 1
                if i >= n:
                    break
            if i >= n:
                break
    return {"contract": "game/l1policy/v1", "cases": cases}


def main():
    os.makedirs(OUT, exist_ok=True)
    fans = gen_fans()
    settle = gen_settle()
    games = gen_games()
    for name, data in [("fans_golden.json", fans),
                       ("settle_golden.json", settle),
                       ("game_golden.json", games)]:
        path = os.path.join(OUT, name)
        with open(path, "w") as f:
            json.dump(data, f, separators=(",", ":"))
        print(name, len(data["cases"]), "cases,",
              os.path.getsize(path) // 1024, "KB")


if __name__ == "__main__":
    main()
