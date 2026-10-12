"""Hand decomposition, win detection, waits, and shanten — joker-aware.

A full hand is 17 tiles = 5 面子 + 1 眼 (基本形), or a 特殊形
(嚦咕嚦咕 / 十三么 / 十六不搭). Exposed melds reduce the concealed
requirement: concealed part must form (5 - len(melds)) melds + eye.

Jokers (百搭, D2: universal substitutes) may stand for any tile in the
concealed part; a room sub-option may forbid them as the eye.

Decompositions are enumerated with jokers resolved to concrete kinds so
the fan recognizer can score each reading; 高點法 takes the max.
"""
from tiles import NUM_KINDS, is_suited, suit_of, ORPHANS, JOKER

# ── boolean win check (fast, memoized) ──────────────────────────────────

def _can_melds(cnt, jk, todo, cache):
    if todo == 0:
        return not any(cnt) and jk == 0
    i = 0
    while i < NUM_KINDS and cnt[i] == 0:
        i += 1
    if i == NUM_KINDS:
        return jk == todo * 3
    key = (bytes(cnt), jk, todo)
    hit = cache.get(key)
    if hit is not None:
        return hit
    r = False
    c0 = cnt[i]
    # use copies of kind i as a triplet (pad with jokers only when it
    # consumes all remaining copies, to avoid stranded tiles)
    if c0 >= 3:
        cnt[i] -= 3
        r = _can_melds(cnt, jk, todo - 1, cache)
        cnt[i] += 3
    if not r and c0 < 3 and jk >= 3 - c0:
        cnt[i] = 0
        r = _can_melds(cnt, jk - (3 - c0), todo - 1, cache)
        cnt[i] = c0
    # runs starting at i (first tile real — i is the lowest occupied kind)
    if not r and is_suited(i) and i % 9 <= 6:
        b, c = i + 1, i + 2
        for jb in (0, 1):
            if jb and jk < 1:
                continue
            if not jb and cnt[b] == 0:
                continue
            for jc in (0, 1):
                uj = jb + jc
                if jk < uj:
                    continue
                if not jc and cnt[c] == 0:
                    continue
                cnt[i] -= 1
                if not jb: cnt[b] -= 1
                if not jc: cnt[c] -= 1
                if _can_melds(cnt, jk - uj, todo - 1, cache):
                    r = True
                cnt[i] += 1
                if not jb: cnt[b] += 1
                if not jc: cnt[c] += 1
                if r:
                    break
            if r:
                break
    cache[key] = r
    return r


def wins_standard(counts, jokers, need_melds, joker_in_eye=True):
    if sum(counts) + jokers != need_melds * 3 + 2:
        return False
    cache = {}
    for eye in range(NUM_KINDS):
        if counts[eye] >= 2:
            counts[eye] -= 2
            ok = _can_melds(counts, jokers, need_melds, cache)
            counts[eye] += 2
            if ok:
                return True
        if joker_in_eye and counts[eye] == 1 and jokers >= 1:
            counts[eye] -= 1
            ok = _can_melds(counts, jokers - 1, need_melds, cache)
            counts[eye] += 1
            if ok:
                return True
    if joker_in_eye and jokers >= 2:
        return _can_melds(counts, jokers - 2, need_melds, cache)
    return False

# ── enumeration for scoring (jokers resolved) ───────────────────────────
# A meld is ((k1,k2,k3), is_triplet). Reading = (eye_kind, sorted melds).

def _enum_melds(cnt, jk, todo, out, acc, limit):
    if len(out) >= limit:
        return
    if todo == 0:
        if not any(cnt) and jk == 0:
            out.add(tuple(sorted(acc)))
        return
    i = 0
    while i < NUM_KINDS and cnt[i] == 0:
        i += 1
    if i == NUM_KINDS:
        if jk == todo * 3:
            # pure-joker melds: resolve as triplets of unrestricted kinds is
            # ambiguous; canonicalise as triplet of the eye kind — handled
            # upstream by trying concrete kinds. Here mark wildcard triplet.
            out.add(tuple(sorted(acc + [((JOKER,) * 3, True)] * todo)))
        return
    c0 = cnt[i]
    if c0 >= 3:
        cnt[i] -= 3
        _enum_melds(cnt, jk, todo - 1, out, acc + [((i, i, i), True)], limit)
        cnt[i] += 3
    if c0 < 3 and jk >= 3 - c0:
        cnt[i] = 0
        _enum_melds(cnt, jk - (3 - c0), todo - 1, out,
                    acc + [((i, i, i), True)], limit)
        cnt[i] = c0
    if is_suited(i) and i % 9 <= 6:
        b, c = i + 1, i + 2
        for jb in (0, 1):
            if (jb and jk < 1) or (not jb and cnt[b] == 0):
                continue
            for jc in (0, 1):
                uj = jb + jc
                if jk < uj or (not jc and cnt[c] == 0):
                    continue
                cnt[i] -= 1
                if not jb: cnt[b] -= 1
                if not jc: cnt[c] -= 1
                _enum_melds(cnt, jk - uj, todo - 1, out,
                            acc + [((i, b, c), False)], limit)
                cnt[i] += 1
                if not jb: cnt[b] += 1
                if not jc: cnt[c] += 1


def enumerate_standard(counts, jokers, need_melds, joker_in_eye=True,
                       limit=200):
    """All (eye, melds) readings of the concealed part, jokers resolved."""
    if sum(counts) + jokers != need_melds * 3 + 2:
        return []
    readings = []
    for eye in range(NUM_KINDS):
        eye_opts = []
        if counts[eye] >= 2:
            eye_opts.append(0)
        if joker_in_eye and counts[eye] == 1 and jokers >= 1:
            eye_opts.append(1)
        for uj in eye_opts:
            counts[eye] -= 2 - uj
            melds = set()
            _enum_melds(counts, jokers - uj, need_melds, melds, [], limit)
            counts[eye] += 2 - uj
            for m in melds:
                readings.append((eye, m))
    if joker_in_eye and jokers >= 2:
        melds = set()
        _enum_melds(counts, jokers - 2, need_melds, melds, [], limit)
        for m in melds:
            readings.append((JOKER, m))  # wildcard eye
    # dedupe + SORT: cross-language determinism contract — 高點法 ties
    # must resolve to the same reading in Python and Dart, so iteration
    # order is canonical (eye asc, then melds lexicographic)
    seen, final = set(), []
    for r in readings:
        if r not in seen:
            seen.add(r)
            final.append(r)
    final.sort(key=lambda r: (r[0], r[1]))
    return final

# ── special forms (concealed hands; 17 tiles unless noted) ──────────────

def wins_liku(counts, jokers):
    """嚦咕嚦咕: 7 pairs + 1 triplet, fully concealed. 4-of-kind counts as
    two pairs. VERIFY-12."""
    if sum(counts) + jokers != 17:
        return False
    for t in range(NUM_KINDS):
        for real in (3, 2, 1):
            if counts[t] < real or (counts[t] - real) not in (0, 1, 2, 4):
                continue
            uj = 3 - real
            if jokers < uj:
                continue
            rem = counts.copy()
            rem[t] -= real
            rj = jokers - uj
            odd = sum(1 for c in rem if c % 2 == 1)
            if any(c == 3 for c in rem) or any(c > 4 for c in rem):
                continue
            if odd <= rj and (rj - odd) % 2 == 0:
                return True
    return False


def liku_pairs(counts):
    """Pair kinds of a joker-free liku win (for 三元/四喜/八對 detectors)."""
    for t in range(NUM_KINDS):
        if counts[t] >= 3:
            rem = counts.copy()
            rem[t] -= 3
            if all(c in (0, 2, 4) for c in rem):
                pairs = []
                for k in range(NUM_KINDS):
                    pairs += [k] * (rem[k] // 2)
                return t, pairs
    return None, None


def wins_thirteen_orphans(counts, jokers, n_melds):
    """十三么 (港式16張, VERIFY-11): 13 distinct 么九字 kinds + 1 extra
    orphan (eye) + one ordinary 面子 (may be an exposed meld — at most 1)."""
    if n_melds > 1:
        return False
    if sum(counts) + jokers != 17 - 3 * n_melds:
        return False
    cnt = counts.copy()
    jk = jokers
    for k in ORPHANS:
        if cnt[k] >= 1:
            cnt[k] -= 1
        elif jk:
            jk -= 1
        else:
            return False
    # eye partner: one more orphan (or joker)
    for k in ORPHANS:
        if cnt[k] >= 1:
            c2 = cnt.copy()
            c2[k] -= 1
            if _rest_is_one_meld(c2, jk, n_melds):
                return True
    if jk >= 1 and _rest_is_one_meld(cnt, jk - 1, n_melds):
        return True
    return False


def _rest_is_one_meld(cnt, jk, n_melds):
    rem = sum(cnt) + jk
    if n_melds == 1:
        return rem == 0
    if rem != 3:
        return False
    return _can_melds(cnt, jk, 1, {})


def wins_sixteen_disjoint(counts, jokers):
    """十六不搭: fully concealed; 16 pairwise-unconnected tiles, win tile
    pairs one of them. No jokers (VERIFY)."""
    if jokers or sum(counts) != 17:
        return False
    if sum(1 for c in counts if c == 2) != 1 or any(c > 2 for c in counts):
        return False
    kinds = [k for k in range(NUM_KINDS) if counts[k] >= 1]
    if len(kinds) != 16:
        return False
    for i, a in enumerate(kinds):
        for b in kinds[i + 1:]:
            if suit_of(a) == suit_of(b) and suit_of(a) <= 2 and b - a <= 2:
                return False
    return True

# ── top level ───────────────────────────────────────────────────────────

def win_forms(counts, jokers, n_melds, joker_in_eye=True):
    forms = set()
    if wins_standard(counts, jokers, 5 - n_melds, joker_in_eye):
        forms.add("standard")
    if n_melds == 0:
        if wins_liku(counts, jokers):
            forms.add("liku")
        if wins_sixteen_disjoint(counts, jokers):
            forms.add("sixteen")
    if wins_thirteen_orphans(counts, jokers, n_melds):
        forms.add("orphans")
    return forms


def winning_kinds(counts, jokers, n_melds, joker_in_eye=True):
    """All kinds t where hand+t wins — 聽牌 detection and 扇 counting."""
    outs = []
    for t in range(NUM_KINDS):
        if counts[t] >= 4:
            continue
        counts[t] += 1
        if win_forms(counts, jokers, n_melds, joker_in_eye):
            outs.append(t)
        counts[t] -= 1
    return outs

# ── shanten (L1 AI heuristic) ───────────────────────────────────────────

_BLOCK_CACHE = {}


def _block_options(key, suited):
    """Pareto-optimal (melds, partials, pair_used) decompositions of one
    suit block (or the honor block). Runs never cross suits, so blocks
    decompose independently; the module-level cache makes shanten fast
    across a whole game (hands repeat block patterns constantly)."""
    hit = _BLOCK_CACHE.get(key)
    if hit is not None:
        return hit
    out = set()
    cnt = list(key)
    n = len(cnt)

    def walk(i, m, p, pair):
        while i < n and cnt[i] == 0:
            i += 1
        if i == n:
            out.add((m, p, pair))
            return
        c0 = cnt[i]
        if c0 >= 3:                              # triplet
            cnt[i] -= 3
            walk(i, m + 1, p, pair)
            cnt[i] += 3
        if suited and i <= n - 3 and cnt[i + 1] and cnt[i + 2]:   # run
            cnt[i] -= 1; cnt[i + 1] -= 1; cnt[i + 2] -= 1
            walk(i, m + 1, p, pair)
            cnt[i] += 1; cnt[i + 1] += 1; cnt[i + 2] += 1
        if c0 >= 2:
            cnt[i] -= 2
            walk(i, m, p + 1, pair)              # pair-as-partial
            if not pair:
                walk(i, m, p, True)              # the eye
            cnt[i] += 2
        if suited:
            for d in (1, 2):                     # edge/gap partial
                j = i + d
                if j < n and cnt[j]:
                    cnt[i] -= 1; cnt[j] -= 1
                    walk(i, m, p + 1, pair)
                    cnt[i] += 1; cnt[j] += 1
        cnt[i] = 0                               # drop this kind
        walk(i + 1, m, p, pair)
        cnt[i] = c0

    walk(0, 0, 0, False)
    # shanten is monotone nonincreasing in each component ⇒ dominated
    # options can never win; prune them
    pruned = frozenset(
        o for o in out
        if not any(o2 != o and o2[0] >= o[0] and o2[1] >= o[1]
                   and o2[2] >= o[2] for o2 in out))
    _BLOCK_CACHE[key] = pruned
    return pruned


def shanten(counts, jokers, n_melds_exposed):
    """Standard-form shanten (0 = 聽牌, -1 = win-shaped). Each joker
    reduces by 1. Good enough for AI; legality uses exact win checks."""
    need = 5 - n_melds_exposed
    blocks = [_block_options(tuple(counts[0:9]), True),
              _block_options(tuple(counts[9:18]), True),
              _block_options(tuple(counts[18:27]), True),
              _block_options(tuple(counts[27:34]), False)]
    best = 99
    for am, ap, ax in blocks[0]:
        for bm, bp, bx in blocks[1]:
            for cm, cp, cx in blocks[2]:
                for dm, dp, dx in blocks[3]:
                    m = am + bm + cm + dm
                    p = ap + bp + cp + dp
                    useful = min(m, need)
                    partials = min(p, need - useful)
                    s = (need - useful) * 2 - partials \
                        - (1 if (ax or bx or cx or dx) else 0)
                    if s < best:
                        best = s
    return max(best - jokers, -1)
