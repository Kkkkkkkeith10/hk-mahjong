# 05 · UI / UX Design

Style per 01-STYLE. Landscape-only table scene (Flame); portrait allowed in menus (Flutter widgets).

---

## 1. Screen map & flows

```
Splash → 主頁 ──┬─ 開房 → 房間設定精靈 → 大廳(lobby) → 牌局(table) → 結算 → 再戰?
               ├─ 入房 (code entry / recent rooms) → 大廳 → …
               ├─ 單機 (quick AI game, last-used preset) → 牌局
               ├─ 規則書 (rules reference + 番種圖鑑)
               ├─ 番表管理 (preset manager/editor)
               └─ 設定 / 個人檔案
```

First-launch: name + avatar pick (anonymous auth silently created) → optional 60-second interactive tour (deal → claim → 叮 → win) — skippable, revisitable from 規則書.

## 2. 房間設定精靈 (room setup wizard) — 3 steps

1. **規則:** preset cards (協會新章 / 新手場 / 百搭歡樂場 / my presets) → optional 「修改」 into editor.
2. **模式:** 百搭 toggle + its sub-options; 換牌 toggle + sub-mode picker; 拉/踢半 toggle (default ON).
3. **場口:** match length, timers, aids, theme → 「開房」→ room code screen (giant code, share sheet button, QR).
Every step shows a live summary card on the right; the same card appears in the lobby and (collapsed) at the table.

## 3. 牌局 (table scene) layout — landscape

- **Bottom:** own 16-tile hand (drawn tile offset right); flowers + melds fanned left of hand; tap = raise, tap again / drag up = discard; long-press = zoom tile.
- **Left/top/right:** opponents — avatar + name + wind chip + connection/AI badge, 暗手 tile backs (count-accurate), melds + flowers, personal river below each (6–8/row, 叮 tile rotated).
- **Center hub:** wall ring with 開門 break & 槓尾 shading, dice zone, 圈風/局數, remaining-tile counter, dealer 莊 coin + 拉N chips.
- **Top bar (thin):** room name/rules summary chip (tap → full preset view), ledger strip (拉 chains), menu (⚙ sound/leave/help).
- **Action layer:** contextual pill buttons bottom-right (食/碰/槓/上/叮/過) with countdown ring; appear only when legal (D8); auto-過 setting honored; multi-槓 choice shows tile thumbnails.
- **Turn cues:** own-turn = hand area glow + haptic; others = avatar ring fills with their timer.

## 4. Key interaction specs

- Claim window: buttons ≥ 64 px tall; 食 always leftmost & red; simultaneous options stack vertically; timer visualized as draining ring; timeout = 過 (and sets 過水 where applicable — warn with a red flash "過水!").
- 叮: button pulses when 聽; confirmation sheet shows waits + potential 番 preview (helper-independent: after 叮 the commitment is real, so always show before confirming); after 叮, drawn non-winning tiles auto-discard with 300 ms cancel window (win tiles always prompt).
- 換牌 phase: hand rises; select N tiles (counter shows N/需求); confirm lock; waiting states show opponents' locked status; exchange animation crosses tiles face-down.
- 過水 state: suppressed 食 shows grey button with 「過水」 tag; tooltip explains until when.
- Win overlay & settlement per 03 §5. 流局: wall collapses animation + 「流局 · 連莊拉一」 banner.
- Reconnection: returning player gets a 2 s catch-up summary toast (「第3局 · 你已叮」).

## 5. 番表編輯器 (FanTable editor)

Portrait-friendly list: category accordion (per 03 §1 categories) → rows [名稱 | 番值 stepper | on/off]; search bar; formula rows open a small sheet (coefficient + preview curve); dependency-disabled rows greyed with reason; sticky footer: 「還原官方」 · live sample-hand score preview (a fixed showcase hand re-scored on every change); save-as dialog with name + note. Diff badge counts changes vs 協會新章.

## 6. 規則書 & 番種圖鑑

規則書: the rules restated in-app (⚠ pending R1 rights decision — our own wording by default), structured like the 總例 TOC, searchable. 圖鑑: every 番種 = card with definition, example hand rendered in real tile art, value in current preset vs official. Deep-linked from win overlay rows and editor rows (tap 番種 name anywhere → its card).

## 7. Feedback & error UX

No blocking modals during play except win/花糊 choices. Network hiccup: thin amber banner + auto-retry; 30 s → AI-takeover notice. Errors never show technical text; always an action (重試/離開). All destructive actions (leave mid-match, 斬拉, delete preset) use confirm sheets.

## 8. UX guardrails (design intent)

The app never rushes a thinking player beyond room timers; never hides information a physical table would show (rivers, melds, discard order, wall count); never reveals information a physical table would hide (hands, wall) — even in the client's memory (server-filtered views, 06). Beginner aids are room-scoped and visible to all (fairness transparency: lobby card lists 「聽牌提示: 開」).
