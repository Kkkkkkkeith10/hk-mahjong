"""Tests for settle.py — run: python3 -m pytest test_settle.py -q"""
from settle import (Delta, LaLedger, win_deltas, midway_deltas,
                    settle_win, DEFAULT_CFG)


def pay(deltas):
    out = {}
    for d in deltas:
        out[(d.frm, d.to)] = out.get((d.frm, d.to), 0) + d.amount
    return out


def test_discard_win_plain():
    ds = win_deltas(50, winner=1, discarder=3, dealer=0, repeat_n=0)
    assert pay(ds) == {(3, 1): 50}


def test_self_draw_three_payers():
    ds = win_deltas(50, winner=1, discarder=None, dealer=0, repeat_n=0)
    assert pay(ds) == {(0, 1): 51, (2, 1): 50, (3, 1): 50}
    # dealer seat 0 pays +1番 (莊家)


def test_dealer_wins_with_repeat():
    # dealer=winner, 拉2莊: every line +1+2×2 = +5
    ds = win_deltas(30, winner=0, discarder=None, dealer=0, repeat_n=2)
    assert pay(ds) == {(1, 0): 35, (2, 0): 35, (3, 0): 35}


def test_dealer_pays_discard():
    ds = win_deltas(30, winner=2, discarder=0, dealer=0, repeat_n=1)
    assert pay(ds) == {(0, 2): 33}


def test_midway_concealed_kong_instant():
    ds = midway_deltas("concealed_kong", 2)
    assert pay(ds) == {(0, 2): 5, (1, 2): 5, (3, 2): 5}
    assert not any(d.la for d in ds)


def test_midway_flower_hu_is_la():
    ds = midway_deltas("seven_rob_one", 1, source=3)
    assert pay(ds) == {(3, 1): 30} and ds[0].la
    ds = midway_deltas("two_tai_flower", 0)
    assert pay(ds) == {(1, 0): 40, (2, 0): 40, (3, 0): 40}
    assert all(d.la for d in ds)


# ── LaLedger lifecycle ──────────────────────────────────────────────────

def test_la_record_not_paid():
    led = LaLedger()
    inst = settle_win(50, winner=0, discarder=1, dealer=2, repeat_n=0,
                      ledger=led)
    assert inst == []
    assert led.led[(0, 1)] == {"amount": 50, "kou": 1}


def test_la_compound_ceil():
    led = LaLedger()
    settle_win(5, 0, 1, dealer=2, repeat_n=0, ledger=led)
    inst = settle_win(10, 0, 1, dealer=2, repeat_n=0, ledger=led)
    assert inst == []
    # 5 × 1.5 = 7.5 → ceil 8, +10 = 18, kou 2 (拉兩口)
    assert led.led[(0, 1)] == {"amount": 18, "kou": 2}


def test_la_collect_when_creditor_wins_elsewhere():
    led = LaLedger()
    settle_win(50, 0, 1, dealer=2, repeat_n=0, ledger=led)
    inst = settle_win(20, 0, 3, dealer=2, repeat_n=0, ledger=led)
    # collects the recorded 50 from seat1; new 20 vs seat3 is recorded
    assert pay(inst) == {(1, 0): 50}
    assert (0, 1) not in led.led and led.led[(0, 3)]["amount"] == 20


def test_la_collect_when_debtor_discards_elsewhere():
    led = LaLedger()
    settle_win(50, 0, 1, dealer=2, repeat_n=0, ledger=led)
    inst = settle_win(20, 2, 1, dealer=3, repeat_n=0, ledger=led)
    # seat1 出銃 to seat2 → seat0 collects 50; new 2←1 amount recorded
    assert pay(inst) == {(1, 0): 50}
    assert led.led[(2, 1)]["amount"] == 20


def test_la_kick_half_floor():
    led = LaLedger()
    settle_win(51, 0, 1, dealer=2, repeat_n=0, ledger=led)
    inst = settle_win(30, 1, 0, dealer=2, repeat_n=0, ledger=led)
    # debtor 1 wins off creditor 0: pays 踢半 floor(51/2)=25, clears;
    # new win 1←0 recorded 30
    assert pay(inst) == {(1, 0): 25}
    assert led.led[(1, 0)]["amount"] == 30


def test_la_self_draw_resolves_all_pairs():
    led = LaLedger()
    settle_win(50, 0, 1, dealer=3, repeat_n=0, ledger=led)   # 0→1: 50
    settle_win(41, 2, 0, dealer=3, repeat_n=0, ledger=led)   # 2→0: 41
    inst = settle_win(10, 0, None, dealer=3, repeat_n=0, ledger=led)
    got = pay(inst)
    assert got[(1, 0)] == 60          # collect 50 + 自摸 10
    assert got[(0, 2)] == 20          # 踢半 floor(41/2)
    # 自摸 itself paid instantly (+1番 dealer line for seat3)
    assert got[(3, 0)] == 11 and got[(2, 0)] == 10
    assert led.led == {}


def test_zhan_la_and_match_end_wipe():
    led = LaLedger()
    for amt in (10, 10, 10):
        settle_win(amt, 0, 1, dealer=2, repeat_n=0, ledger=led)
    assert led.can_zhan(0, 1)
    d = led.zhan_la(0, 1)
    assert d.frm == 1 and d.to == 0 and d.amount == 48   # 10,25,48
    settle_win(7, 2, 3, dealer=0, repeat_n=0, ledger=led)
    wiped = led.match_end()
    assert wiped == [(2, 3, 7, 1)] and led.led == {}
