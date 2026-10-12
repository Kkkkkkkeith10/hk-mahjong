# 港式台牌 — Full Game Feature Plan
**Project:** Multiplayer 港式台灣牌 mahjong game for Google Play
**Stack:** Flutter + Flame · Firebase backend · 繁體中文 UI
**Date:** 2026-07-07 · **Basis:** RESEARCH-mahjong-game-modes.md + 香港麻雀協會《港式十六張新章麻雀總例》(2025-07-28)

---

## 1. Locked decisions (from Keith)

| # | Decision |
|---|---|
| D1 | Base game: 港式十六張新章 per the 協會總例 rulebook (the uploaded PDF is the source of truth) |
| D2 | 百搭 = **additional 4 or 8 dedicated joker tiles**, each substitutes **any** tile; room toggle before setup |
| D3 | 換牌 = opening swap, multiple modes incl. dice-decided swap count; room toggle before setup |
| D4 | Editable 番表: players can edit the scoring table themselves (per-room rule presets) |
| D5 | Multiplayer: **friends-only private rooms**, room-code join, 4 players per table |
| D6 | AI players (fill empty seats + offline play) |
| D7 | 拉/踢半 settlement: room toggle, **default ON** |
| D8 | No penalty simulation — the app **blocks illegal moves** (no 黃牌/紅牌/詐糊 system in v1) |
| D9 | Free app, **no monetization** in v1 |
| D10 | 繁體中文 only in v1 |
| D11 | Engine: Flutter/Flame; backend: Firebase (fits private-room, turn-based play) |

Out of scope for v1: public matchmaking/ranking, 3-player mode, real-money anything, tournament referee mode, English UI, HK 13-tile 舊章, Vietnamese-hierarchy jokers (D2 supersedes: all jokers are universal).

---

## 2. Game concept in one paragraph

An authentic digital 港式台牌 (HK-style 16-tile mahjong) for playing with friends: create a private room, tune your table's house rules — every 番種 value is editable, 拉/踢半 on or off, add 百搭 joker tiles, add a 換牌 opening swap — invite 1–3 friends with a room code, and AI fills any empty seat. Nothing on the Play Store offers editable 番表, 拉/踢半, 百搭 toggles, or 換牌 modes; this is the "digitize YOUR table" app.

---

## 3. Feature list (summary)

**F1 Core rules engine** — full 總例 implementation: deal, 補花, turn flow, 上/碰/槓/搶槓, 叮牌, 過水, 食糊 validation (基本形 + 嚦咕嚦咕/十三么/十六不搭), 流局, 連拉莊.
**F2 Scoring engine** — ~150 番種 recognizer, 高點法 / 單式結算 / 不複合原則, 全銃/自摸收三家, 中途獎勵.
**F3 拉/踢半 ledger** — cross-hand recorded scores, ×1.5 compounding, 踢半, 斬拉; room toggle (default ON).
**F4 Editable 番表** — in-app editor: enable/disable and re-value every 番種, formula items (拉莊 2n, 尾牌連摸 5×2ⁿ), saved as named rule presets per room host.
**F5 百搭 mode** — room toggle: +4 or +8 universal joker tiles; joker rules configurable (eye, melds, discard, 淨百搭 bonus).
**F6 換牌 mode** — room toggle: opening swap with selectable sub-modes (換三張 fixed / dice-count / host-defined).
**F7 Private rooms & multiplayer** — create/join by 6-char code, host = rule owner, reconnect handling, server-authoritative state.
**F8 AI players** — 16-tile shanten + heuristics, joker-aware, 3 difficulty levels; fills seats, takes over on disconnect, powers offline mode.
**F9 Game UI/UX** — table scene (Flame), hand interaction, claim prompts with timers, 叮 declaration, win reveal with 番 breakdown, 拉 ledger display.
**F10 Meta screens** — home, room setup wizard, rule-preset manager, 執位 ceremony (optional animation), round scoreboard + end-of-東 summary, settings, how-to-play reference (the 番種表 as in-game encyclopedia).

Sections 4–13 detail each feature. Section 14 = asset list. Section 15 = architecture. Section 16 = data model. Section 17 = roadmap. Section 18 = Play Store checklist. Section 19 = risks.

---

## 4. F1 — Core rules engine (per 總例)

### 4.1 Tiles & setup
- 144 tiles: 萬/筒/索 1–9 ×4 (108) + 東南西北 ×4 (16) + 中發白 ×4 (12) + 8 flowers (春夏秋冬梅蘭菊竹 ×1). With 百搭 ON: +4 or +8 joker tiles → 148/152 total.
- 執位 (seat ceremony): optional animated version of the 總例 procedure (draw 東南西北一筒二筒 + 3-dice 數骰位, odd/even → 一筒/二筒 direction); quick mode = random seats. Runs at the start of every 東 (4 圈).
- 開門: dealer rolls 3 dice → 開門人 + break point; 槓尾 (dead wall) at the break; wall drawn clockwise, turns counter-clockwise. Quick mode skips the animation but keeps the same random distribution.
- 配牌: 4×4-tile blocks → 16 tiles each; dealer draws the 17th tile as first draw; 補花 in strict seat order, multiple rounds; 天叮 window after 補花 before dealer's first discard (+40番).

### 4.2 Turn flow & claims
- Draw → (optional 暗槓/加槓 → 補槓 from 槓尾) → discard. Flower drawn → expose + replace immediately.
- 上 (chow): from upper player only; claimed tile displayed in the middle of the meld.
- 碰: from anyone; 同一巡 cannot re-碰 a tile someone declined.
- 槓: 暗槓 (face-down, revealed at hand end; pays 中途獎勵 1底/家 instantly), 加槓 (exposed pung + 4th tile; vulnerable to 搶槓), 大明槓 (discard + concealed triplet). All 補槓 from 槓尾 then discard.
- 搶槓: win on an 加槓 tile only (not 暗槓; exception: none — 十三么 explicitly may NOT rob 暗槓 either, per 總例). Counts as the 加槓 player discarding.
- 鳴牌優先: 食糊 > 碰/槓 > 上. Simultaneous wins allowed: 雙響 +5番 / 三響 +10番 each; if discarder is dealer, all winners count 莊家/拉莊.
- Claim windows: app shows actionable buttons (食/碰/槓/上/過) with a room-configurable timer (default 5 s); auto-過 on timeout. Engine resolves priority automatically.

### 4.3 叮牌 (ready declaration)
- Any 聽牌 player may declare 叮; their 叮-discard is rotated 90° on the river.
- Locked after 叮: no hand changes, no 上/碰/槓 (including 暗槓), win only.
- Scoring hooks: 叮 +5番; 即食 (win within one 巡 of 叮, cancelled if any 鳴牌/暗槓 intervenes) +5番; 天叮 40 / 地叮 30 / 人叮 20番.
- UI: 叮 button appears only when 聽牌; after 叮 the app auto-plays drawn non-winning tiles (with a brief cancel window — see F9).

### 4.4 過水 (sacred discard)
- Pass on a winning tile (self-drawn win declined can't happen digitally — applies to discards and declined 自摸? Per 總例: 同一巡 no win after passing; after 叮, passing → cannot win rest of the hand).
- Engine tracks 過水 state per player; win button greyed with reason shown. 加槓 tile passed while 聽 also triggers 過水.

### 4.5 花糊 & 中途獎勵 (instant payouts)
- 七搶一: player holds 7 flowers, another draws the 8th → may claim 30分 from that player instantly (or 照補花 and continue; flower value stacks with later win, 該點拉落下一鋪).
- 兩台花: own 8 flowers → 40分 from each player, or continue playing (八隻花 counts 40番 if hand completes).
- 暗槓: 1底 from each player immediately.
- These payouts bypass the 拉 ledger (settled instantly).

### 4.6 食糊 validation & hand forms
- 基本形: 5 面子 + 1 眼 (17 tiles).
- 特殊形: 嚦咕嚦咕 (7 pairs + 面子 structure per 總例 display rules), 十三么, 十六不搭. All included by default (rulebook-official).
- Illegal win attempts are simply impossible: the 食 button only appears when the hand genuinely wins (D8) — 詐糊/空糊 can't occur.

### 4.7 流局 & dealership
- Wall exhausted (to 槓尾) → 流局: no scores, dealer stays, 拉莊數 +1.
- 連拉莊: dealer +1番 base; at 拉N莊, dealer's wins/losses add 2N番; any non-dealer win resets to 0. On-table indicator (拉N tag at dealer's corner, mirroring the 總例's physical marker).
- 一輪 = 四圈 (one 東); room can be set to 1東/2東/unlimited. 70-min timer optional (off by default in casual rooms).

### 4.8 Blocked-not-punished principle (D8)
Everything the 總例 punishes (相公, 摸錯牌, 違規公開, 做錯莊, 食換, 改鳴…) is procedurally impossible in-app. No penalty engine in v1. (Roadmap: optional "strict mode" later.)

---

## 5. F2 — Scoring engine

### 5.1 番種 recognizer
- Input: winning hand (melds, eye, flowers, win context flags: 自摸/出銃, 叮 state, 巡 counters, wall position, 槓 events, joker usage).
- Output: itemized 番 list + total. Every 番種 from the 番種簡表 (p.18 of the PDF, ~150 items across categories: action 番, tile-composition 番, wait 番, sequence families 步高/相逢/龍/金門橋/連環套, triplet families 連刻/同刻/暗刻, honor/terminal families, 歸 family, special forms 嚦咕/不搭/十三么, 天地人糊, 求人, flower hands).
- ⚠️ Build step: transcribe the 番種簡表 into `fan_table.json` **verified line-by-line against the PDF** (research doc's transcription is draft).

### 5.2 Computation rules (總例 §分數計算/食糊的計分)
- 高點法: enumerate all readings of the hand, score each, take the highest (except 嚦咕兩食 & 大雞/大鴨 special handling).
- 單式結算: two meld-pattern 番種 both count only if shared melds < 50% of either pattern's melds.
- 嚦咕兩食: hand readable as both 基本形 and 嚦咕形 → score both and sum (shared 底/嚦咕/般高-class exclusions per 總例 §12).
- 不複合原則: a 番種 that *necessarily* implies a cheaper one absorbs it (不搭不計五門, 嚦咕不另計門清, 四步高不加三步高…); exceptions where co-occurrence is not necessary DO stack (門叮 = 門清5 + 叮15 = 20番 ✓; special forms stack with 門叮/門摸; 八歸/十二歸 add 四歸). Implemented as an implication graph in the fan table data (each 番種 lists `suppresses:[...]`, `stacksWith:[...]`).
- Settlement: 全銃 (discarder pays full hand value), 自摸 → ×3 collected (full value from each), no cap, no 包牌.

### 5.3 Score display
Win screen shows the sorted 番 itemization (name + value + highlight of qualifying tiles), total, payer(s), and the 拉 ledger effect (recorded vs collected).

---

## 6. F3 — 拉/踢半 ledger (room toggle, default ON)

- State: per ordered player-pair (A→B), a recorded amount + 口 count, persisting across hands within a match.
- Transitions (per 總例): A wins off B → record, don't settle. Then:
  (a) A wins off anyone else, or B deals into someone else → A **collects** the recorded amount;
  (b) A wins off the other two → their scores also recorded (independent pair ledgers);
  (c) A wins off B again or A 自摸 → recorded ×1.5 + new score, 口+1 (拉兩口/三口…);
  (d) B wins off A or B 自摸 → B pays **half** the recorded amount (踢半) and the ledger clears.
- Rounding: 拉 rounds up, 踢半 rounds down (benefit to the 食糊者).
- 斬拉: at 拉三口+, the losing player gets a "斬拉" prompt before the next hand's dice — settles and stops compounding.
- 自摸 interaction: A 自摸 triggers (c) against every player A has a ledger on, and (d) for every ledger held against A — engine resolves all pairs each win. ⚠️ Edge cases (multiple simultaneous winners, 自摸 with ledgers in both directions) need a written spec + exhaustive unit tests; ambiguities resolved by asking Keith / HKMA convention.
- UI: persistent compact ledger widget (who 拉s whom, amount, 口 count); tapping opens history. Toggle OFF → every win settles instantly.

---

## 7. F4 — Editable 番表 (the differentiator)

- **Preset system**: a rule preset = 番表 + game options. Ships with `協會新章 (official)` locked preset; host can clone → edit → save named presets (e.g. "屋企規矩").
- **Editor UI**: 番種 list grouped by the table's categories; search; per item: on/off switch + value stepper; formula items expose their parameter (拉莊 2n → coefficient; 尾牌連摸 5×2ⁿ → base/cap); "reset to official" per item and globally.
- **Guard rails**: values 0–999; dependency warnings when disabling a 番種 that others reference (e.g. disabling 叮 hides 門叮/即食/天地人叮); preview panel shows a sample hand re-scored live.
- **Beyond 番 values, the preset also stores** (all room options): 拉/踢半 on/off, 百搭 config (off/4/8 + joker sub-rules), 換牌 config, claim timer, 東 count, 執位 full/quick, 中途獎勵 on/off, 過水 strictness, 即食/天叮 windows.
- Storage: JSON preset docs under the host's profile in Firestore; room references a frozen copy at creation (mid-game rule edits impossible).
- v1 sharing: presets are per-account only (shareable preset codes = roadmap).

---

## 8. F5 — 百搭 mode (room toggle)

- Adds **4 or 8 dedicated 百搭 tiles** (distinct tile face) to the wall; each substitutes **any** tile (D2 — universal jokers, no Vietnamese hierarchy).
- Sub-options (stored in preset, sensible defaults):
  - Joker count: 4 / 8 (default 4).
  - Joker as 眼 (pair): allow / forbid (default allow — universal means universal).
  - Joker in 鳴牌 (上/碰/槓): allow / forbid (default forbid — keeps claims verifiable and matches common HK table practice).
  - Discarding a joker: forbidden (default; auto-blocked) / allowed-as-dead-tile.
  - 淨百搭 bonus: +N番 for winning with zero jokers (default off; editable in 番表 as a new 番種 row).
- Scoring with jokers: recognizer assigns each joker the substitution that yields the 高點法 maximum. 特殊形 (十三么 etc.) with jokers allowed by default, toggleable.
- Interaction with flowers: jokers are hand tiles, not flowers; 補花 unaffected.
- AI must be joker-aware (F8).

## 9. F6 — 換牌 mode (room toggle)

Runs after 配牌+補花, before 天叮 window and dealer's first discard. Sub-modes:
1. **換三張 (classic)** — everyone secretly picks 3 tiles (same-suit constraint toggle, default ON); direction (left/right/across) decided by dealer dice (odd/even/triple mapping shown on screen); simultaneous blind pass.
2. **骰子換牌 (Keith's original)** — dealer rolls dice; roll maps to swap count for everyone (default mapping: die total mod table → 0–5 tiles; exact mapping editable by host); same-suit constraint optional (default OFF); direction also dice-decided.
3. **自定義** — host fixes count (0–5) and direction.
- Flowers/jokers cannot be passed. Timer per selection (default 15 s; AI auto-picks lowest-value tiles on timeout).
- 天叮 note: because hands change, the 天叮/天糊 window opens **after** the swap completes. (House-rule flag: disable 天叮 when 換牌 is on — default keeps it on.)
- ⚠️ No official precedent for mode 2 — we own the spec; fairness rule: everyone swaps the same count, blind simultaneous exchange.

---

## 10. F7 — Private rooms & multiplayer

- **Flow**: Home → 開房 → room-setup wizard (preset pick/edit → toggles for 百搭/換牌/拉 → 東 count → timers) → room created with 6-char code → friends join by code → host taps 開局 (AI auto-fills empty seats).
- **Architecture**: server-authoritative. Firebase: Auth (anonymous + Google sign-in), Firestore (rooms, presets, profiles, match summaries), **Cloud Functions as the game server** (validates every action, holds the hidden wall/hands, emits per-player filtered views — clients never see others' tiles), Realtime Database or Firestore streams for live state.
- **Anti-cheat baseline**: hidden information never leaves the server; all moves validated; deterministic server RNG (per-hand seed kept server-side, disclosed post-hand for fairness audit — nice trust feature).
- **Disconnect/reconnect**: 30 s grace → AI takes over; player can rejoin and resume anytime; host migration if host quits (oldest member becomes host; rules stay frozen).
- **In-room extras**: quick-chat stickers/phrases (canned, no free text in v1 — avoids moderation burden), Cantonese voice callouts (碰!/上!/槓!/食!/自摸!).
- Match lifecycle: room persists for the configured 東 count → final settlement board → rematch vote.

## 11. F8 — AI players

- **Core**: 16-tile shanten calculator (5 melds + 1 pair; extended from 13-tile algorithms, joker-aware: jokers = free substitutions in the pattern search; memoized/pruned for mobile).
- **Discard policy**: minimize shanten → maximize 進張 (tile acceptance) → tiebreak by 番 potential (reads the room's edited 番表, so AI adapts to house rules!) → defense layer (fold heuristics: track discards/melds, avoid feeding 叮-declared or big-hand-visible opponents).
- **Claims**: value-based (does 上/碰/槓 lower shanten or raise expected 番 enough to justify opening the hand / breaking 門清·門叮 potential); 叮 declaration when 聽 with decent wait quality.
- **換牌 policy**: pass tiles from shortest/most isolated suit.
- **Difficulty tiers**: 初級 (greedy shanten, no defense), 中級 (+acceptance counting, basic defense), 高級 (+expected-value claim decisions, 拉 ledger awareness — plays safer against players it owes 拉 to).
- Runs server-side in multiplayer (Cloud Function turn) and on-device for offline mode (same Dart engine — shared package).

## 12. F9 — Game UI/UX (table scene)

- Landscape table view: own hand bottom (drag/tap to discard), opponents' 暗手 backs + 明章 melds + flowers on three sides, 牌河 per player (叮 tile rotated 90°), wall with 開門 break + 槓尾 visually distinct, dice-roll animations, dealer marker + 拉N莊 tag, wind/圈 indicator, remaining-tile counter, 拉 ledger widget.
- Action layer: contextual buttons (食/碰/槓/上/叮/過) with countdown ring; auto-pass toggle; 聽牌 helper (which tiles win + resulting 番 preview — toggleable per room as "beginner aid").
- Win reveal: hand fans open, qualifying 番種 items animate in with values, total counts up, settlement/拉-record animation.
- 補花, 搶槓, 雙響 etc. all get short distinct animations + Cantonese voice.
- Accessibility: large-tile mode, colorblind-safe suit accents, haptics on claim windows.

## 13. F10 — Meta screens

Home (開房/入房/單機/規則書) · Room lobby (players, rules summary card, code share via system sheet) · Preset manager (F7 §7) · Profile (name, avatar, stats: wins, biggest hand, 自摸率) · Match summary (per-hand log with replayable 番 breakdowns, final table) · Settings (sound/voice/haptics/tile size) · 規則書: in-app reference reproducing the 總例 structure + interactive 番種 encyclopedia (each 番種: definition + example tiles — doubles as the 番表 editor's help).

---

## 14. Asset list

### 14.1 Tile art (the big one)
- 42 standard faces: 萬×9, 筒×9, 索×9, winds×4, dragons×3, flowers×8 — plus **1 百搭 face** (distinct design, e.g. gold 百搭 glyph). = 43 unique faces.
- Tile back, tile side/edge (3D-ish sprite or 9-patch), face-down wall pair sprite.
- Sizes: hand (large), meld/river (medium), opponent minis (small) — export @1x/2x/3x atlases.
- States: normal, selected/raised, disabled/greyed (過水), highlighted (winning tile), 叮-rotated river tile.

### 14.2 Table & environment
Table felt background (2–3 themes: classic green, HK teahouse wood, dark), wall layout sprites, center info panel (winds/dice/counter), dealer marker, 拉莊 counter chip, dice (3D-rolled or sprite-sheet, 1–6), seat frames/avatars ring, room-code card.

### 14.3 UI kit
繁中-friendly font (e.g. Noto Sans TC + a display face for numerals/番 values — check embedding licenses), buttons (食/碰/槓/上/叮/過 in distinct colors), countdown ring, toggles/steppers for the 番表 editor, list cells, modal frames, scoreboard table, ledger widget, icons (settings, share, sound, help, preset, AI robot badge, connection state).

### 14.4 Animation & VFX
Tile deal sweep, 補花 flip, claim slam, 槓 reveal, 搶槓 flash, 叮 stamp effect, win fan-out + 番 item pop-ins, coin/score fly, 拉 chain-link effect (recorded score), 踢半 chain-break effect, dice roll, confetti for 420番-class hands.

### 14.5 Audio
- Cantonese voice pack (per seat, ideally 2 male + 2 female variants): 上/碰/槓/食/自摸/叮/搶槓 + numbers for 番 totals (optional).
- SFX: tile click/shuffle/wall-build, dice, claim stinger, win fanfare (small/big hand tiers), 流局 sting, button taps.
- BGM: 2–3 loopable low-key tracks (lobby + in-game), volume-separated.

### 14.6 Content/data assets
`fan_table.json` (official 番種簡表, verified), 總例 text for the in-app 規則書 (**need Keith to confirm rights to reproduce HKMA text/table — see §19 R1**), 番種 example-hand data for the encyclopedia, canned chat phrases list, store assets (icon, feature graphic, 8+ screenshots, listing copy 繁中).

---

## 15. Architecture

- **Client**: Flutter; Flame for the table scene (sprites, gestures, animations); ordinary Flutter widgets for menus/editor (Flutter's forte). State mgmt: Riverpod/Bloc (pick one, suggest Riverpod).
- **Shared Dart package `mj_core`**: tile/wall/hand models, rules engine (F1), 番 recognizer (F2), 拉 ledger (F3), AI (F8) — pure Dart, no Flutter deps → runs in client (offline) and Cloud Functions (online, compiled via Dart on Cloud Run if Functions-for-Dart friction, else Node port decision at spike time ⚠️).
- **Backend (Firebase)**: Auth · Firestore (profiles, presets, room configs, match archives) · game-state service (Cloud Run container running `mj_core`, WebSocket/Firestore-stream to clients) · Cloud Functions (room lifecycle, code generation) · Crashlytics + Analytics · Remote Config (timers, feature flags).
- **Determinism & replay**: every hand = seed + action log → enables replays, bug repro, and post-hand RNG disclosure.

## 16. Data model (Firestore sketch)

`users/{uid}`: name, avatar, stats. `presets/{id}`: ownerUid, name, fanTable{}, options{}, basedOn. `rooms/{code}`: hostUid, frozenPreset, seats[4]{uid|ai,connected}, status, 東/圈/局 counters, ledger{}, createdAt. `rooms/{code}/hands/{n}`: seed, actionLog[], result{winner(s), 番 items, totals, ledgerDelta}. Server-only collection for hidden state (wall, hands) inaccessible by security rules.

## 17. Roadmap (solo-dev friendly, ~6 milestones)

| M | Deliverable | Contents |
|---|---|---|
| M1 · Rules core | `mj_core` offline | tiles, deal/補花, turn flow, claims, 叮, 過水, win validation incl. special forms; CLI test harness; **fan_table.json verified vs PDF**; unit tests from 總例 examples |
| M2 · Scoring + ledger | scoring done | recognizer, 高點法/單式/不複合, settlement, 拉/踢半 + 斬拉, 中途獎勵; golden-hand test suite (≥100 hands) |
| M3 · Single-player app | playable APK | Flame table UI, AI 初/中級, offline vs 3 AI, win reveal, match summary |
| M4 · Modes & editor | feature-complete offline | 百搭 (+joker AI + recognizer), 換牌 (3 sub-modes), 番表 editor + presets, 規則書/encyclopedia |
| M5 · Multiplayer | online beta | Firebase auth, rooms/codes, server-authoritative service, reconnect/AI-takeover, voice/SFX polish; closed test with Keith's mahjong friends (the real validation!) |
| M6 · Release | Play Store | store listing, IARC rating, internal→closed→production tracks, Crashlytics triage, tutorial/onboarding polish |

Suggested testing discipline throughout: the scoring engine is the reputational core — maintain a growing golden-hands corpus; any dispute from beta testers becomes a test case.

## 18. Play Store checklist

Free app, no IAP/ads (D9) → simplest policy path. IARC questionnaire: answer *simulated gambling* honestly (mahjong with scoring; expect Teen-ish rating; no real-money, no cash-out, no wager language in listing). 繁中 listing (name suggestion needed — e.g. 《開枱・港式台牌》 — check trademark/name collisions before finalizing ⚠️). Privacy policy + Data-safety form (Firebase Auth/Analytics data). Target latest API level; app bundle; test on low-end Android (Flame perf).

## 19. Risks & open items

- **R1 — HKMA content rights**: the 番表 values/structure and in-app 規則書 text derive from the 協會總例 (©香港麻雀協會). Rules themselves aren't copyrightable but the text/table layout is. Keith to confirm relationship/permission with HKMA, or we rewrite the reference text in our own words. (I'm not a lawyer — worth a quick professional check before launch.)
- **R2 — 拉/踢半 edge cases**: multi-winner + ledger interactions under-specified in the 總例; write a decision spec early (M2) and validate with experienced players.
- **R3 — 番 recognizer complexity**: ~150 番種 with 高點法 enumeration is combinatorial; mitigate with the golden-hand corpus + property tests (e.g. disabling a 番種 never increases total).
- **R4 — Joker 高點法**: jokers multiply hand readings; needs pruning; cap analysis time with iterative deepening.
- **R5 — Server cost**: Cloud Run + Firestore streams for free app = ongoing cost; private-rooms-only keeps volume low; set budget alerts.
- **R6 — Solo-dev scope**: M1–M6 is a lot; the plan is sequenced so every milestone ships something playable — resist starting multiplayer before M4 is stable.
