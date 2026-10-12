"""Tile kinds and id mapping — Python reference of mj_core (lib/src/tile.dart).

Kind indices (34 playing kinds + joker):
  0-8   W1-W9 萬
  9-17  T1-T9 筒
  18-26 S1-S9 索
  27-30 FE FS FW FN 東南西北
  31-33 DC DF DB 中發白
  34    J0 百搭 (joker)
Flowers (X1-X8) are not hand tiles; they live in a separate flower zone.
"""

W, T, S = 0, 9, 18
WIND, DRAGON = 27, 31
JOKER = 34
NUM_KINDS = 34  # playing kinds excluding joker

_WINDS = ["FE", "FS", "FW", "FN"]
_DRAGONS = ["DC", "DF", "DB"]

def kind_to_id(k: int) -> str:
    if k < 9: return f"W{k + 1}"
    if k < 18: return f"T{k - 8}"
    if k < 27: return f"S{k - 17}"
    if k < 31: return _WINDS[k - 27]
    if k < 34: return _DRAGONS[k - 31]
    return "J0"

def id_to_kind(tid: str) -> int:
    c = tid[0]
    if c == "W": return int(tid[1]) - 1
    if c == "T": return 9 + int(tid[1]) - 1
    if c == "S": return 18 + int(tid[1]) - 1
    if c == "F": return 27 + _WINDS.index(tid)
    if c == "D": return 31 + _DRAGONS.index(tid)
    if c == "J": return JOKER
    raise ValueError(tid)

def suit_of(k: int) -> int:
    """0=W 1=T 2=S 3=wind 4=dragon."""
    if k < 27: return k // 9
    return 3 if k < 31 else 4

def rank_of(k: int) -> int:
    """1-9 for suited; 1-4 winds; 1-3 dragons."""
    if k < 27: return k % 9 + 1
    return k - 26 if k < 31 else k - 30

def is_suited(k: int) -> bool: return k < 27
def is_honor(k: int) -> bool: return 27 <= k < 34
def is_terminal(k: int) -> bool: return k < 27 and k % 9 in (0, 8)
def is_orphan(k: int) -> bool:  # 么九+字: the 13 orphan kinds
    return is_terminal(k) or is_honor(k)

ORPHANS = [k for k in range(NUM_KINDS) if is_orphan(k)]
assert len(ORPHANS) == 13
