# 04 · Game Modes, Options & Preset System

The base game (02+03) is always 港式台牌. 百搭 and 換牌 are **room toggles** chosen in room setup, both OFF by default. All options + the FanTable form a **RulePreset**.

---

## 1. 百搭 mode (D2)

**Core:** adds 4 or 8 dedicated 百搭 tiles to the wall (148/152 tiles). Every joker is **universal** — substitutes any 數牌/字牌 (never a flower).

Sub-options (defaults chosen for cleanest play; all stored in preset):
| Option | Values | Default |
|---|---|---|
| Joker count | 4 / 8 | 4 |
| Joker as 眼 | allow / forbid | allow |
| Joker in 鳴牌 (上/碰/槓) | allow / forbid | **forbid** — claims stay verifiable, hands stay honest |
| Discard joker | forbid (blocked) / allow-as-dead (unclaimable, unwinnable) | forbid |
| Joker in 特殊形 (十三么 etc.) | allow / forbid | allow |
| 淨百搭 bonus (win with 0 jokers) | 0–20番 | 0 (off) — appears as an added FanTable row when mode on |

Mechanics detail:
- Deal/draw: jokers behave as normal hand tiles; never auto-exposed.
- 聽牌/叮/過水 computations treat jokers as wildcards (a joker in hand usually widens waits — 叮 remains available; wait set shown in helper accounts for substitutions).
- Scoring: recognizer assigns each joker the substitution maximizing 高點法 total (03 §2). A joker standing in for the winning tile is fine; 搶槓 unaffected (you can't 加槓 with a joker when melding-with-joker is forbidden).
- 尾牌/海底 etc. unaffected. Flowers unaffected.
- AI: joker-aware shanten (07).

## 2. 換牌 mode (D3)

Runs in the SWAP state: after 配牌+補花, **before** 天叮 window. Flowers & 百搭 tiles not swappable. Blind simultaneous exchange; selection timer 15 s (AI/timeout picks most-isolated tiles).

Sub-modes:
1. **換三張 (classic):** everyone passes exactly 3; same-suit constraint toggle (default ON); direction by dealer dice — odd = 逆時針 (下家), even = 順時針 (上家), triple = 對家; dice animation announces it.
2. **骰子換牌 (original design):** dealer rolls 2 dice; swap count = mapping of the total — default map: 2–4→2張, 5–9→3張, 10–12→4張 (host-editable table 0–5); direction by the same odd/even/triple rule; same-suit constraint default OFF.
3. **自定義:** host fixes count (0–5) + direction.

Edge rules: everyone swaps the same count (fairness); received tiles enter hand before 天叮 window opens; a player dealt fewer usable tiles than the count must still pass (any tiles legal unless same-suit ON and impossible — then constraint auto-relaxes for that player with a table notice). ⚠️ Mode 2 has no real-world precedent — playtest at M4 and tune the default map.

## 3. Room options (full surface)

**Rules:** preset choice → FanTable edits · 拉/踢半 on/off (default ON) · min 番 to win · 中途獎勵 · 天叮/即食 windows · 花糊 instant claim.
**Modes:** 百搭 block (§1) · 換牌 block (§2).
**Pace:** claim timer 3/5/8 s · turn timer 10/15/30 s · 執位 full/quick · match length 1圈/1東/2東 · animation speed.
**Aids:** 聽牌 helper on/off (host-level — info advantage) · discard safety hints off/on (beginner rooms).
**Table:** theme · voice pack per seat · canned-chat on/off.

## 4. RulePreset system

- Preset = `{fanTable, options}` snapshot. Built-ins: 「協會新章」 (locked, exactly the 總例) · 「新手場」 (helpers on, 拉 off, slower timers) · 「百搭歡樂場」 (百搭4, 換三張 on).
- Host flow: pick preset → optional edit (opens editor, 05 §5) → save-as under own account (max 20) → create room. Room stores a **frozen copy**; mid-match edits impossible; lobby shows a diff-vs-official summary card so joiners see house rules at a glance (e.g. 「清么 420→200 · 拉/踢半 ON · 百搭×4」).
- Integrity: clients receive the frozen preset at join; server scores with its own copy (client copy is display-only).
- Roadmap: shareable preset codes, community preset browser.
