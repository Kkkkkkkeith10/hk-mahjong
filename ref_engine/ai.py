"""L1 AI policy — the shipping baseline for the Flutter client's bots.

Level 1 = competent beginner: always wins when it can, declares 叮 when a
discard leaves a wait, discards by shanten descent (tie-break: fewest
neighbours/most isolated first), claims pung/chow only when it lowers
shanten, kongs when safe. Deterministic given the same views (no RNG), so
self-play games are reproducible from the wall seed alone.
"""
from decompose import shanten, winning_kinds
from engine import Policy
from tiles import NUM_KINDS, JOKER


def _neighbour_score(counts, k):
    """Lower = more isolated = better to throw."""
    s = counts[k] * 10
    if k < 27:                       # suited: adjacent ranks matter
        r = k % 9
        for d in (-2, -1, 1, 2):
            if 0 <= r + d <= 8:
                s += counts[k + d] * (2 if abs(d) == 1 else 1)
    return s


class L1Policy(Policy):
    def choose_swap(self, view, n):
        c = view["counts"].copy()
        picks = []
        for _ in range(n):
            cands = [k for k in range(NUM_KINDS) if c[k] > 0]
            k = min(cands, key=lambda k: _neighbour_score(c, k))
            c[k] -= 1
            picks.append(k)
        return picks

    def _best_discard(self, view):
        c = view["counts"]
        jk = view["jokers"]
        nm = len(view["melds"])
        best, best_key = None, None
        for k in range(NUM_KINDS):
            if c[k] == 0:
                continue
            c[k] -= 1
            key = (shanten(c, jk, nm), _neighbour_score(c, k))
            c[k] += 1
            if best_key is None or key < best_key:
                best, best_key = k, key
        return best

    def choose_discard(self, view):
        return self._best_discard(view)

    def want_win(self, view):
        return True

    def want_ting(self, view):
        c = view["counts"]
        jk = view["jokers"]
        nm = len(view["melds"])
        for k in range(NUM_KINDS):
            if c[k] == 0:
                continue
            c[k] -= 1
            ok = bool(winning_kinds(c, jk, nm))
            c[k] += 1
            if ok:
                return k
        return None

    def want_kong(self, view, options):
        # kong whenever available (replacement draw + 底 reward); a ting
        # hand never reaches here (engine gates it)
        return options[0] if options else None

    def _improves(self, view, take):
        c = view["counts"]
        base = shanten(c, view["jokers"], len(view["melds"]))
        for k in take:
            c[k] -= 1
        after = shanten(c, view["jokers"], len(view["melds"]) + 1)
        for k in take:
            c[k] += 1
        return after < base

    def want_claim(self, view, kind, options):
        if "pung" in options and self._improves(view, [kind, kind]):
            return "pung"
        return None

    def want_chow(self, view, kind, low_options):
        for lo in low_options:
            need = [x for x in (lo, lo + 1, lo + 2) if x != kind]
            if self._improves(view, need):
                return lo
        return None
