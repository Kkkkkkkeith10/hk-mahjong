# 00 · Game Design Document — Overview
**Working title:** 《開枱》— 港式台牌 (final name TBD, check collisions before launch)
**Platform:** Android (Google Play) · **Engine:** Flutter + Flame · **Backend:** Firebase
**Language:** 繁體中文 · **Price:** Free, no monetization (v1)
**Version:** GDD v1.0 · 2026-07-07

---

## 1. Vision statement

The authentic home-table 港式台牌 experience, digitized. Not a casino app, not a generic mahjong app — *your* table: your 番表, your house rules, your friends, the 拉/踢半 tension that makes 港式台牌 what it is, wrapped in a nostalgic Hong Kong 麻雀館/茶餐廳 aesthetic.

## 2. Design pillars

1. **忠於總例 (Faithful)** — the 香港麻雀協會《港式十六張新章麻雀總例》(2025-07-28) is the rules bible. Default preset = official rules, exactly.
2. **你屋企的規矩 (Yours)** — every 番種 value editable, every mechanic toggleable (拉/踢半, 百搭, 換牌). The app adapts to the table, never the reverse.
3. **開枱唔使等 (Frictionless)** — room code → friends in → AI fills gaps → playing within 60 seconds. Illegal moves are impossible, scoring is automatic and itemized, disputes die.
4. **香港味 (HK soul)** — 茶餐廳/麻雀館 visual identity, Cantonese voice calls, the ritual (執位, 開門骰) kept as optional ceremony.

## 3. Audience

Primary: HK players 25–55 who play 台牌 at home/麻雀館 and want to keep playing when they can't meet — they know the rules, they have opinions about 番表.
Secondary: HK mahjong players who know 13-tile 香港牌 and want to learn 台牌 (served by beginner aids + in-app 規則書).

## 4. Core loop

開房 (pick/edit rules) → 執位/開門 → play hands (draw–discard–claim–叮–食糊) → itemized 番 settlement + 拉 ledger drama → next hand → end of 東 → final board → rematch.

Session target: one 東 (四圈) ≈ 30–50 min; 快局 option (1 圈) ≈ 10–15 min.

## 5. Document map

| Doc | Contents |
|---|---|
| 00-OVERVIEW | This file — vision, pillars, loop |
| 01-STYLE | Visual & audio identity: palette, type, tiles, motion, sound |
| 02-GAMEPLAY-RULES | Rules-engine design spec (per 總例) |
| 03-SCORING-SETTLEMENT | 番 recognizer, computation rules, 拉/踢半 ledger |
| 04-GAME-MODES-OPTIONS | 百搭, 換牌, room options & preset system |
| 05-UI-UX | Screens, flows, table layout, interactions |
| 06-MULTIPLAYER-BACKEND | Rooms, netcode, server authority, data model |
| 07-AI | AI player design, difficulties, integration points |
| 08-INTEGRATION | How every system connects: modules, events, state machines, data flow |
| 09-ASSETS | Complete asset manifest (art/audio/data) styled per 01 |

Companion docs (same folder level up): `RESEARCH-mahjong-game-modes.md`, `FEATURE-PLAN.md` (decisions D1–D11, roadmap M1–M6, risks R1–R6). The uploaded 《港式台牌總例》PDF is the rules source of truth.

## 6. Non-goals (v1)

Public matchmaking/rank · 3-player · monetization · English · penalty/referee simulation · 13-tile 香港牌 · joker hierarchies · real-money anything · free-text chat.
