"""Fan (番種) recognizer — Python reference for mj_core M2.

Scores a winning hand against data/fan_table.json (153 entries).

Pipeline (總例 p.10-11):
  1. enumerate concealed readings (decompose.enumerate_standard)
  2. per reading: detect pattern instances over the 5 melds (+eye)
  3. 單式結算 (p.11 item 11): instances of the SAME 番種 co-count only if
     every pair shares < 50% of their melds (例1-3). Different 番種 are
     unrestricted here — the 不複合 suppresses graph handles those.
  4. apply the (transitive) suppresses graph from fan_table.json
  5. 高點法 (item 10): max total across readings / placements
  6. 嚦咕兩食 (item 12): standard + liku readings are ADDITIVE

明/暗 variants: a pattern instance is 暗 iff every constituent meld is
concealed; a meld completed by the winning discard/搶槓 counts as exposed
(placement is enumerated; 高點法 picks the best).

Undetected (VERIFY, disabled or never awarded here): 連環套, 金門橋,
滿庭芳, 四子/七子/十子, 大鴨. See ../data/VERIFICATION-fan-table.md.
"""
import json
import os
from dataclasses import dataclass, field
from itertools import combinations

from tiles import (NUM_KINDS, JOKER, is_suited, is_honor, is_terminal,
                   is_orphan, suit_of, rank_of, WIND, DRAGON)
from decompose import (win_forms, enumerate_standard, winning_kinds,
                       wins_liku, liku_pairs, wins_thirteen_orphans,
                       wins_sixteen_disjoint)

DATA = os.path.join(os.path.dirname(__file__), "..", "data",
                    "fan_table.json")

NOT_IMPLEMENTED = {
    "open_chain_loop", "closed_chain_loop",        # VERIFY-4 (連環套)
    "open_golden_gate", "closed_golden_gate",      # VERIFY-4 (金門橋)
    "mixed_court", "pure_court",                   # VERIFY-6 (滿庭芳)
    "four_of_kind_hand", "seven_of_kind_hand",     # VERIFY-9
    "ten_of_kind_hand",                            # VERIFY-9
    "big_duck",                                    # VERIFY (大鴨)
}


class FanTable:
    def __init__(self, path=DATA):
        with open(path, encoding="utf-8") as f:
            doc = json.load(f)
        self.entries = {e["id"]: e for e in doc["entries"]}
        self.settlement = doc["settlement"]
        # transitive closure of suppresses
        self._sup = {}
        for eid in self.entries:
            seen, stack = set(), list(self.entries[eid].get("suppresses", []))
            while stack:
                s = stack.pop()
                if s in seen:
                    continue
                seen.add(s)
                stack += self.entries[s].get("suppresses", [])
            self._sup[eid] = seen

    def value(self, eid, n=1):
        e = self.entries[eid]
        f = e.get("formula")
        if f:
            if f["type"] == "geometric":
                return f["base"] * f["ratio"] ** (n - 1)
            return f["coef"] * n
        return e["value"]

    def enabled(self, eid):
        return self.entries[eid].get("enabled", True)

    def suppressed_by(self, eid):
        return self._sup[eid]


@dataclass
class M:
    """A meld for scoring."""
    kinds: tuple          # 3 kind ints (kong: still 3, kong=True)
    triplet: bool
    concealed: bool
    kong: bool = False


@dataclass
class Ctx:
    """Everything the recognizer needs about a win."""
    counts: list                    # concealed tiles incl. winning tile
    jokers: int = 0
    exposed: list = field(default_factory=list)  # [(kind:int, mtype)]
    # mtype: "chow"(kind=low) | "pung" | "kong_exposed" | "kong_added"
    #        | "kong_concealed"
    win_kind: int = -1
    win_method: str = "discard"     # discard | self_draw | rob_kong
    flowers: tuple = ()             # ints 1..8
    seat: int = 0                   # 0=E 1=S 2=W 3=N
    dealer: bool = False
    dealer_repeat_n: int = 0
    ting: bool = False
    ting_class: str = ""            # "" | heaven | earth | man
    instant_eat: bool = False
    last_tile: bool = False
    flower_draw: bool = False
    kong_draw: bool = False
    tail_chain_n: int = 0
    multi_win: int = 1
    win_class: str = ""             # "" | heaven_earth | man
    seven_rob_one: bool = False
    joker_in_eye: bool = True


def exposed_melds(ctx):
    out = []
    for kind, mtype in ctx.exposed:
        if mtype == "chow":
            out.append(M((kind, kind + 1, kind + 2), False, False))
        elif mtype == "pung":
            out.append(M((kind,) * 3, True, False))
        elif mtype == "kong_concealed":
            out.append(M((kind,) * 3, True, True, kong=True))
        else:  # kong_exposed / kong_added
            out.append(M((kind,) * 3, True, False, kong=True))
    return out


# ── 單式結算: per-fan-id max multiset selection ─────────────────────────

def _select(instances):
    """instances: list of frozensets (meld index sets, same fan id).
    Max count subset with pairwise shared/size < 0.5 (p.11 item 11)."""
    # elements are meld indices (int) plus the eye marker 'E' — stringify
    # for a stable, type-safe sort key
    uniq = sorted(set(instances),
                  key=lambda inst: sorted(str(x) for x in inst))
    best = [0]

    def ok(a, chosen):
        for b in chosen:
            if len(a & b) / min(len(a), len(b)) >= 0.5:
                return False
        return True

    def dfs(i, chosen):
        if len(chosen) + len(uniq) - i <= best[0]:
            return
        if i == len(uniq):
            best[0] = max(best[0], len(chosen))
            return
        if ok(uniq[i], chosen):
            chosen.append(uniq[i])
            dfs(i + 1, chosen)
            chosen.pop()
        dfs(i + 1, chosen)

    dfs(0, [])
    return best[0]


# ── pattern instance detection over one reading ─────────────────────────

def _cycle3(suits):
    """雜 suit rule: consecutive differ + all three suits appear."""
    return (len(set(suits)) == 3
            and all(suits[i] != suits[i + 1] for i in range(len(suits) - 1)))


def reading_instances(ms, eye):
    """ms: list[M] (5 melds). eye: kind (may be JOKER = wildcard).
    Returns dict fan_id -> list[frozenset(indices, 'E' for eye)]."""
    inst = {}

    def add(fid, *idx):
        inst.setdefault(fid, []).append(frozenset(idx))

    runs = [(i, suit_of(m.kinds[0]), rank_of(m.kinds[0]), m.concealed)
            for i, m in enumerate(ms)
            if not m.triplet]
    trips = [(i, m.kinds[0], m.concealed) for i, m in enumerate(ms)
             if m.triplet and m.kinds[0] != JOKER]
    strips = [(i, suit_of(k), rank_of(k), c) for i, k, c in trips
              if is_suited(k)]
    eye_suited = eye != JOKER and is_suited(eye)
    es, er = (suit_of(eye), rank_of(eye)) if eye_suited else (-1, -1)

    def oc(prefix, concs, *idx):
        add(("closed_" if all(concs) else "open_") + prefix, *idx)

    # — same-rank / identical runs —
    for (i, si, ri, ci), (j, sj, rj, cj) in combinations(runs, 2):
        if ri != rj:
            continue
        add("identical_seq_pair" if si == sj else "mixed_double_seq", i, j)
    for c3 in combinations(runs, 3):
        idx, suits, ranks, concs = zip(*c3)
        if len(set(ranks)) != 1:
            continue
        if len(set(suits)) == 3:
            oc("triple_meet", concs, *idx)
        elif len(set(suits)) == 1:
            oc("pure_triple_seq", concs, *idx)
    for c4 in combinations(runs, 4):
        idx, suits, ranks, concs = zip(*c4)
        if len(set(ranks)) != 1:
            continue
        if len(set(suits)) == 1:
            oc("pure_quad_seq", concs, *idx)
        else:
            add("four_same_seq", *idx)
    if len(runs) == 5:
        idx, suits, ranks, concs = zip(*runs)
        if len(set(ranks)) == 1 and len(set(suits)) > 1:
            add("five_same_seq", *idx)
    # 雙同順 / 雙般高: two disjoint pairs, distinguishable (p.11 例2:
    # 般高 pairs may share the rank if suits differ)
    def _double(fid_double, same_suit):
        pairs = [(frozenset((a[0], b[0])), (a[1], a[2]))
                 for a, b in combinations(runs, 2)
                 if a[2] == b[2] and (a[1] == b[1]) == same_suit]
        for (pa, ka), (pb, kb) in combinations(pairs, 2):
            if ka != kb and not (pa & pb):
                add(fid_double, *(pa | pb))
    _double("double_same_seq", False)
    _double("double_identical_seq", True)
    # 老少順
    ts = [(frozenset((a[0], b[0])), a[1])
          for a, b in combinations(runs, 2)
          if a[1] == b[1] and {a[2], b[2]} == {1, 7}]
    for p, _s in ts:
        add("terminal_seq", *p)
    for (pa, sa), (pb, sb) in combinations(ts, 2):
        if sa != sb and not (pa & pb):
            add("double_terminal_seq", *(pa | pb))
    # 龍 (ranks 1,4,7)
    for c3 in combinations(runs, 3):
        idx, suits, ranks, concs = zip(*c3)
        if sorted(ranks) != [1, 4, 7]:
            continue
        if len(set(suits)) == 1:
            oc("pure_dragon", concs, *idx)
        elif len(set(suits)) == 3:
            oc("mixed_dragon", concs, *idx)
    # 步高 (step 1 or 2)
    for n, name in ((3, "3step"), (4, "4step"), (5, "5step")):
        for cn in combinations(runs, n):
            cs = sorted(cn, key=lambda r: r[2])
            idx, suits, ranks, concs = zip(*cs)
            step = ranks[1] - ranks[0]
            if step not in (1, 2):
                continue
            if any(ranks[k + 1] - ranks[k] != step for k in range(n - 1)):
                continue
            if len(set(suits)) == 1:
                oc("pure_" + name, concs, *idx)
            elif _cycle3(suits):
                oc("mixed_" + name, concs, *idx)

    # — triplet families (suited ranks) —
    for (i, si, ri, ci), (j, sj, rj, cj) in combinations(strips, 2):
        if ri == rj and si != sj:
            add("two_same_triplet", i, j)
            if eye_suited and er == ri and es not in (si, sj):
                add("small_three_same_triplet", i, j, "E")
        if si == sj and abs(ri - rj) == 1:
            add("two_chain_triplet", i, j)
        if si == sj and {ri, rj} == {1, 9}:
            add("terminal_triplet", i, j)
    for c3 in combinations(strips, 3):
        idx, suits, ranks, concs = zip(*c3)
        if len(set(ranks)) == 1 and len(set(suits)) == 3:
            add("three_same_triplet", *idx)
    # 雙同刻 / 雙連刻 / 雙老少刻
    stp = [(frozenset((a[0], b[0])), a[2]) for a, b in combinations(strips, 2)
           if a[2] == b[2] and a[1] != b[1]]
    for (pa, ra), (pb, rb) in combinations(stp, 2):
        if ra != rb and not (pa & pb):
            add("double_same_triplet", *(pa | pb))
    ctp = [frozenset((a[0], b[0])) for a, b in combinations(strips, 2)
           if a[1] == b[1] and abs(a[2] - b[2]) == 1]
    for pa, pb in combinations(ctp, 2):
        if not (pa & pb):
            add("double_chain_triplet", *(pa | pb))
    ttp = [(frozenset((a[0], b[0])), a[1]) for a, b in combinations(strips, 2)
           if a[1] == b[1] and {a[2], b[2]} == {1, 9}]
    for (pa, sa), (pb, sb) in combinations(ttp, 2):
        if sa != sb and not (pa & pb):
            add("double_terminal_triplet", *(pa | pb))
    # 連刻 chains, same suit
    names = {2: "two_chain_triplet", 3: "three_chain_triplet",
             4: "four_chain_triplet", 5: "five_chain_triplet"}
    small = {3: "small_three_chain_triplet", 4: "small_four_chain_triplet",
             5: "small_five_chain_triplet", 6: "small_six_chain_triplet"}
    for n in (3, 4, 5):
        for cn in combinations(strips, n):
            cs = sorted(cn, key=lambda t: t[2])
            idx, suits, ranks, concs = zip(*cs)
            if len(set(suits)) == 1 and \
                    all(ranks[k + 1] - ranks[k] == 1 for k in range(n - 1)):
                add(names[n], *idx)
    # 小N連刻: (N-1) chained trips + eye adjacent, same suit
    for n in (2, 3, 4, 5):
        if not eye_suited:
            break
        for cn in combinations(strips, n):
            cs = sorted(cn, key=lambda t: t[2])
            idx, suits, ranks, concs = zip(*cs)
            if len(set(suits)) != 1 or suits[0] != es:
                continue
            if any(ranks[k + 1] - ranks[k] != 1 for k in range(n - 1)):
                continue
            if er == ranks[0] - 1 or er == ranks[-1] + 1:
                add(small[n + 1], *idx, "E")
    # 三色連刻 (rotating suits)
    mnames = {3: "mixed_chain_triplet", 4: "mixed_4chain_triplet",
              5: "mixed_5chain_triplet"}
    msmall = {3: "small_mixed_chain_triplet", 4: "small_mixed_4chain_triplet",
              5: "small_mixed_5chain_triplet", 6: "small_mixed_6chain_triplet"}
    for n in (3, 4, 5):
        for cn in combinations(strips, n):
            cs = sorted(cn, key=lambda t: t[2])
            idx, suits, ranks, concs = zip(*cs)
            if any(ranks[k + 1] - ranks[k] != 1 for k in range(n - 1)):
                continue
            if _cycle3(suits):
                add(mnames[n], *idx)
    for n in (2, 3, 4, 5):  # 小三色N連刻: eye extends the chain
        if not eye_suited:
            break
        for cn in combinations(strips, n):
            cs = sorted(cn, key=lambda t: t[2])
            idx, suits, ranks, concs = zip(*cs)
            if any(ranks[k + 1] - ranks[k] != 1 for k in range(n - 1)):
                continue
            for pos, r_eye in ((0, ranks[0] - 1), (1, ranks[-1] + 1)):
                if er != r_eye:
                    continue
                full = ((es,) + suits) if pos == 0 else (suits + (es,))
                if _cycle3(full):
                    add(msmall[n + 1], *idx, "E")
    return inst


# ── whole-hand / composition fans on a reading ──────────────────────────

def _full_kinds(ms, eye):
    """All 17 tile kinds of the reading (kong extra tile ignored)."""
    ks = [eye, eye]
    for m in ms:
        ks += list(m.kinds)
    return ks


def composition_fans(ks, eye, ms, ctx, award):
    """Tile-composition fans shared by standard + special forms.
    ks: list of 17 kinds (jokers resolved); ms may be None (special)."""
    suited = [k for k in ks if k != JOKER and is_suited(k)]
    honors = [k for k in ks if k != JOKER and is_honor(k)]
    suits = {suit_of(k) for k in suited}
    if not honors:
        award("no_honors")
        if not any(is_terminal(k) for k in suited):
            award("no_terminals")
        if not ctx.flowers:
            award("no_honor_no_flower")
    if not any(k != JOKER and rank_of(k) == 5 and is_suited(k) for k in ks):
        award("missing_five")
    if len(suits) == 2:
        award("missing_one_suit")
    # 五門/七門 — VERIFY definitions (presence-based 小, set-based 大)
    winds = [k for k in honors if k < DRAGON]
    drags = [k for k in honors if k >= DRAGON]
    if len(suits) == 3 and winds and drags:
        award("small_five_types")
        if ctx.flowers and ctx.jokers:
            award("small_seven_types")
        if ms is not None:
            wt = any(m.triplet and WIND <= m.kinds[0] < DRAGON for m in ms)
            dt = any(m.triplet and m.kinds[0] >= DRAGON for m in ms)
            rsuits = {suit_of(m.kinds[0]) for m in ms
                      if m.kinds[0] != JOKER and is_suited(m.kinds[0])}
            if wt and dt and len(rsuits) == 3:
                award("big_five_types")
                if ctx.flowers and ctx.jokers:
                    award("big_seven_types")
    if honors and len(suits) == 1:
        award("mixed_one_suit")
    if not honors and len(suits) == 1 and suited:
        award("pure_one_suit")
    if not suited and honors:
        award("all_honors")
    orphan_only = all(k == JOKER or is_orphan(k) for k in ks)
    term_only = all(k == JOKER or is_terminal(k) for k in ks)
    if term_only:
        award("pure_terminals")
    elif orphan_only:
        award("mixed_terminals")


def flower_fans(ctx, award):
    fl = ctx.flowers
    if not fl:
        award("no_flowers")
    else:
        award("flower_tile", len(fl))
        mine = {ctx.seat + 1, ctx.seat + 5}
        sf = sum(1 for f in fl if f in mine)
        if sf:
            award("seat_flower", sf)
        sets = sum(1 for grp in ({1, 2, 3, 4}, {5, 6, 7, 8})
                   if grp <= set(fl))
        if sets:
            award("one_set_flowers", sets)
    if len(fl) == 8:
        award("eight_immortals")
    if ctx.seven_rob_one:
        award("seven_rob_one")


def situational_fans(ctx, mun_ching, award):
    if ctx.ting:
        award("ting")
    if ctx.ting_class:
        award(ctx.ting_class + "_ting")
    if mun_ching:
        award("mun_ching")
    if ctx.win_method == "self_draw":
        award("self_draw")
        if mun_ching:
            award("mun_mo")
    if ctx.ting and mun_ching:
        award("mun_ting")
    if ctx.instant_eat:
        award("instant_eat")
    if ctx.last_tile:
        award("last_tile")
    if ctx.win_method == "rob_kong":
        award("rob_kong")
    if ctx.flower_draw:
        award("flower_draw")
    if ctx.kong_draw:
        award("kong_draw")
    if ctx.tail_chain_n:
        award("tail_chain_draw", ctx.tail_chain_n)
    if ctx.multi_win == 2:
        award("double_win")
    elif ctx.multi_win == 3:
        award("triple_win")
    if ctx.dealer:
        award("dealer")
    if ctx.dealer_repeat_n:
        award("dealer_repeat", ctx.dealer_repeat_n)
    if ctx.win_class == "heaven_earth":
        award("heaven_earth_win")
    elif ctx.win_class == "man":
        award("man_win")


# ── standard-form reading score ─────────────────────────────────────────

def _score_reading(ms, eye, ctx, table, outs):
    """Score one reading (melds already concealment-adjusted)."""
    awarded = {}

    def award(fid, times=1):
        if fid in NOT_IMPLEMENTED or fid not in table.entries:
            return
        if not table.enabled(fid):
            return
        awarded[fid] = awarded.get(fid, 0) + times

    # pattern instances under 單式結算
    for fid, sets in reading_instances(ms, eye).items():
        n = _select(sets)
        if n:
            award(fid, n)

    trips = [m for m in ms if m.triplet]
    # 暗刻 count
    nc = sum(1 for m in trips if m.concealed)
    for n, fid in ((5, "five_concealed"), (4, "four_concealed"),
                   (3, "three_concealed"), (2, "two_concealed")):
        if nc == n:
            award(fid)
            break
    nk = sum(1 for m in ms if m.kong)
    if nk:
        award("kong", nk)
    # honor sets
    ht = sum(1 for m in trips if is_honor(m.kinds[0]))
    if ht:
        award("honor_tiles", ht)
    if any(m.kinds[0] == WIND + ctx.seat for m in trips):
        award("seat_honor")
    d3 = sum(1 for m in trips if m.kinds[0] >= DRAGON and m.kinds[0] < JOKER)
    w3 = sum(1 for m in trips if WIND <= m.kinds[0] < DRAGON)
    eye_dragon = DRAGON <= eye < JOKER
    eye_wind = WIND <= eye < DRAGON
    if d3 == 3:
        award("big_three_dragons")
    elif d3 == 2 and eye_dragon:
        award("small_three_dragons")
    if w3 == 4:
        award("big_four_winds")
    elif w3 == 3 and eye_wind:
        award("small_four_winds")
    elif w3 == 3:
        award("big_three_winds")
    elif w3 == 2 and eye_wind:
        award("small_three_winds")
    # whole-hand shapes
    if len(trips) == 5:
        award("all_triplets")
        if all(m.concealed for m in trips) and \
                ctx.win_method == "self_draw" and not any(
                    mt != "kong_concealed" for _k, mt in ctx.exposed):
            award("all_concealed_triplets")   # 坎坎糊 VERIFY-5
    if len(trips) == 0:
        award("common_hand")
        if not ctx.flowers and not is_honor(eye) and \
                not any(is_honor(k) for m in ms for k in m.kinds):
            award("big_common")               # 大平 VERIFY-3
    # 帶么 families (every set incl. eye holds orphan / terminal)
    def has_t(kinds):
        return any(k != JOKER and is_terminal(k) for k in kinds)

    def has_o(kinds):
        return any(k != JOKER and is_orphan(k) for k in kinds)
    if all(has_o(m.kinds) for m in ms) and (eye == JOKER or is_orphan(eye)):
        honors_used = any(is_honor(k) for m in ms for k in m.kinds
                          if k != JOKER) or is_honor(eye)
        if all(has_t(m.kinds) for m in ms) and \
                (eye == JOKER or is_terminal(eye)) and not honors_used:
            award("pure_terminal_sets")
        elif honors_used:
            award("mixed_terminal_sets")
        else:
            award("pure_terminal_sets")
    # 四歸 (VERIFY-7)
    ks = _full_kinds(ms, eye)
    quad_kinds = 0
    for k in range(NUM_KINDS):
        if not is_suited(k) or ks.count(k) != 4:
            continue
        if any(m.kong and m.kinds[0] == k for m in ms):
            continue
        quad_kinds += 1
        in_trip = [m for m in ms if m.triplet and m.kinds[0] == k]
        involved = [m for m in ms if k in m.kinds]
        closed = all(m.concealed for m in involved)
        if eye == k:
            award("closed_four_to_two" if closed else "open_four_to_two")
        elif in_trip:
            award("closed_four_to_three" if closed else "open_four_to_three")
        else:
            award("closed_four_to_four" if closed else "open_four_to_four")
    if quad_kinds >= 3:
        award("eight_return")
        award("twelve_return")
    elif quad_kinds == 2:
        award("eight_return")
    # composition + flowers + situational
    mun_ching = not any(mt != "kong_concealed" for _k, mt in ctx.exposed)
    composition_fans(ks, eye, ms, ctx, award)
    flower_fans(ctx, award)
    situational_fans(ctx, mun_ching, award)
    # wait shape
    _wait_fans(ms, eye, ctx, outs, award)
    return awarded


def _wait_fans(ms, eye, ctx, outs, award):
    if ctx.win_kind < 0 or outs is None:
        return
    if len(outs) == 1:
        award("single_wait")            # 獨獨
        return
    w = ctx.win_kind
    if eye == w:
        award("pair_eye_wait")          # 將眼
        return
    for m in ms:
        if w not in m.kinds:
            continue
        if m.triplet:
            award("pair_call_win")      # 對碰
            return
        a, b, c = m.kinds
        if w == b or (w == c and rank_of(a) == 1) or \
                (w == a and rank_of(c) == 9):
            award("false_single")       # 假獨 (卡/邊 with other outs)
            return
    # 兩面 or joker-resolved: no wait fan


# ── special forms ───────────────────────────────────────────────────────

def _score_liku(ctx, table):
    awarded = {}

    def award(fid, times=1):
        if fid in table.entries and table.enabled(fid) and \
                fid not in NOT_IMPLEMENTED:
            awarded[fid] = awarded.get(fid, 0) + times

    award("liku_liku")
    trip, pairs = liku_pairs(ctx.counts) if not ctx.jokers else (None, None)
    if pairs is not None:
        groups = pairs + [trip]
        if len(set(groups)) == 8:
            award("eight_pairs_liku")   # VERIFY-13
        if all(d in groups for d in range(DRAGON, DRAGON + 3)):
            award("dragon_liku")
        if all(w in groups for w in range(WIND, WIND + 4)):
            award("winds_liku")
        # 三色同對
        pr = set(pairs)
        for r in range(1, 10):
            if all(s * 9 + r - 1 in pr for s in range(3)):
                award("three_suit_same_pair")
        # 連對 (chain pairs incl. the triplet kind)
        best = 0
        for s in range(3):
            ranks = {rank_of(k) for k in set(groups)
                     if is_suited(k) and suit_of(k) == s}
            for r in range(1, 10):
                n = 0
                while r + n <= 9 and (r + n) in ranks:
                    n += 1
                best = max(best, n)
        names = {3: "three_chain_pairs", 4: "four_chain_pairs",
                 5: "five_chain_pairs", 6: "six_chain_pairs",
                 7: "seven_chain_pairs", 8: "eight_chain_pairs"}
        if best >= 3:
            award(names[min(best, 8)])
    ks = []
    for k in range(NUM_KINDS):
        ks += [k] * ctx.counts[k]
    composition_fans(ks, -1, None, ctx, award)
    return awarded


def _score_sixteen(ctx, table, outs):
    awarded = {}

    def award(fid, times=1):
        if fid in table.entries and table.enabled(fid):
            awarded[fid] = awarded.get(fid, 0) + times

    award("sixteen_disjoint")
    kinds = [k for k in range(NUM_KINDS) if ctx.counts[k]]
    if outs is not None and len(outs) >= 16:
        award("sixteen_gates_disjoint")
    by_rank = {}
    for k in kinds:
        if is_suited(k):
            by_rank.setdefault(rank_of(k), set()).add(suit_of(k))
    if any(len(s) == 3 for s in by_rank.values()):
        award("disjoint_three_meet")    # VERIFY
    suited = [k for k in kinds if is_suited(k)]
    if len(suited) == 9 and sorted(rank_of(k) for k in suited) == \
            list(range(1, 10)):
        by_suit = {}
        for k in suited:
            by_suit.setdefault(suit_of(k), set()).add(rank_of(k) % 3)
        if len(by_suit) == 3 and all(len(v) == 1 for v in by_suit.values()):
            award("disjoint_mixed_dragon")  # VERIFY
    return awarded


def _score_orphans(ctx, table, outs):
    awarded = {"thirteen_orphans": 1}
    if outs is not None and len(outs) >= 13 and \
            table.enabled("thirteen_gates_orphans"):
        awarded["thirteen_gates_orphans"] = 1
    return awarded


# ── suppresses + totals ─────────────────────────────────────────────────

def _points(fid, n, table):
    e = table.entries[fid]
    if e.get("formula"):
        return table.value(fid, n)
    return e["value"] * n


def _apply_suppresses(awarded, table):
    """不複合: the suppresses graph defines mutually exclusive alternative
    countings; 高點法 keeps the max-total compatible subset (p.11 例2:
    相逢×2+雙般高 26 beats 四同順 20)."""
    ids_ = sorted(awarded, key=lambda f: -_points(f, awarded[f], table))
    conf = {f: set() for f in ids_}
    for a in ids_:
        for b in ids_:
            if a != b and (b in table.suppressed_by(a)
                           or a in table.suppressed_by(b)):
                conf[a].add(b)
    if not any(conf.values()):
        return awarded
    pts = {f: _points(f, awarded[f], table) for f in ids_}
    best = [-1, {}]

    def dfs(i, cur, tot, blocked):
        rem = tot + sum(pts[f] for f in ids_[i:] if f not in blocked)
        if rem <= best[0]:
            return
        if i == len(ids_):
            best[0], best[1] = tot, dict(cur)
            return
        f = ids_[i]
        if f not in blocked:
            cur[f] = awarded[f]
            dfs(i + 1, cur, tot + pts[f], blocked | conf[f])
            del cur[f]
        dfs(i + 1, cur, tot, blocked)

    dfs(0, {}, 0, set())
    return best[1]


def _finalize(awarded, table):
    out = []
    total = 0
    for fid, n in sorted(awarded.items(),
                         key=lambda kv: -_points(kv[0], kv[1], table)):
        pts = _points(fid, n, table)
        out.append((fid, n, pts))
        total += pts
    return out, total


def score_win(ctx, table=None):
    """Score a winning hand. Returns dict with fans/total/forms, or
    {'error': 'not_a_win'}."""
    table = table or FanTable()
    n_exp = len(ctx.exposed)
    forms = win_forms(ctx.counts, ctx.jokers, n_exp, ctx.joker_in_eye)
    if not forms:
        return {"error": "not_a_win"}
    # pre-win waits (for 獨獨/扇 fans)
    outs = None
    if 0 <= ctx.win_kind < NUM_KINDS and ctx.counts[ctx.win_kind] > 0:
        pre = ctx.counts.copy()
        pre[ctx.win_kind] -= 1
        outs = winning_kinds(pre, ctx.jokers, n_exp, ctx.joker_in_eye)

    best_std = None
    if "standard" in forms:
        exp = exposed_melds(ctx)
        for eye, melds in enumerate_standard(ctx.counts, ctx.jokers,
                                             5 - n_exp, ctx.joker_in_eye):
            base = exp + [M(kinds, trip, True) for kinds, trip in melds]
            variants = [base]
            if ctx.win_method in ("discard", "rob_kong") and ctx.win_kind >= 0:
                variants = []
                for wi in range(len(exp), len(base)):
                    if ctx.win_kind in base[wi].kinds:
                        v = [M(m.kinds, m.triplet,
                               m.concealed and i != wi, m.kong)
                             for i, m in enumerate(base)]
                        variants.append(v)
                if eye == ctx.win_kind or not variants:
                    variants.append(base)
            for ms in variants:
                aw = _score_reading(ms, eye, ctx, table, outs)
                aw = _apply_suppresses(aw, table)
                fans, tot = _finalize(aw, table)
                if best_std is None or tot > best_std[1]:
                    best_std = (fans, tot, (eye, tuple(m.kinds for m in ms)))

    def special(scorer):
        aw = dict(scorer)
        mun_ching = not any(mt != "kong_concealed" for _k, mt in ctx.exposed)

        def award(fid, times=1):
            if fid in table.entries and table.enabled(fid):
                aw[fid] = aw.get(fid, 0) + times
        flower_fans(ctx, award)
        situational_fans(ctx, mun_ching, award)
        if outs is not None and len(outs) == 1:
            award("single_wait")
        aw = _apply_suppresses(aw, table)
        return _finalize(aw, table)

    results = {}
    if best_std:
        results["standard"] = best_std[:2]
    if "liku" in forms:
        results["liku"] = special(_score_liku(ctx, table))
    if "sixteen" in forms:
        results["sixteen"] = special(_score_sixteen(ctx, table, outs))
    if "orphans" in forms:
        results["orphans"] = special(_score_orphans(ctx, table, outs))

    # 嚦咕兩食 (p.11 item 12): standard + liku are additive; otherwise 高點法
    if "standard" in results and "liku" in results:
        fans = results["standard"][0] + \
            [(f, n, p) for f, n, p in results["liku"][0]
             if f in ("liku_liku", "eight_pairs_liku", "dragon_liku",
                      "winds_liku", "three_suit_same_pair") or
             f.endswith("_chain_pairs")]
        total = sum(p for _f, _n, p in fans)
        best = (fans, total, "liku_two_eat")
    else:
        best = max(((v[0], v[1], form) for form, v in results.items()),
                   key=lambda t: t[1])

    fans, total, form = best
    # 大雞 (VERIFY): a win carrying zero fan
    if total == 0 and table.enabled("big_chicken"):
        fans = [("big_chicken", 1, table.value("big_chicken"))]
        total = fans[0][2]
    return {"fans": fans, "total": total, "form": form, "forms": forms}
