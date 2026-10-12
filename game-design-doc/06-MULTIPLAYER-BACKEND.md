# 06 · Multiplayer & Backend Design

**Model:** friends-only private rooms · 4 seats · server-authoritative · Firebase + Cloud Run game service.

---

## 1. Topology

```
Flutter client ⇄ (a) Firestore: profiles, presets, room directory, match archives
              ⇄ (b) Game service (Cloud Run, Dart, runs mj_core): live game WebSocket
Cloud Functions: room lifecycle (create/join/close), code allocation, cleanup
Firebase Auth: anonymous by default, optional Google link (preset/stat portability)
```

The **game service** owns all hidden state (wall order, hands, 槓尾). Clients receive **per-seat filtered views** only — opponents' hands/wall never reach the device (anti-cheat by construction). Every client action = intent message; service validates against the rules engine and broadcasts resulting events.

## 2. Room lifecycle

1. Host completes wizard → Function allocates unused 6-char code (unambiguous alphabet, no 0/O/1/I) → `rooms/{code}` doc with **frozen preset**.
2. Joiners enter code → seat assigned (max 4) → lobby presence via Firestore stream.
3. Host taps 開局 → Function spins/assigns a game-service session; empty seats become AI; room locked to members (mid-match join only for the original members' reconnects).
4. Match end → summary written to `rooms/{code}/result` + each user's archive → rematch vote (same frozen preset; host may re-wizard = new room).
5. Cleanup: rooms idle > 24 h or completed > 7 d archived & code recycled.

## 3. Protocol (game service ⇄ client)

- Client→server intents: `discard(tile)`, `claim(type)`, `pass`, `kong(choice)`, `ting`, `swapSelect(tiles)`, `flowerChoice`, `zhanLa`, `emote(id)`, `resume`.
- Server→client events (per-seat filtered): `stateSnapshot` (on join/resume), `dealt(yourTiles, counts)`, `drawn(you: tile | others: count)`, `discarded`, `claimWindow(options, deadline)`, `melded`, `tingDeclared`, `flowerEvent`, `handEnd(winContext, fanItems, settlement, ledgerDelta)`, `matchEnd`.
- All events carry `seq` numbers; client re-syncs via snapshot on gap. Timers are server-side; deadlines sent as timestamps (client renders ring from clock offset).

## 4. Determinism, fairness & audit

Per-局 server RNG seed; full action log stored. Post-局, seed + wall order disclosed in match log (「公平驗證」 tab — players can verify the wall was fixed before play). Enables replay, bug repro, dispute resolution.

## 5. Disconnect & AI takeover

Presence heartbeat (5 s). Miss 30 s → seat flips to AI (badge shown, toast to room). Player resumes anytime with full snapshot + catch-up toast. Host disconnect: authority is server-side so play continues; host *controls* (kick/rematch settings) pass to longest-seated member until return. Room dissolves if all humans gone 10 min.

## 6. Data model (Firestore)

```
users/{uid}: {name, avatarId, stats{games,wins,selfDraws,biggestFan}, presetIds[]}
presets/{id}: {ownerUid, name, note, fanTable{...}, options{...}, basedOn:"official", updatedAt}
rooms/{code}: {hostUid, frozenPreset{...}, seats[4]{uid|"ai:level", presence}, status, sessionRef,
               counters{東,圈,局}, createdAt}
rooms/{code}/hands/{n}: {seed(disclosed post-hand), actionLog[], result{winners[], fanItems[], deltas[], ledger}}
users/{uid}/archive/{matchId}: summary
-- game-service internal (not Firestore): live wall/hands/timers per session
```
Security rules: users write self only; presets owner-only; rooms writable via Functions/service only; hands read-only to members; hidden state never in Firestore.

## 7. Offline 單機 mode

Same `mj_core` engine runs locally with 3 on-device AI; identical UX; results stored locally (not in cloud stats to keep them honest). Serves as the zero-latency demo and the engine's daily test bed.

## 8. Ops & cost posture

Free app → keep cold-startable Cloud Run (scale to zero), one region (asia-east), Firestore reads minimized (events over WebSocket, Firestore only for durable docs). Budget alerts at $10/25/50/mo. Crashlytics + Analytics (screen funnels: wizard completion, match completion, editor usage — measures whether the differentiators actually get used). Remote Config: timers, feature flags, kill-switch for 換牌 mode 2 while balancing.
