# 08 · System Integration — How Everything Connects

The keystone doc: module boundaries, the event spine, shared state machines, and the cross-cutting flows that tie 02–07 together.

---

## 1. Module map

```
┌────────────────────────────── Flutter app ──────────────────────────────┐
│  UI-Meta (Flutter widgets)          UI-Table (Flame)                    │
│  home · wizard · editor · 圖鑑  ↔   table scene · action layer · FX     │
│            │  Riverpod state / event bus  │                             │
│  ┌─────────┴───────────────────────────────┴──────────┐                 │
│  │            GameClient (view-model layer)           │                 │
│  │  session adapter: LOCAL(mj_core) | REMOTE(WebSocket)│                │
│  └───────────────┬─────────────────────┬──────────────┘                 │
└──────────────────│─────────────────────│────────────────────────────────┘
          LOCAL    │                     │  REMOTE (per-seat filtered events)
┌─────────  mj_core (pure Dart, shared package)  ─────────┐   ┌─ Cloud ──┐
│ RulesEngine (02)  ── emits GameEvents                   │   │ Game     │
│ FanRecognizer + FanTable (03)                           │◄──┤ service  │
│ Settlement + LaLedger (03)                              │   │ (runs    │
│ Modes: JokerRules · SwapPhase (04)                      │   │ mj_core) │
│ AI L1–L3 (07) — consumes the same filtered view API     │   └────┬─────┘
└─────────────────────────────────────────────────────────┘        │
                       Firebase: Auth · Firestore (presets/rooms/archives) · Functions
```

**The prime integration rule:** `mj_core` is the single implementation of the game. Client (offline), server (online), and AI all consume it through the same two interfaces — `intent in, events out` and `FilteredView` — so online/offline behavior can never diverge, and AI can never cheat.

## 2. The event spine

All gameplay is expressed as an ordered `GameEvent` stream (dealt, drawn, discarded, claimWindow, melded, tingDeclared, flowerEvent, swapPhase, handEnd, matchEnd — see 06 §3). Consumers subscribe to the same stream:

| Consumer | Reaction |
|---|---|
| UI-Table | animates the event (01 §6 motion vocabulary), updates layout |
| Audio | voice call / SFX per event type |
| Ledger widget | on `handEnd.ledgerDelta` → chain/break animations |
| Match log | appends replayable entries |
| AI seats | receive events → produce intents (server-side or local) |
| Analytics | funnels (claims used, 叮 rate, editor-modified 番種 triggering) |

Replay = re-emitting a stored event log into the same consumers with input disabled. Reconnect = `stateSnapshot` (compressed current state) + resume live stream. One spine, five features for free.

## 3. Rule data flow (the preset thread)

```
總例 PDF ──(verified transcription, M1)──► fan_table.json (official)
   └► Preset editor (05 §5) clones ► user preset (Firestore) ─┐
Room wizard picks preset ► FROZEN copy into rooms/{code} ─────┤
                                                              ▼
                     ┌── RulesEngine reads options (timers, modes, min番, 拉 on/off)
        frozen preset├── FanRecognizer reads fanTable (values, enabled, suppresses)
                     ├── AI L2/L3 read fanTable for hand-value planning (07 §2)
                     ├── Lobby/table summary chip renders diff-vs-official (04 §4)
                     └── 圖鑑 renders "current preset vs official" per 番種 (05 §6)
```
One JSON document drives rules, scoring, AI motivation, and three UI surfaces. Editing a 番種 therefore *visibly changes the whole game* — including how AI plays — which is the product thesis (pillar 2) realized technically.

## 4. State machines & who owns them

| Machine | Owner | Notes |
|---|---|---|
| Match (東/圈/局 progression, dealership, 拉莊N) | mj_core `MatchState` | authoritative instance lives where the session lives (server or local) |
| 局 (DEALING→SWAP→TIN_WINDOW→TURN_LOOP→HAND_END, 02 §3) | mj_core `HandState` | emits the event spine |
| Claim resolution (priority, timers, 過水 marking) | mj_core within TURN_LOOP | timers server-side online (06 §3) |
| LaLedger | mj_core `LedgerState`, persisted in room doc between hands | survives service restarts |
| Room lifecycle (lobby→playing→ended) | Cloud Functions + room doc | UI-Meta subscribes |
| Client session (connecting→synced→playing→reconnecting) | GameClient | drives connection UX (05 §7) |

## 5. Cross-cutting flows (worked end-to-end)

**A. A discard someone can rob-win (搶槓 variant of the spine):** P2 加槓 → RulesEngine opens CLAIM_WINDOW(搶槓) → filtered views: only 聽-on-that-tile seats get `claimWindow{食}` → P4 taps 食 → engine validates (not 過水-locked) → `handEnd` computes WinContext(搶槓 flag) → FanRecognizer adds 搶槓10番 → Settlement charges P2 as 出銃 → LaLedger consults P4→P2 pair → UI plays 搶槓 flash → win overlay → ledger chain animation → next 局 with dealership logic.

**B. Host edits 清一色 120→500 in the editor:** editor mutates preset draft → live preview panel re-scores sample hand via FanRecognizer (same code, instant feedback) → saved to Firestore → wizard freezes it into the room → lobby diff chip shows 「清一色 500」 → in play, AI-L2 seat starts favoring flush lines (07 §2) → someone wins 清一色 → win overlay shows the row valued 500 → 圖鑑 card for 清一色 shows "本房 500 · 官方 120".

**C. Player disconnects mid-叮:** presence miss 30 s → seat flips AI (06 §5) → AI inherits FilteredView incl. 叮-locked state → AI auto-plays per 叮 rules (win-only) → player resumes → snapshot restores UI incl. 「你已叮」 toast → AI badge clears.

**D. 換牌 + 百搭 + 天叮 ordering (mode interaction):** DEALING (152 tiles, jokers in wall) → 補花 completes → SWAP (jokers unswappable, greyed in selection UI) → exchange resolves → TIN_WINDOW: 聽 check runs joker-aware → 天叮 offered → TURN_LOOP. The state machine linearizes the three features so they can't conflict; each mode only ever adds a state or modifies a predicate, never forks the flow.

## 6. Dependency & build order

`fan_table.json` → RulesEngine/FanRecognizer (M1–M2) → LOCAL GameClient + Flame table (M3) → Modes & editor (M4, pure mj_core + UI additions) → game service = mj_core behind WebSocket + Functions (M5) → store (M6). Nothing in M3–M4 has to change for M5 **if** the GameClient adapter boundary (LOCAL/REMOTE) is respected from M3 day one — the single most important architectural discipline in the project.

## 7. Consistency contracts (testable invariants)

1. Same seed + same intents ⇒ identical event log, local or remote (determinism).
2. No event delivered to a seat contains information that seat couldn't see at a physical table (filtering).
3. Recognizer(total) with any 番種 disabled ≤ with it enabled (editor sanity).
4. Ledger conservation: Σ(all deltas incl. recorded) = 0 every hand.
5. AI intents are always in the legal-action set offered to that seat (no-cheat).
These run in CI on the golden corpus + fuzzed self-play (07 §5).
