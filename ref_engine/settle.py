"""Settlement + 拉/踢半 ledger — Python reference for mj_core M2.

Money model (03-SCORING-SETTLEMENT.md + fan_table.json settlement block):
  * 全銃制: 出銃 pays the winner's full total; 自摸 = each of the other
    three pays the full total.
  * 1番 = 1分 for win totals; 底 (=5分) is the unit for 中途獎勵.
  * 莊家 adjustment is PER PAIR: any payment line involving the dealer
    gains (dealerBonusFan + laZhuangFanPerN × repeatN) 番. The engine must
    therefore NOT set ctx.dealer/dealer_repeat_n on the recognizer — the
    fan-table `dealer`/`dealer_repeat` entries are display aliases of this
    same adjustment, never double-counted.
  * 拉 ledger (toggle ON): 出銃 amounts are recorded, not paid. Compounds
    ×1.5 (ceil) when the same creditor wins off the same debtor again;
    debtor escaping (win off creditor / 自摸) pays half, floor (踢半);
    creditor winning elsewhere / debtor 出銃 elsewhere ⇒ collect in full.
  * 斬拉 (kou ≥ 3, debtor's option between 局): settle full, clear.
  * Match end: unresolved ledgers are WIPED (Keith 2026-07-07).
  * 花糊 (七搶一/兩台花) 該得點拉落下一鋪 when flowerWinLa; 暗槓 reward is
    instant.
"""
import math
from dataclasses import dataclass


@dataclass(frozen=True)
class Delta:
    frm: int          # seat paying
    to: int           # seat receiving
    amount: int       # 分
    reason: str
    la: bool = False  # True = record to LaLedger instead of paying


DEFAULT_CFG = {
    "selfDrawMultiplier": 3, "cap": None, "diBase": 5,
    "dealerBonusFan": 1, "laZhuangFanPerN": 2,
    "laLedger": {"compound": 1.5, "roundUpOnWin": True,
                 "kickHalfRoundDown": True, "matchEndPolicy": "wipe"},
    "flowerWinLa": True,
    "midwayRewards": {"concealedKongDiPerPlayer": 1, "sevenRobOneDi": 6,
                      "twoTaiFlowerDiPerPlayer": 8},
}


def _dealer_adj(cfg, dealer, repeat_n, a, b):
    if dealer in (a, b):
        return cfg["dealerBonusFan"] + cfg["laZhuangFanPerN"] * repeat_n
    return 0


def win_deltas(total_fan, winner, discarder, dealer, repeat_n,
               cfg=DEFAULT_CFG, la_on=False):
    """Payment lines for one win. discarder None ⇒ 自摸 (3 payers).
    With la_on, 出銃 lines are marked la=True (recorded, not paid)."""
    deltas = []
    if discarder is None:
        for p in range(4):
            if p == winner:
                continue
            amt = total_fan + _dealer_adj(cfg, dealer, repeat_n, winner, p)
            deltas.append(Delta(p, winner, amt, "self_draw"))
    else:
        amt = total_fan + _dealer_adj(cfg, dealer, repeat_n, winner,
                                      discarder)
        deltas.append(Delta(discarder, winner, amt, "discard_win",
                            la=la_on))
    return deltas


def midway_deltas(kind, seat, cfg=DEFAULT_CFG, source=None):
    """中途獎勵. kind: concealed_kong | seven_rob_one | two_tai_flower.
    七搶一 comes from the flower-drawer (`source`); the other two from
    every other player. 花糊 rewards are 拉'd when flowerWinLa."""
    di = cfg["diBase"]
    mw = cfg["midwayRewards"]
    la = cfg["flowerWinLa"]
    if kind == "concealed_kong":
        amt = mw["concealedKongDiPerPlayer"] * di
        return [Delta(p, seat, amt, kind) for p in range(4) if p != seat]
    if kind == "seven_rob_one":
        assert source is not None
        return [Delta(source, seat, mw["sevenRobOneDi"] * di, kind, la=la)]
    if kind == "two_tai_flower":
        amt = mw["twoTaiFlowerDiPerPlayer"] * di
        return [Delta(p, seat, amt, kind, la=la)
                for p in range(4) if p != seat]
    raise ValueError(kind)


class LaLedger:
    """拉/踢半 ledger. Keys are (creditor, debtor) ordered pairs."""

    def __init__(self, cfg=DEFAULT_CFG):
        self.cfg = cfg["laLedger"]
        self.led = {}   # (c, d) -> {"amount": int, "kou": int}

    def record(self, creditor, debtor, amount):
        key = (creditor, debtor)
        cur = self.led.get(key)
        if cur is None:
            self.led[key] = {"amount": amount, "kou": 1}
        else:
            comp = cur["amount"] * self.cfg["compound"]
            comp = math.ceil(comp) if self.cfg["roundUpOnWin"] \
                else math.floor(comp)
            cur["amount"] = comp + amount
            cur["kou"] += 1

    def resolve_on_win(self, winner, discarder):
        """Apply the resolution table for one win event. Returns instant
        Deltas. The NEW win amount itself is handled by the caller
        (record() for 出銃, instant for 自摸)."""
        out = []
        for (c, d) in list(self.led):
            amt = self.led[(c, d)]["amount"]
            if winner == c and discarder == d:
                continue                      # compounding via record()
            if winner == c:                   # creditor wins elsewhere/自摸
                out.append(Delta(d, c, amt, "la_collect"))
                del self.led[(c, d)]
            elif winner == d and (discarder == c or discarder is None):
                half = amt / 2                # 踢半
                half = math.floor(half) if self.cfg["kickHalfRoundDown"] \
                    else math.ceil(half)
                out.append(Delta(d, c, half, "la_kick_half"))
                del self.led[(c, d)]
            elif discarder == d:              # debtor 出銃 elsewhere
                out.append(Delta(d, c, amt, "la_collect"))
                del self.led[(c, d)]
        return out

    def zhan_la(self, creditor, debtor):
        """斬拉: debtor settles the full recorded amount (kou≥3 gate is
        UI-side). Returns the instant Delta."""
        rec = self.led.pop((creditor, debtor))
        return Delta(debtor, creditor, rec["amount"], "la_zhan")

    def can_zhan(self, creditor, debtor):
        rec = self.led.get((creditor, debtor))
        return rec is not None and rec["kou"] >= 3

    def match_end(self):
        """matchEndPolicy 'wipe': cancel everything, return the wiped
        entries for the struck-through UI panel."""
        wiped = [(c, d, rec["amount"], rec["kou"])
                 for (c, d), rec in self.led.items()]
        self.led.clear()
        return wiped


def settle_win(total_fan, winner, discarder, dealer, repeat_n,
               ledger=None, cfg=DEFAULT_CFG):
    """Full settlement of one win: returns list of instant Deltas.
    If `ledger` is provided (拉 ON), 出銃 amounts are recorded there
    instead of paid, and existing ledgers resolve per the table.
    Multi-winner: call once per winner, in seat order from the
    discarder's 下家 (R2)."""
    la_on = ledger is not None
    instant = []
    if la_on:
        instant += ledger.resolve_on_win(winner, discarder)
    for dl in win_deltas(total_fan, winner, discarder, dealer, repeat_n,
                         cfg, la_on):
        if dl.la:
            ledger.record(dl.to, dl.frm, dl.amount)
        else:
            instant.append(dl)
    return instant
