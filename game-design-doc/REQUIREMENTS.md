# 10 · Requirements Specification
Formal, numbered, testable requirements distilled from docs 00–09. Every FR/NFR traces to a design doc section; every milestone gate references these IDs. **Priority:** P0 = must ship v1 · P1 = should ship v1 · P2 = post-launch acceptable.

---

## 1. Functional requirements

### F1 — Rules engine (`mj_core`) — see 02, 08

| ID | Requirement | Pri |
|---|---|---|
| FR-1.1 | Implement full 港式十六張新章 per the 總例 PDF: 144 tiles, 16-tile hands, 執位/開門/配牌/補花, 局 state machine `DEALING → SWAP → TIN_WINDOW → TURN_LOOP → HAND_END` (02 §3). | P0 |
| FR-1.2 | Support all actions: 上/碰/暗槓/加槓/大明槓/搶槓/叮/食糊/自摸/過, with claim priority 食 > 碰/槓 > 上 and 雙響/三響 multi-winner resolution (02 §3–4). | P0 |
| FR-1.3 | Enforce 過水: after declining a winnable tile, block winning until own next discard; if 叮-ed, block for the rest of the 局. The blocked 食 button must show a reason tooltip (02 §4). | P0 |
| FR-1.4 | Implement 叮 system: declaration, 90° rotated discard, hand lock (no swap/鳴牌/槓), 叮+5 / 即食+5 / 天叮40 / 地叮30 / 人叮20, 天叮 window closing at dealer's first draw (02 §2.2, §4). | P0 |
| FR-1.5 | Implement flowers: auto-expose + 槓尾 replace; 七搶一 and 兩台花 with instant-claim-vs-continue choice modal (10 s timer, default claim) (02 §5). | P0 |
| FR-1.6 | Dealership: 連莊/拉莊N on dealer win or 流局; pass counter-clockwise on 閒家 win; 拉N莊 adds 2N番 to dealer wins AND losses (02 §6). | P0 |
| FR-1.7 | Client offers only legal actions; server re-validates every intent (blocked-move policy D8 — no 詐糊/相公 possible) (02 §7). | P0 |
| FR-1.8 | Expose the configurable rule surface of 02 §8 (min 番, claim timer 3/5/8 s, 執位 mode, 東 count, 中途獎勵, 即食, 天叮, 花糊 instant claim, auto-pass, 聽牌 helper) as room options. | P0 |
| FR-1.9 | Deterministic engine: same seed + same intent sequence ⇒ byte-identical event log, local or remote (08 §7-1). | P0 |

### F2 — Scoring (`FanRecognizer` / `FanTable` / `Settlement`) — see 03

| ID | Requirement | Pri |
|---|---|---|
| FR-2.1 | Ship `fan_table.json` transcribed and human-verified against 總例 p.18 番種簡表 (~150 entries). **This is the M1 gate.** | P0 |
| FR-2.2 | FanRecognizer scores any WinContext: all-reading decomposition, joker branching, 不複合 suppresses graph, 單式結算 (<50 % shared 面子), 高點法, 嚦咕兩食, formula 番種 (拉莊 2n, 尾牌連摸 5×2ⁿ) (03 §2). | P0 |
| FR-2.3 | Recognizer output is itemized: per-番種 id, name, value, contributing tiles (for UI highlight) + total (03 §2). | P0 |
| FR-2.4 | Settlement: 全銃制 (出銃 pays full; 自摸 ×3), dealer ±(1+2N)番, 雙響/三響 independent settles, 中途獎勵 instant payouts with 1底 = 5分 (03 §3). | P0 |
| FR-2.5 | LaLedger (拉/踢半): record-not-pay, ×1.5 compounding round-up, 踢半 half round-down, 三口斬拉 prompt, 自摸 resolves all pairs; room toggle default ON (03 §4). | P0 |
| FR-2.6 | Ledger conservation invariant: Σ(all deltas incl. recorded) = 0 every hand, enforced in CI (08 §7-4). | P0 |
| FR-2.7 | Every 總例 worked example (§11, §13) passes as a named unit test; golden corpus ≥100 hands at M2 (03 §2). | P0 |
| FR-2.8 | Match-end handling of outstanding ledgers: **wipe (no settle)** — decided 2026-07-07. Implemented as config `laLedger.matchEndPolicy` (values wipe/full/half) so tables can differ later; official preset = wipe (03 §5). | P1 |

### F3 — Game modes — see 04

| ID | Requirement | Pri |
|---|---|---|
| FR-3.1 | 百搭 mode: +4 or +8 dedicated joker tiles substituting any tile; sub-options for eye/meld/discard legality per 04; joker-aware 聽/糊 detection everywhere (swap UI greys jokers). | P0 |
| FR-3.2 | 換牌 mode: 換三張 classic, 骰子換牌 (dice→count map, host-editable), 自定義; blind simultaneous exchange; SWAP state after 補花, before TIN_WINDOW (08 §5-D). | P0 |
| FR-3.3 | Both modes are independent room toggles chosen before room creation; any combination (incl. both) must work. | P0 |

### F4 — FanTable editor & presets — see 04–05

| ID | Requirement | Pri |
|---|---|---|
| FR-4.1 | Per-番種 value stepper + enable toggle; formula entries expose coefficient; `requires` chains hide dependents; official preset immutable (03 §1). | P0 |
| FR-4.2 | Live preview: editing re-scores a sample hand instantly via the same FanRecognizer (08 §5-B). | P1 |
| FR-4.3 | Presets stored in Firestore; wizard freezes a full copy into the room doc; lobby/table shows diff-vs-official chip (08 §3). | P0 |
| FR-4.4 | Editor sanity invariant: disabling any 番種 never raises any hand's total (08 §7-3). | P0 |

### F5 — Multiplayer — see 06

| ID | Requirement | Pri |
|---|---|---|
| FR-5.1 | Friends-only private rooms, 4 seats, 6-char room code + QR share; no matchmaking. | P0 |
| FR-5.2 | Server-authoritative online play: game service runs `mj_core`; clients receive per-seat filtered events only (08 §7-2). | P0 |
| FR-5.3 | Disconnect: 30 s presence miss → AI takeover with same FilteredView; reconnect via stateSnapshot + live stream resume; AI badge UX (08 §5-C). | P0 |
| FR-5.4 | Fairness: wall seed disclosed at hand end for audit (06). | P1 |

### F6 — AI players — see 07

| ID | Requirement | Pri |
|---|---|---|
| FR-6.1 | AI fills any empty/abandoned seat; three difficulty tiers L1–L3; L2/L3 read the room's frozen FanTable for hand-value planning. | P0 (L1–L2), P1 (L3) |
| FR-6.2 | AI consumes only the FilteredView API — structurally cannot cheat (08 §7-5). | P0 |
| FR-6.3 | AI respects 叮-lock, 過水, and all mode rules (joker-aware shanten). | P0 |

### F7 — UI/UX — see 01, 05

| ID | Requirement | Pri |
|---|---|---|
| FR-7.1 | Screens: home, 3-step room wizard, lobby, table (Flame), win overlay, editor, 圖鑑, match log/replay, settings. | P0 (圖鑑/replay P1) |
| FR-7.2 | Win overlay: fanned hand, cascading itemized 番種 rows with tile highlights, count-up, settlement panel with 拉-recorded shown as chained (03 §5). | P0 |
| FR-7.3 | 茶餐廳/麻雀館 style per 01: locked palette, Noto Sans TC, motion vocabulary ≤400 ms. | P0 |
| FR-7.4 | All timed choices (claims, 花糊, 斬拉) have visible countdowns and safe defaults. | P0 |

### F8 — Audio · F9 — Content · F10 — Replay/log

| ID | Requirement | Pri |
|---|---|---|
| FR-8.1 | Cantonese voice pack (≥1 M/F, 9 lines), ~20 SFX, lobby + in-game BGM per 09 §6; per-channel volume settings. | P0 (1 pack), P1 (2nd) |
| FR-9.1 | 圖鑑: card per 番種 with example hand, official vs current-preset value (08 §3). | P1 |
| FR-9.2 | Rules reference written entirely in own wording — decided 2026-07-07 (closes Risk R1): no verbatim 總例 text or table reproduction ships in-app; fan_table.json stores only names + numeric values. | P0 |
| FR-10.1 | Match log with per-局 replay by re-emitting the stored event log (08 §2). | P1 |

## 2. Non-functional requirements

| ID | Requirement | Pri |
|---|---|---|
| NFR-1 | **Performance:** shanten/legal-move calc < 5 ms on mid-range Android; recognizer full decomposition < 50 ms; steady 60 fps table scene; cold start < 3 s. | P0 |
| NFR-2 | **Determinism/consistency:** the five invariants of 08 §7 run in CI on golden corpus + fuzzed self-play; any failure blocks merge. | P0 |
| NFR-3 | **Security:** all game state server-side online; per-seat filtering; Firestore rules deny cross-room reads; no client-trusted scoring. | P0 |
| NFR-4 | **Reliability:** reconnect within one claim window loses nothing; LedgerState persisted in room doc survives service restart (08 §4). | P0 |
| NFR-5 | **Offline:** full single-player vs AI works with zero network (LOCAL adapter). | P0 |
| NFR-6 | **Localization:** 繁體中文 only v1; all strings externalized so future locales are additive. | P0 |
| NFR-7 | **Accessibility:** min touch target 48 dp; colour-blind-safe suit distinctions (glyph, not colour alone); text scale support in meta UI. | P1 |
| NFR-8 | **Compliance (Play Store):** IARC questionnaire — no real-money gambling, no simulated-gambling monetization (free app, no IAP); privacy policy URL; data-safety form matches Firebase usage; target latest API level. | P0 |
| NFR-9 | **Licensing:** all fonts embedding-licensed (Noto OFL verified; display face checked before build); rules text own-worded (R1); all art original. | P0 |
| NFR-10 | **Footprint:** initial APK/AAB ≤ 60 MB; audio/atlas budgets per 09. | P1 |
| NFR-11 | **Cost:** Firebase free-tier friendly at v1 scale (friends-only rooms); no always-on server outside active rooms. | P1 |
| NFR-12 | **Testability:** every rule toggle of 02 §8 and every 番種 detector individually unit-testable; self-play harness (07 §5) runs headless in CI. | P0 |

## 3. Traceability & gates

- **M1 gate:** FR-2.1 (verified fan_table.json) + FR-1.9 skeleton.
- **M2 gate:** FR-2.2–2.7, FR-1.1–1.6 complete with golden corpus green.
- **M3 gate:** FR-7.x local play vs AI (FR-6.1 L1) — playable build.
- **M4 gate:** FR-3.x, FR-4.x modes & editor.
- **M5 gate:** FR-5.x online; NFR-2/3/4 verified under fault injection.
- **M6 gate:** NFR-8/9 store compliance, asset list (see `asset-list.xlsx`) 100 % Done for P0 rows.

**Open decisions:** none — R1 (own-worded rules) and FR-2.8 (wipe) both closed 2026-07-07. Remaining verification items are the VERIFY-1…10 rule-detail questions in `data/VERIFICATION-fan-table.md`.
