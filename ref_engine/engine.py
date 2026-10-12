"""Game state machine — Python reference for mj_core M2.

One 局 (hand) of 港式台牌, driven synchronously by four Policy objects.
Emits a full event log (the golden-fixture format the Dart port replays).

Rules implemented (總例 pp.3-9, p.11; VERIFY items marked):
  配牌 4×4×4 (dealer draws the 17th as first-turn draw) · 補花 from tail ·
  換牌 room option (fixed 3 or dice count, pass to 下家 — direction VERIFY)
  · claims 食糊 > 碰/槓 > 上 · simultaneous winners (雙響/三響) · 過水
  (same-巡 block; 叮 decline = whole-局; declined 加槓 rob too) · 叮
  (locked hand, rotated discards, 即食 window, 天/地叮) · 槓 (暗/明/加,
  tail replacement draw, 搶槓 vs 加槓 only, 暗槓 never robbable, 暗槓
  instant 1底/家) · 海底 · 槓摸/花摸/尾牌連摸 chain · 百搭 (may not be
  discarded — VERIFY) · 七搶一/八仙過海 flower events end the 局 as 花糊
  (rewards 拉落下一鋪, dealer 連莊 — VERIFY) · 流局 ⇒ 連莊.
"""
from dataclasses import dataclass, field

from tiles import id_to_kind, kind_to_id, JOKER, NUM_KINDS
from decompose import win_forms, winning_kinds, shanten
from fans import Ctx, FanTable, score_win
from settle import settle_win, midway_deltas
from wall import Wall, SplitMix64


def is_flower(tid):
    return tid[0] == "X"


@dataclass
class Player:
    counts: list = field(default_factory=lambda: [0] * NUM_KINDS)
    jokers: int = 0
    flowers: list = field(default_factory=list)
    melds: list = field(default_factory=list)   # (kind:int, mtype:str)
    discards: list = field(default_factory=list)
    ting: bool = False
    ting_class: str = ""
    ting_turn: int = -1        # turn counter at 叮 (for 即食)
    blocked_turn: bool = False  # 過水 until own next draw
    blocked_hand: bool = False  # 叮過水: whole 局

    def add(self, tid):
        if tid == "J0":
            self.jokers += 1
        else:
            self.counts[id_to_kind(tid)] += 1

    def remove_kind(self, k, n=1):
        assert self.counts[k] >= n
        self.counts[k] -= n

    def hand_size(self):
        return sum(self.counts) + self.jokers


class Options:
    def __init__(self, jokers=0, swap="off", la_on=True,
                 joker_in_eye=True):
        assert jokers in (0, 4, 8) and swap in ("off", "fixed3", "dice")
        self.jokers = jokers
        self.swap = swap
        self.la_on = la_on
        self.joker_in_eye = joker_in_eye


class Engine:
    def __init__(self, seed, opts=None, dealer=0, repeat_n=0,
                 table=None, ledger=None):
        self.opts = opts or Options()
        self.rng = SplitMix64(seed ^ 0xD1CE)   # aux rng (dice), separate
        self.wall = Wall(seed, self.opts.jokers)
        self.dealer = dealer
        self.repeat_n = repeat_n
        self.table = table or FanTable()
        self.ledger = ledger
        self.players = [Player() for _ in range(4)]
        self.events = []
        self.turn_count = 0        # increments on every head draw
        self.any_meld = False      # any 鳴牌/暗槓 this 局
        self.tail_chain = 0        # current player's consecutive tail draws
        self.last_draw_kind = -1
        self.deltas = []
        self.result = None

    # ── logging ─────────────────────────────────────────────────────────
    def log(self, type_, **kw):
        self.events.append({"type": type_, **kw})

    def _apply_deltas(self, ds):
        """Instant deltas are paid; la-flagged ones (花糊 rewards when
        flowerWinLa) are recorded to the ledger instead."""
        for d in ds:
            if d.la and self.ledger is not None:
                self.ledger.record(d.to, d.frm, d.amount)
            else:
                self.deltas.append(d)

    # ── setup ───────────────────────────────────────────────────────────
    def _deal(self, policies):
        hands = self.wall.deal_initial()
        for s, h in enumerate(hands):
            for tid in h:
                self.players[s].add(tid) if not is_flower(tid) \
                    else self.players[s].flowers.append(int(tid[1]))
        self.log("deal", hands=hands)
        # 換牌 (before 補花 — VERIFY ordering)
        if self.opts.swap != "off":
            n = 3 if self.opts.swap == "fixed3" else \
                (self.rng.next_bounded(6) + 1)
            self.log("swap_count", n=n)
            gives = []
            for s in range(4):
                g = policies[s].choose_swap(self._view(s), n)
                assert len(g) == n
                for k in g:
                    self.players[s].remove_kind(k)
                gives.append(g)
            for s in range(4):   # pass to 下家 (VERIFY direction)
                for k in gives[s]:
                    self.players[(s + 1) % 4].counts[k] += 1
            self.log("swap", gives=gives)
        # 補花 in seat-order rounds from tail (flowers were set aside at
        # deal, so hand_size < 16 marks how many replacements are owed)
        changed = True
        while changed:
            changed = False
            for s in range(4):
                p = self.players[s]
                need = 16 - p.hand_size()
                for _ in range(need):
                    tid = self.wall.draw_tail()
                    self.log("flower_replace", seat=s, tile=tid)
                    if is_flower(tid):
                        p.flowers.append(int(tid[1]))
                    else:
                        p.add(tid)
                    changed = True
        for s in range(4):
            if self._flower_events(s, policies):
                return

    def _view(self, seat):
        p = self.players[seat]
        return {"seat": seat, "counts": p.counts.copy(),
                "jokers": p.jokers, "melds": list(p.melds),
                "flowers": tuple(p.flowers), "ting": p.ting,
                "discards": [list(q.discards) for q in self.players],
                "wall_remaining": self.wall.remaining,
                "dealer": self.dealer}

    # ── win helpers ─────────────────────────────────────────────────────
    def _ctx(self, seat, win_kind, method, flags):
        p = self.players[seat]
        c = p.counts.copy()
        return Ctx(counts=c, jokers=p.jokers, exposed=list(p.melds),
                   win_kind=win_kind, win_method=method,
                   flowers=tuple(p.flowers), seat=seat,
                   ting=p.ting, ting_class=p.ting_class,
                   joker_in_eye=self.opts.joker_in_eye, **flags)

    def _can_win(self, seat, extra_kind=None):
        p = self.players[seat]
        c = p.counts.copy()
        if extra_kind is not None:
            c[extra_kind] += 1
        return bool(win_forms(c, p.jokers, len(p.melds),
                              self.opts.joker_in_eye))

    def _instant_eat(self, seat):
        p = self.players[seat]
        return (p.ting and p.ting_turn >= 0 and not self.any_meld
                and self.turn_count - p.ting_turn <= 4)

    def _finish_win(self, winners, discarder, flags_by_seat):
        results = []
        for w in winners:
            ctx = self._ctx(w, self.last_win_kind[w], self.win_method[w],
                            flags_by_seat[w])
            r = score_win(ctx, self.table)
            assert "error" not in r, r
            results.append((w, r))
            self.log("win", seat=w, total=r["total"],
                     fans=[(f, n, p_) for f, n, p_ in r["fans"]],
                     form=r["form"])
        order = winners if discarder is None else sorted(
            winners, key=lambda s: (s - discarder - 1) % 4)
        for w in order:
            r = dict(results)[w]
            self.deltas += settle_win(
                r["total"], w, discarder, self.dealer, self.repeat_n,
                self.ledger, _cfg(self.table))
        self.result = {"kind": "win", "winners": results,
                       "discarder": discarder, "deltas": self.deltas,
                       "dealer_repeats": self.dealer in winners}

    # ── main loop ───────────────────────────────────────────────────────
    def play(self, policies):
        self.last_win_kind = {}
        self.win_method = {}
        self._deal(policies)
        if self.result is not None:      # flower_hu straight off the deal
            return self.result
        cur = self.dealer

        while self.result is None:
            p = self.players[cur]

            # ---- draw phase ----
            from_tail = False
            while True:
                if self.wall.remaining == 0:
                    self._exhaust()
                    return self.result
                tid = self.wall.draw_tail() if from_tail else self.wall.draw()
                if not from_tail:
                    self.turn_count += 1
                if is_flower(tid):
                    p.flowers.append(int(tid[1]))
                    self.log("flower", seat=cur, tile=tid)
                    if self._flower_events(cur, policies):
                        return self.result
                    from_tail = True
                    continue
                break
            p.add(tid)
            draw_kind = JOKER if tid == "J0" else id_to_kind(tid)
            self.log("draw", seat=cur, tail=from_tail)
            if from_tail:
                self.tail_chain += 1
            else:
                self.tail_chain = 0
            p.blocked_turn = False   # 過水 clears on own draw

            # ---- self-draw win? ----
            # in the main draw phase a tail draw only ever follows a
            # flower, so from_tail ⇒ 花摸 (kong replacements go through
            # _replacement_draw, which flags 槓摸 itself)
            if self._can_win(cur) and not p.blocked_hand:
                flags = {"last_tile": self.wall.remaining == 0,
                         "flower_draw": from_tail,
                         "kong_draw": False,
                         "instant_eat": self._instant_eat(cur),
                         "tail_chain_n": self.tail_chain
                         if self.tail_chain >= 2 else 0,
                         "win_class": self._win_class(cur, None)}
                if p.ting or policies[cur].want_win(self._view(cur)):
                    self.last_win_kind[cur] = draw_kind
                    self.win_method[cur] = "self_draw"
                    self._finish_win([cur], None, {cur: flags})
                    return self.result
                # declining 自摸 is allowed without 過水 (VERIFY)

            # ---- ting player: locked, rotate the drawn tile out ----
            if p.ting:
                if draw_kind == JOKER:
                    # drew a joker while ting and (somehow) didn't win:
                    # rotate it out, unclaimable — VERIFY (near-
                    # unreachable, since a wild tile completes any wait)
                    p.jokers -= 1
                    self.log("discard", seat=cur, kind=JOKER, rotated=True)
                    cur = (cur + 1) % 4
                    continue
                p.remove_kind(draw_kind)
                p.discards.append(draw_kind)
                self.log("discard", seat=cur, kind=draw_kind, rotated=True)
                nxt = self._claims(cur, draw_kind, policies)
                if self.result is not None:
                    return self.result
                cur = nxt
                continue

            # ---- kongs on own turn ----
            while True:
                kg = self._kong_options(cur)
                if not kg:
                    break
                choice = policies[cur].want_kong(self._view(cur), kg)
                if choice is None:
                    break
                kind, ktype = choice
                if ktype == "concealed":
                    p.remove_kind(kind, 4)
                    p.melds.append((kind, "kong_concealed"))
                    self._apply_deltas(midway_deltas(
                        "concealed_kong", cur, _cfg(self.table)))
                    self.any_meld = True
                    self.log("kong", seat=cur, kind=kind, ktype=ktype)
                else:   # added: rob window (搶槓)
                    self.log("kong_add_attempt", seat=cur, kind=kind)
                    robbers = self._rob_kong(cur, kind, policies)
                    if robbers:
                        return self.result
                    p.remove_kind(kind)
                    p.melds = [(k, "kong_added") if k == kind and
                               t == "pung" else (k, t)
                               for k, t in p.melds]
                    self.any_meld = True
                    self.log("kong", seat=cur, kind=kind, ktype=ktype)
                # replacement draw from tail
                ok = self._replacement_draw(cur, policies, kong=True)
                if self.result is not None:
                    return self.result
                if not ok:
                    return self.result

            # ---- ting declaration ----
            if not p.ting:
                d = policies[cur].want_ting(self._view(cur))
                if d is not None:
                    k_discard = d
                    p.remove_kind(k_discard)
                    if winning_kinds(p.counts, p.jokers, len(p.melds),
                                     self.opts.joker_in_eye):
                        p.ting = True
                        p.ting_turn = self.turn_count
                        # 天叮: 莊 on very first turn; 地叮: 閒 on own
                        # first discard, uncalled round — VERIFY
                        if cur == self.dealer and self.turn_count == 1 \
                                and not self.any_meld:
                            p.ting_class = "heaven"
                        elif cur != self.dealer and not p.discards \
                                and self.turn_count <= 4 \
                                and not self.any_meld:
                            p.ting_class = "earth"
                        self.log("ting", seat=cur, cls=p.ting_class)
                        p.discards.append(k_discard)
                        self.log("discard", seat=cur, kind=k_discard,
                                 rotated=False)
                        nxt = self._claims(cur, k_discard, policies)
                        if self.result is not None:
                            return self.result
                        cur = nxt
                        continue
                    p.counts[k_discard] += 1   # invalid ting: ignore

            # ---- normal discard ----
            k = policies[cur].choose_discard(self._view(cur))
            assert k != JOKER, "百搭 may not be discarded (VERIFY)"
            p.remove_kind(k)
            p.discards.append(k)
            self.log("discard", seat=cur, kind=k, rotated=False)
            nxt = self._claims(cur, k, policies)
            if self.result is not None:
                return self.result
            cur = nxt
        return self.result

    def _replacement_draw(self, seat, policies, kong):
        p = self.players[seat]
        while True:
            if self.wall.remaining == 0:
                self._exhaust()
                return False
            tid = self.wall.draw_tail()
            if is_flower(tid):
                p.flowers.append(int(tid[1]))
                self.log("flower", seat=seat, tile=tid)
                if self._flower_events(seat, policies):
                    return False
                continue
            p.add(tid)
            self.tail_chain += 1
            self.log("draw", seat=seat, tail=True)
            k = JOKER if tid == "J0" else id_to_kind(tid)
            if self._can_win(seat) and not p.blocked_hand:
                flags = {"kong_draw": kong, "flower_draw": not kong,
                         "last_tile": self.wall.remaining == 0,
                         "instant_eat": self._instant_eat(seat),
                         "tail_chain_n": self.tail_chain
                         if self.tail_chain >= 2 else 0,
                         "win_class": ""}
                if p.ting or policies[seat].want_win(self._view(seat)):
                    self.last_win_kind[seat] = k
                    self.win_method[seat] = "self_draw"
                    self._finish_win([seat], None, {seat: flags})
                    return False
            return True

    def _win_class(self, seat, discarder):
        # 天/地/人糊 — VERIFY-8 definitions
        if seat == self.dealer and self.turn_count <= 1 \
                and not self.any_meld and discarder is None:
            return "heaven_earth"
        if discarder == self.dealer and self.turn_count <= 1 \
                and not self.any_meld:
            return "heaven_earth"
        if seat != self.dealer and discarder is None \
                and self.turn_count <= 4 and not self.any_meld:
            return "man"
        return ""

    def _kong_options(self, seat):
        p = self.players[seat]
        opts = []
        if p.ting:
            return opts    # no kongs after 叮 (VERIFY)
        for k in range(NUM_KINDS):
            if p.counts[k] == 4:
                opts.append((k, "concealed"))
        for k, t in p.melds:
            if t == "pung" and p.counts[k] >= 1:
                opts.append((k, "added"))
        return opts

    def _rob_kong(self, konger, kind, policies):
        winners = []
        for off in range(1, 4):
            s = (konger + off) % 4
            q = self.players[s]
            if q.blocked_hand or q.blocked_turn:
                continue
            if self._can_win(s, kind):
                if q.ting or policies[s].want_win(self._view(s)):
                    winners.append(s)
                else:
                    q.blocked_hand = True   # declined 搶槓 ⇒ 過水成局
                    self.log("pass_rob", seat=s)
        if winners:
            flags = {}
            for w in winners:
                self.players[w].counts[kind] += 1
                self.last_win_kind[w] = kind
                self.win_method[w] = "rob_kong"
                flags[w] = {"instant_eat": self._instant_eat(w),
                            "multi_win": len(winners), "win_class": ""}
            self._finish_win(winners, konger, flags)
        return winners

    def _claims(self, discarder, kind, policies):
        """Resolve claims; returns next seat. Sets self.result on win."""
        # 1. wins (all simultaneous winners valid)
        winners = []
        for off in range(1, 4):
            s = (discarder + off) % 4
            q = self.players[s]
            if q.blocked_hand or q.blocked_turn:
                continue
            if self._can_win(s, kind):
                if q.ting or policies[s].want_win(self._view(s)):
                    winners.append(s)
                else:
                    if q.ting:
                        q.blocked_hand = True
                    else:
                        q.blocked_turn = True   # 過水: until own next draw
                    self.log("pass_win", seat=s)
        if winners:
            flags = {}
            for w in winners:
                self.players[w].counts[kind] += 1
                self.last_win_kind[w] = kind
                self.win_method[w] = "discard"
                flags[w] = {"last_tile": self.wall.remaining == 0,
                            "instant_eat": self._instant_eat(w),
                            "multi_win": len(winners),
                            "win_class": self._win_class(w, discarder)}
            self._finish_win(winners, discarder, flags)
            return -1
        # 2. pung / exposed kong
        for off in range(1, 4):
            s = (discarder + off) % 4
            q = self.players[s]
            if q.ting:
                continue
            options = []
            if q.counts[kind] >= 3:
                options.append("kong")
            if q.counts[kind] >= 2:
                options.append("pung")
            if not options:
                continue
            c = policies[s].want_claim(self._view(s), kind, options)
            if c in options:
                self.players[discarder].discards.pop()
                self.any_meld = True
                if c == "kong":
                    q.remove_kind(kind, 3)
                    q.melds.append((kind, "kong_exposed"))
                    self.log("claim", seat=s, kind=kind, what="kong")
                    self._replacement_draw(s, policies, kong=True)
                    if self.result is not None:
                        return -1
                else:
                    q.remove_kind(kind, 2)
                    q.melds.append((kind, "pung"))
                    self.log("claim", seat=s, kind=kind, what="pung")
                nxt = self._post_claim_discard(s, policies)
                if self.result is not None:
                    return -1
                return nxt
        # 3. chow (next player only)
        s = (discarder + 1) % 4
        q = self.players[s]
        if not q.ting and kind < 27:
            lows = [kind - 2, kind - 1, kind]
            opts = []
            for lo in lows:
                if lo < 0 or lo // 9 != kind // 9 or (lo + 2) // 9 != kind // 9:
                    continue
                need = [x for x in (lo, lo + 1, lo + 2) if x != kind]
                if all(q.counts[x] >= 1 for x in need):
                    opts.append(lo)
            if opts:
                lo = policies[s].want_chow(self._view(s), kind, opts)
                if lo in opts:
                    self.players[discarder].discards.pop()
                    for x in (lo, lo + 1, lo + 2):
                        if x != kind:
                            q.remove_kind(x)
                    q.melds.append((lo, "chow"))
                    self.any_meld = True
                    self.log("claim", seat=s, kind=lo, what="chow")
                    nxt = self._post_claim_discard(s, policies)
                    if self.result is not None:
                        return -1
                    return nxt
        return (discarder + 1) % 4

    def _post_claim_discard(self, seat, policies):
        """After a claim the claimer discards; that discard may itself be
        claimed (chains recurse). Returns the seat whose turn is next."""
        p = self.players[seat]
        k = policies[seat].choose_discard(self._view(seat))
        assert k != JOKER
        p.remove_kind(k)
        p.discards.append(k)
        self.log("discard", seat=seat, kind=k, rotated=False)
        return self._claims(seat, k, policies)

    def _flower_events(self, seat, policies):
        """七搶一 / 八仙過海 midway checks. Returns True if 局 ended."""
        p = self.players[seat]
        if len(p.flowers) == 8:
            self._apply_deltas(midway_deltas("two_tai_flower", seat,
                                             _cfg(self.table)))
            self.log("flower_hu", seat=seat, kind="eight")
            self.result = {"kind": "flower_hu", "seat": seat,
                           "deltas": self.deltas, "dealer_repeats": True}
            return True
        if len(p.flowers) == 7:
            for off in range(1, 4):
                v = (seat + off) % 4
                if len(self.players[v].flowers) == 1:
                    self._apply_deltas(midway_deltas(
                        "seven_rob_one", seat, _cfg(self.table), source=v))
                    p.flowers += self.players[v].flowers
                    self.players[v].flowers = []
                    self.log("flower_hu", seat=seat, kind="seven_rob",
                             victim=v)
                    self.result = {"kind": "flower_hu", "seat": seat,
                                   "deltas": self.deltas,
                                   "dealer_repeats": True}
                    return True
        return False

    def _exhaust(self):
        self.log("exhaust")
        self.result = {"kind": "exhaust", "deltas": self.deltas,
                       "dealer_repeats": True}


def _cfg(table):
    from settle import DEFAULT_CFG
    cfg = dict(DEFAULT_CFG)
    cfg.update(table.settlement)
    return cfg


class Policy:
    """Interface. Views are dicts; kinds are ints."""

    def choose_swap(self, view, n):
        raise NotImplementedError

    def choose_discard(self, view):
        raise NotImplementedError

    def want_win(self, view):
        return True

    def want_ting(self, view):
        """Return the kind to discard while declaring 叮, or None."""
        return None

    def want_kong(self, view, options):
        return None

    def want_claim(self, view, kind, options):
        return None

    def want_chow(self, view, kind, low_options):
        return None
