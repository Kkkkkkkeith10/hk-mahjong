# 03 · Scoring & Settlement Design
**Modules:** FanRecognizer · FanTable (data) · Settlement · LaLedger

---

## 1. FanTable (data-driven scoring)

Single JSON asset `fan_table.json` (transcribed & verified from 總例 p.18 番種簡表 — M1 task), one entry per 番種:

```json
{
  "id": "moon_ting", "name": "門叮", "category": "action",
  "value": 15, "editable": true, "enabled": true,
  "formula": null,            // or {"type":"linear","coef":2}  (拉莊 2n)
                              // or {"type":"geometric","base":5} (尾牌連摸 5×2^n)
  "suppresses": [],           // 不複合: ids absorbed when this scores
  "requires": ["ting"],       // hidden if dependency 番種 disabled
  "stacksWith": ["men_qing_note"],  // documented explicit exceptions
  "detector": "moon_ting"     // recognizer function key
}
```

~150 entries across categories: action (叮/門清/自摸/門叮/門摸/即食/海底/搶槓/花摸/槓摸/尾牌連摸/雙響/三響/槓) · composition (無字/字牌/正字/無花/花牌/正花/無字花/一台花) · wait (對碰/假獨/獨獨/將眼) · dealer (莊家/拉莊) · sequence families (平糊/大平/老少順/相逢系/同順系/龍系/步高系 雜清×3-5步×明暗/連環套/金門橋/般高系) · triplet families (對對糊/坎坎糊/暗刻系/同刻系/連刻系/老少刻) · honor-terminal-suit (四喜/三風/三元/字一色/么系/滿庭芳/缺系/門系/混清一色/歸系) · special forms (嚦咕系/連對系/不搭系/十三么系/天地人糊/子系/天地人叮/大雞大鴨/求人系/七搶一/八仙過海).

Editing (F4): value stepper + on/off per entry; formula entries expose coefficient; `requires` chains hide dependents; preset = full FanTable copy + options block. Official preset immutable.

## 2. FanRecognizer

Input `WinContext`: 17-tile hand (+jokers), melds w/ open/concealed + claimed-tile position, flowers, seat/圈 winds, win method (自摸/出銃/搶槓), source player, 叮 state + 巡 counters, wall state (海底/尾牌), 槓-continuation flags (槓摸/花摸), dealer & 拉莊N, simultaneous-win count.

Pipeline:
1. **Decompose** hand into all valid readings (基本形 partitions; special-form checks run in parallel). Jokers branch the search (see 04 §joker scoring); prune with memoization + iterative deepening (R4).
2. **Score each reading:** run detectors → candidate 番種 set → apply `suppresses` graph (不複合原則) → apply 單式結算 (two meld-pattern 番種 co-score only if shared 面子 < 50% of either) → sum.
3. **高點法:** take max reading. **嚦咕兩食:** if readable as 基本形 AND 嚦咕形, score both per 總例 §12 and sum (shared-base exclusions). 大雞/大鴨 excluded from 高點法 override per 總例 §10.
4. Output: itemized list (id, name, value, contributing tiles for UI highlight) + total.

Testing: golden corpus (≥100 hands at M2, grows forever); property tests — disabling any 番種 never raises a total; every 總例 worked example (§11 例1–3, §13 examples) is a named test.

## 3. Settlement (per 局)

- 出銃: discarder owes winner the full total. 自摸: each of 3 players owes full total. No cap, no 包牌.
- Dealer adjustments (莊家1 + 拉莊2N) apply to dealer's wins and losses.
- 雙響/三響: each winner settles independently vs the same discarder (+5/+10番 each).
- 中途獎勵 (settle **instantly**, bypass LaLedger). Unit: **1底 = 5分** (derived from the 總例: 七搶一 = 6底 = 30分; 兩台花 = 8底 = 40分). 暗槓 = 1底(5分) from each player; 七搶一 = 30分 from the flower-drawer; 兩台花 = 40分 from each.
- Output: `SettlementDelta[]` (from, to, amount, reason) → consumed by LaLedger or applied directly.

## 4. LaLedger (拉/踢半) — room toggle, default ON

State: map of ordered pairs `(creditor A → debtor B): {amount, kou}` persisting across 局 within a match.

On each win event, per affected pair:
| Event | Effect |
|---|---|
| A wins off B (no ledger) | record amount, kou=1 — **not paid** |
| A wins off C, or B 出銃 to C | A **collects** recorded A→B amount, ledger clears |
| A wins off B again, or A 自摸 | recorded = recorded × 1.5 (round **up**) + new amount; kou+1 (拉兩口/三口…) |
| B wins off A, or B 自摸 | B pays **half** recorded (round **down**, 踢半), ledger clears |
| kou ≥ 3 | before next 局's dice, B may 斬拉: settle full recorded amount, stop compounding |

自摸 by X resolves every pair involving X (collect all X-held ledgers per rule c; every ledger held against X resolves per rule d — 踢半). ⚠️ Simultaneous multi-winner + ledger combos: resolve winners in seat order from discarder's 下家; **spec each edge case as unit tests during M2 and confirm ambiguous ones with experienced players (Risk R2).**

Toggle OFF → SettlementDelta applied immediately every 局.

UI: persistent ledger strip (avatar→avatar, amount, 口 dots); gold-chain animation on record, chain-break on 踢半; 斬拉 prompt modal between hands; full history in match log.

## 5. Score presentation

Win overlay: winning hand fanned + claimed/自摸 tile highlighted → 番種 rows cascade (name · value · tile highlights on tap) → total count-up (brass ticks; gong ≥ 100番) → settlement panel (who pays what; 拉-recorded amounts shown as chained, not paid) → continue button (host or 8 s auto).
Match end: table of per-player totals, per-局 log (tap → replay that hand's 番 breakdown), outstanding ledgers are **wiped (no settle)** at match end — recorded 拉 amounts that never resolved are cancelled and shown struck-through in the match-end ledger panel. (DECIDED 2026-07-07, Keith. Config point `settlement.laLedger.matchEndPolicy = "wipe"` in `data/fan_table.json`; alternatives full/踢半 stay implementable behind the same config.)
