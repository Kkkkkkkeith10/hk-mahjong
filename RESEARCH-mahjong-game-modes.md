# Mahjong Game Research — 港式台灣牌 & 百搭麻雀
**For:** Keith's multiplayer mahjong game (Flutter/Flame → Google Play)
**Date:** 2026-07-07 · **Status:** DRAFT — awaiting Keith's approval before feature planning

---

## 0. What this document covers

1. Game Mode A — 港式台灣牌 (HK-style Taiwan 16-tile mahjong): rules + 台數表
2. Game Mode B — 百搭麻雀 (joker mahjong): HK 百搭 style AND Vietnamese joker style
3. 換牌 (opening tile swap) mechanics, including dice-determined swap counts
4. Editable 番表/台數表 — market gap analysis
5. Competitor apps on Google Play + store policy notes
6. Technical direction: Flutter/Flame, multiplayer backend, AI approach
7. YouTube reference videos
8. Open questions for Keith ← **please answer these**

---

## 1. Game Mode A — 港式台灣牌 (Taiwan 16-tile, HK style)

> ### ⭐ 2026-07-07 UPDATE — AUTHORITATIVE SOURCE RECEIVED
> Keith supplied the **香港麻雀協會《港式十六張新章麻雀總例》** (last revised 2025-07-28, 19 pp).
> **This rulebook supersedes sections 1.1–1.3 below** (kept for comparison only).
> See the new **Section 1A** for the rulebook digest. The uploaded PDF is the single
> source of truth for Mode A's rules engine.

---

## 1A. Mode A per the official rulebook (港式十六張新章總例)

### 1A.1 Structure of the rulebook
總則 → 牌的構成 → 流程 → 組合(面子/食糊形) → 座位及配牌(數骰位/執位/莊家風位/開門/配牌) → 桌面區域 → 行牌過程/摸打規條 → 行牌事件(鳴牌/碰/上/開槓/搶槓/叮牌/食糊/花糊/計分/中途獎勵/鳴牌優先) → 流局/連拉莊 → 一輪結束/賽制 → 犯規與罰則 → 分數計算(授受法/拉/番種簡表).

### 1A.2 Key mechanics the engine must implement (from the rulebook)

- **144 tiles** incl. 8 flowers; win = 5 面子 + 1 眼 (17 tiles), or special hands 嚦咕嚦咕 / 十三么 / 十六不搭.
- **執位** every 東 (round of 4 圈): draw 東南西北一筒二筒 tiles + 3-dice roll (數骰位, counted counter-clockwise from roller: 5/9/13/17→self etc.) to seat players; odd/even dice decide whether wind assignment starts from 一筒 or 二筒 side.
- **開門**: dealer rolls to pick 開門人 and break point; 槓尾/牆頭 defined; wall drawn clockwise while turns go counter-clockwise.
- **配牌**: 4-tile blocks ×4 → everyone 16 tiles (dealer draws 17th as first draw); 補花 strictly in seat order, multi-round; 天叮 (declare 叮 immediately after 補花, before dealer's first draw) = +40番.
- **鳴牌**: 上 (upper player only) / 碰 / 明槓·加槓·暗槓 / 搶槓 (only on 加槓; 十三么 cannot 搶暗槓). One-巡 restrictions (同巡不得再碰同一張). Meld display rules (上牌 claimed tile placed in middle; 暗槓 face-down, shown at hand end).
- **叮牌 (declare ready)** — a defining 港式台牌 feature: any 聽牌 player may declare 叮, rotates first discard after 叮; locked hand (no tile changes, no 鳴牌 except win, no 槓); 叮糊 +5番; **即食** (win within one 巡 of 叮) +5番; 天叮 40番, plus 地叮/人叮 in the 番表.
- **過水 (sacred discard)**: pass on your winning tile → cannot win rest of that 巡; after 叮, passing → cannot win rest of the hand.
- **花糊**: 7 flowers + another player draws the 8th → 七搶一 (30番 from that player); 8 flowers self → 兩台花/正爛花 40番. Player may instead 照補花 and continue; flower score then stacks with a later normal win. 該點拉落下一鋪.
- **中途獎勵 (instant mid-hand payouts, independent of winning):** 七搶一 6底(30分) · 兩台花 8底/家(40分) · 暗槓 1底/家 — collected immediately, unaffected by 拉/踢.
- **鳴牌優先**: 食糊 > 碰/開槓 > 上; multiple simultaneous wins allowed (雙響 +5番 / 三響 +10番 to each winner).
- **流局**: wall empty → no score, 莊家連莊 & 拉莊數+1.
- **莊家連拉莊**: 莊家 1番; 拉N莊 adds **2N番** to dealer's wins/losses; any 閒家 win resets 拉莊數.
- **賽制**: 一輪 = 四圈 (one 東), 70-minute time limit; score-card signing (digital analogue: end-of-round confirmation screen).

### 1A.3 Scoring & settlement (very different from generic Taiwan 台數)

- **授受法**: score = hand's total 番數 directly (no 底+台 split). 全銃制 — discarder pays the whole value alone; 自摸 → all three pay full value each. **No 番 cap, no 包牌.**
- **拉 / 踢半 — the signature settlement system**: when A wins off B, the score is *recorded, not settled*. Then: (a) A wins off someone else / B deals into someone else → A collects the recorded score; (b) A wins off the other two → keeps recording; (c) A wins off B again or A 自摸 → recorded score ×1.5 + new score, keep recording (拉兩口, 拉三口…); (d) B wins off A or B 自摸 → B pays only **half** the recorded score (踢半). Rounding: 拉 rounds up, 踢 rounds down. 三口斬拉: after being 拉-ed 3+ 口, the loser may 斬拉 before next hand.
- **Counting rules**: 高點法 (highest interpretation wins); 單式結算 (two 番種 may both count only if meld-overlap <50%); 嚦咕兩食 (hand readable as both 基本形 and 嚦咕形 scores both, sharing 底/嚦咕/般高-excluded items); **不複合原則** (a 番種 that necessarily implies a lower one doesn't stack — with listed exceptions, e.g. 門叮 CAN stack 門清+叮=20番; 花牌/字牌/莊家 exempt).

### 1A.4 番種簡表 — ~150 番種 (draft transcription from p.18 — MUST be re-verified against the PDF at data-entry)

*General/action:* 叮5 · 門清5 · 自摸1 · 門叮15 · 門摸5 · 即食5 · 海底10 · 搶槓10 · 花摸5 · 槓摸5 · 尾牌連摸 5×2ⁿ · 雙響5 · 三響10 · 莊家1 · 拉莊2n · 槓2
*Tile-composition:* 無字1 · 字牌1 · 正字1 · 無花1 · 花牌1 · 正花1 · 無字花5 · 一台花10
*Wait/eye:* 對碰1 · 假獨1 · 獨獨2 · 將眼2
*Sequence hands:* 平糊5 · 大平15 · 老少順3 · 雙老少順25 · 相逢3 · 明/暗三相逢10/20 · 四同順20 · 五同順60 · 雙同順10 · 明/暗雜龍10/20 · 明/暗清龍15/30 · 雜三/四/五步高(明5/暗10 · 15/30 · 50/100) · 清三/四/五步高(20/40 · 60/120 · 200/400) · 連環套(明15/暗30) · 清金門橋(明50/暗100) · 一般高5 · 雙般高20 · 一色三同順(明60) · 一色四同順(明180/暗360)
*Triplet hands:* 對對糊40 · 坎坎糊240 · 二/三/四/五暗刻 5/20/60/180 · 二同刻5 · 小三同刻20 · 三同刻40 · 雙同刻20 · 三色連刻 series (小10→三色五連刻180 · 小六連刻260) · 連刻 series (二連刻5 → 小六連刻480) · 雙連刻20 · 老少刻5 · 雙老少刻30
*Honor/terminal/suit:* 大四喜180 · 小四喜120 · 大三風60 · 小三風30 · 大三元80 · 小三元40 · 字一色240 · 斷么10 · 混帶么40 · 全帶么80 · 混么80 · 清么420 · 混/純滿庭芳 60/120 · 缺五10 · 缺一門10 · 小五門10 · 小七門15 · 大五門20 · 大七門30 · 混一色40 · 清一色120 · 四歸 series (明四歸二5 → 暗四歸四120) · 八歸20 · 十二歸80
*Special forms:* 嚦咕嚦咕40 · 八對嚦咕10 · 三元嚦咕20 · 四喜嚦咕40 · 三色同對10 · 連對 series (三連對5 → 八連對420) · 十六不搭60 · 十六扇不搭20 · 不搭三相10 · 不搭雜龍30 · 十三么120 · 十三扇十三么+20 · 天/地糊120 · 人糊80 · 四子40 · 七子20 · 十子10 · 天叮40 · 地叮30 · 人叮20 · 大雞60 · 大鴨30 · 全求人40 · 半求人20 · 七搶一30 · 八仙過海40

### 1A.5 犯規/罰則 (tournament layer — optional in-app "referee mode")

黃牌/紅牌 system (紅牌 −60), 罰企糊 (barred from winning the hand), 詐糊 −160 & hand restarts, 相公 (小相公/大相公, 大相公 −20/tile), 違規公開手牌 penalty ladder, 做錯莊/拿錯牌/洗牌重配 procedures, 空糊 → 紅牌. A casual-mode game can auto-prevent most of these (illegal moves simply blocked), but a "strict/tournament mode" could simulate them — worth deciding in the feature plan.

### 1A.6 What this rulebook changes vs the earlier web research

1. Mode A scores in **番 with a ~150-item 番種簡表**, settled by 全銃 + 拉/踢半 — NOT the generic Taiwan 底+台 model in §1.2. The editable scoring table must therefore support: per-番種 values, formula entries (拉莊 2n, 尾牌連摸 5×2ⁿ), enable/disable per 番種, and the 不複合/單式結算/高點法 computation rules.
2. **叮牌** (+過水-after-叮, 即食, 天/地/人叮) is core to Mode A — absent from generic Taiwan rules.
3. **拉/踢半 ledger** is a cross-hand settlement engine — a major, unusual feature (state persists between hands; ×1.5 compounding; 斬拉 option).
4. 中途獎勵 (instant payouts) bypass the 拉 system — separate settlement path.
5. Special hands officially include 嚦咕嚦咕 / 十三么 / 十六不搭 (answers open question #1: yes, include).
6. 執位/開門/配牌 ceremony is fully specified — great material for an authentic "full ritual" mode vs a quick-deal mode.

### 1.1 Core rules

| Aspect | Rule |
|---|---|
| Tiles | 144: 108 suits (萬/筒/索 1–9 ×4) + 16 winds (東南西北 ×4) + 12 dragons (中發白 ×4) + 8 flowers (春夏秋冬梅蘭菊竹 ×1) |
| Hand size | 16 tiles (dealer 17); win = 5 組 (順子/刻子) + 1 對 (眼) = 17 tiles |
| Flowers | Exposed immediately, replaced from wall tail (補花) |
| Claims | 吃 (upper player only) / 碰 / 槓 (明槓、暗槓、加槓, draw replacement from tail) |
| 流局 | Wall exhausted to dead-wall threshold → 莊家連莊 |
| 詐胡 | False win → offender pays penalty (severity varies by house rule) |
| 相公 | Wrong tile count → hand dead, cannot win/claim rest of round |
| 連莊 | Dealer stays on win or 流局; 連N拉N convention: Nth repeat adds 2N+1 台 |

### 1.2 Standard 台數表 (must be editable in-game)

**Payment model:** 底 (base) + 台 × per-台 stake. 自摸 → all 3 opponents pay; 放槍 → discarder pays alone.

Base 台 items: 莊家 1台 · 連莊拉莊 2台/次 · 自摸 1台 · 門清 1台 · 門清自摸 3台 · 花牌 1台/張 · 花槓(同組4花) 2台 · 正花 (seat-matching flower — common HK addition) 1台 · 邊張/中洞/單吊 1台 · 海底撈月 1台 · 槓上開花 1台 · 搶槓 1台.

Hand-pattern 台: 平胡 2台 · 碰碰胡 4台 · 混一色 4台 · 清一色 8台 · 字一色 8台 · 小三元 4台 · 大三元 8台 · 小四喜 8台 · 大四喜 16台 · 三暗刻 2台 · 四暗刻 5台 · 五暗刻 8台 · 八仙過海 8台 · 七搶一 8台 · 天胡 16台 · 地胡 8台(some circles 16台).

⚠️ Values vary noticeably between sources/circles — this **confirms the editable 台數表 is essential**, not just nice-to-have.

### 1.3 What makes it "港式"

- HK terminology (麻雀/番/食糊) mixed with Taiwan mechanics
- Extra recognized hands from HK play: 十三么, 十六不搭 (16 unmatched tiles + eye — a special no-structure hand)
- 拉莊 conventions, dice-roll bonuses in some circles (圍骰/1-2-3 instant 番)
- Often uncapped 台 stacking vs Taiwan casual caps
- There is a zh.wikipedia page 港式台灣麻雀 documenting this hybrid — good primary reference for the rules engine

### 1.4 Rule options a game must expose (from research)

Flowers on/off · 正花/花槓 scoring · 詐胡 penalty severity · 台 cap (capped/uncapped) · 連莊 formula · dealer-extra-payment on 自摸 · minimum 台 to win · 十六不搭 allowed or not.

---

## 2. Game Mode B — 百搭麻雀 (joker mahjong)

Keith wants **both** joker systems, as separate rule presets.

### 2.1 HK 百搭 style

- Joker determined dynamically: flip an indicator tile, the **next tile in sequence** becomes 百搭 (e.g. flip 三筒 → 四筒 is joker). Variants: last wall tile, or dedicated 紅中 as joker (the currently popular 紅中百搭 played in HK — very visible on HK YouTube).
- Usually 1 joker rank (4 physical tiles).
- Substitutes any tile in 順/刻; **eye (眼) restriction debated** — many circles forbid joker-as-pair, some reward it.
- Discarding a joker: usually forbidden or a dead move.
- Scoring: joker itself adds no 番; some circles give bonus 番 for **淨百搭** (winning with zero jokers).

### 2.2 Vietnamese joker style (越南牌)

- Physical set has **8 extra printed joker tiles** on top of the standard set (160 total with flowers).
- Joker **hierarchy**: universal joker (總) substitutes anything; suit jokers (萬/筒/索 jokers) substitute only within their suit; honor joker substitutes 風/元 tiles; plus flower-joker scoring tiles.
- Jokers freely usable in melds AND as the pair.
- A discarded joker is treated as a universal tile — anyone waiting can win on it.
- Simpler scoring than HK; flowers score separately.

### 2.3 Key conflicts → argue for two presets, one engine

| Issue | HK 百搭 | Vietnamese |
|---|---|---|
| Joker source | Flipped/designated normal tile | 8 dedicated printed tiles |
| Joker count | 1 rank (4 tiles) | 8 tiles, tiered powers |
| Joker as eye | Often forbidden | Allowed |
| Joker in exposed melds | Restricted (house rule) | Allowed |
| Discarding joker | Forbidden/dead | Becomes universal win tile |
| Scoring | 番-based, 淨百搭 bonus | Simpler, meld-efficiency focused |

**Design implication:** one rules engine with a *joker substitution matrix* (which tile classes each joker can stand for, per meld type) covers both presets and any custom house rule in between.

### 2.4 Configurable options

Joker count · designation method (flip successor / last tile / 紅中 fixed / dedicated tiles) · joker-as-eye toggle · joker in 碰/槓 toggle · joker discard rule · 淨百搭 bonus · joker win-tile rule.

---

## 3. 換牌 (opening swap)

- **Best-documented precedent: 四川換三張** — after deal, every player passes exactly 3 tiles **of the same suit**; direction (left/right/across) decided by dice roll; happens before play starts.
- **Dice-determined swap COUNT** (Keith's idea — roll dice to decide how many tiles to swap) is **not a documented standard anywhere** — it appears to be a home-game custom / original mechanic. That's fine: it becomes a differentiator, but we must design the rules ourselves (fairness, same-suit constraint or not, direction, min/max count, timing vs 補花).
- Proposed configurable swap modes for the feature plan: ① off ② fixed 換三張 (Sichuan-style, same suit, dice decides direction) ③ dice-count swap (dice decides 0–N tiles, direction fixed or also diced) ④ free-count host-defined.
- Open design questions: does swap happen before or after 補花? Are flowers swappable? Same-suit constraint on or off? Simultaneous blind pass (like Sichuan) or sequential?

---

## 4. Editable 番表/台數表 — the market gap

- Major apps (神來也麻將, 明星3缺1, 神來也麻雀 HK, etc.) all use **fixed scoring** — no editable tables found on Google Play.
- Only a niche iOS scorer app (MJCounter) offers custom 台數表 — and it's a calculator, not a game.
- **This is Keith's strongest differentiator**: "digitize your own table's house rules" — editable 台 items, values, caps, and toggles per room, saved as shareable rule presets. Combined with 換牌 modes and dual 百搭 presets, no Play Store competitor offers this combination.

---

## 5. Competitors & Google Play policy

**Competitors:** 神來也麻將 (Taiwan 16-tile, ~tens of millions of players, F2P coins + daily bonus) · 明星3缺1 (IGS, 16-tile + casino side games) · 神來也麻雀 / Hong Kong Mahjong Club / Let's Mahjong / 開枱-style HK apps (13-tile). None offer editable scoring, 換牌 modes, or dual 百搭 presets.

**Policy notes (important for Play Store approval):**
- No real money in/out — virtual currency only, no cash-out, no "betting" language in store listing.
- Simulated-gambling content rating applies to mahjong with stakes imagery → expect higher IARC age rating; answer the content questionnaire as "simulated gambling" honestly.
- Avoid gambling terms in listing copy; position as tile strategy/scoring game.
- Loot-box style purchases require odds disclosure.

**Monetization patterns observed:** free coins on login, coin purchases (IAP), ads (rewarded video for coins), VIP/cosmetics (table skins, tile skins, avatars, voice packs).

---

## 6. Technical direction (Flutter/Flame — Keith's choice)

- **Flame fits well**: mahjong is turn-based, low tick-rate; Flame handles sprites, gestures, animation; Flutter UI shines for the heavy menu/settings side (番表 editor especially).
- **Multiplayer backend options:**
  - *Firebase (Firestore/RTDB)* — fastest MVP, official Flutter support, fine for turn-based; weak matchmaking.
  - *Nakama* — open-source game server with matchmaking, chat, presence, server-authoritative rules (anti-cheat); has a Dart client. Better long-term for competitive play.
  - *Custom WebSocket* — full control, all risk on us.
  - Suggested path: server-authoritative design from day 1 (rules validated server-side), Firebase for MVP or Nakama if we want ranked play early.
- **AI opponents:** shanten (向聽數) calculation adapted to 16 tiles (5 melds + 1 pair search) + rule-based discard/claim heuristics + defensive discard reading; difficulty tiers by adding Monte-Carlo lookahead at higher levels. 百搭 mode AI needs joker-aware shanten (jokers as free substitutions in the search). ML not practical (no 16-tile training data).
- **Reference:** fast shanten algorithm paper (arXiv 2108.06832); IJCAI mahjong AI competition materials.

---

## 7. YouTube references

**Taiwan 16-tile / 港式台牌:**
- 十六張麻將基礎教學一 — youtube.com/watch?v=8iV9ONBfuYw — basics of 16-tile play
- 台灣十六張麻將 基礎教學說明 — youtube.com/watch?v=UtvFj_iLSKc — full beginner walkthrough
- 港式台牌教學(9) 十三么 & 十六不搭 — youtube.com/watch?v=BZJEpyK0z0E — the HK-specific hands (directly on-topic for "港式台牌")
- 台灣牌實戰 叫牌小技巧 — youtube.com/watch?v=Ui5mjjGLbt8 — strategy/claiming
- 神來也麻將小教室#1 — youtube.com/watch?v=f1aIAT2kUgI — competitor's own tutorial style (good UX reference)

**百搭:**
- 百搭麻雀教學(一) 一步一步教識你打 — youtube.com/watch?v=KXNMHcogQxE — step-by-step HK 百搭 tutorial
- 百搭紅中自摸場 gameplay — youtube.com/watch?v=nJjjzmIT7qY — the currently popular 紅中百搭 variant
- 全城爆紅《百搭紅中》秒懂玩法 — youtube.com/watch?v=PBefcadeiPE — quick-learn rules for 紅中百搭
- 雙百搭秘訣 strategy — youtube.com/watch?v=-Cx0cumvoZk — joker-usage strategy

⚠️ YouTube URLs came from web search results; a couple may have drifted — verify by clicking before relying on any single one. Search terms that work: 「港式台牌 教學」「百搭紅中 玩法」「十六張麻將 教學」「換三張 麻將」.

---

## 8. Open questions for Keith (answer before feature plan)

1. ~~十六不搭 / 十三么 — include?~~ **ANSWERED by rulebook: yes** (60番 / 120番, plus 嚦咕嚦咕 40番).
1b. **NEW — Rule fidelity:** should Mode A follow the 協會總例 *exactly* (incl. 拉/踢半, 叮牌, 過水, 中途獎勵) as the default preset, with house-rule toggles layered on top? And is 拉/踢半 wanted in casual online rooms, or tournament rooms only?
1c. **NEW — 罰則:** casual mode will simply block illegal moves; do you also want a "strict/referee mode" simulating 黃牌/紅牌/詐糊 penalties for serious play?
2. **紅中百搭** — the joker research found the trending HK variant is 紅中做百搭 (red dragon as fixed joker). Should this be the default HK 百搭 preset, with flip-indicator as an option — or the other way round?
3. **百搭 on 16-tile or 13-tile base?** Is 百搭 mode played on the Taiwan 16-tile frame, HK 13-tile frame, or selectable?
4. **換牌 scope** — available in both game modes, or only certain rooms? Host-controlled per room?
5. **Money model** — virtual coins with IAP + rewarded ads acceptable? (Real-money is a hard no for Play Store.)
6. **Multiplayer priority** — friends-only private rooms (開枱 with room code) first, or public matchmaking + ranking from day 1? This decides Firebase-vs-Nakama.
7. **Players per table** — 4 only, or support 3-player (三人麻雀) later?
8. **Language/UI** — 繁體中文(HK) only, or +English for wider Play Store reach?
9. **Editable 番表 sharing** — should custom rule presets be shareable between players (codes/links)? Strong retention feature but adds backend work.

---

## Sources (key)

- zh.wikipedia 港式台灣麻雀 · Klook 台灣麻將規則/台數 guides · vocus 16張教學 · GameTower/明星3缺1 rules pages · mj888 Taiwanese scoring (EN)
- YOHO/HK01/Pinkoi HK mahjong rule guides · Baidu 百搭麻將 · Sloperama Vietnamese Mah-Jongg rules doc · MahjongPros Vietnamese guide · BGG Vietnamese joker thread
- MahjongSoft Sichuan rules · GitHub kltm/sichuan-style-mahjong-rules
- Google Play: 神來也麻將 (com.godgame.mj.android) · 明星3缺1 (com.igs.mjstar31) · 神來也麻雀 (com.godgame.mj13.android)
- Google Play gambling policy: play.google.com/about/restricted-content/gambling
- Flame engine flame-engine.org · Flutter Firestore multiplayer cookbook · Heroic Labs Nakama docs · arXiv 2108.06832 (fast shanten)
