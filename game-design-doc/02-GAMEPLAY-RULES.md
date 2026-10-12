# 02 · Gameplay & Rules Design Spec
**Source of truth:** 香港麻雀協會《港式十六張新章麻雀總例》(2025-07-28). This doc restates it as an implementable spec; on any conflict, the PDF wins.

---

## 1. Definitions

- **Tiles:** 144 base (萬/筒/索 1–9 ×4, 東南西北 ×4, 中發白 ×4, flowers 春夏秋冬梅蘭菊竹 ×1). +4/+8 百搭 if enabled (see 04).
- **面子:** 順子 (3 consecutive same-suit) / 刻子 (3 identical) / 槓子 (4 identical via 開槓; 4-in-hand unmelded = 暗刻+1, not a 槓).
- **食糊形:** 基本形 = 5 面子 + 1 眼; 特殊形 = 嚦咕嚦咕 / 十三么 / 十六不搭. A hand must match a 食糊形 AND ≥ configured minimum (default: no minimum 番) to win.
- **Structure:** Match = N × 東; 東 (round) = 4 圈; 圈 = ≥4 局 (dealer repeats extend it); 局 = one hand.

## 2. Match start & per-局 setup

### 2.1 執位 (每個東執一次)
Full ceremony (optional animation; quick mode = server random with same distribution): shuffle 東南西北一筒二筒 face-down → opposite player rolls 3 dice → 數骰位 counts counter-clockwise from roller (5/9/13/17 = roller; 2/6/10/14/18 = 下家; 3/7/11/15 = 對家; 4/8/12/16 = 上家) → tiles laid with 一筒 left / 二筒 right of the row → dice even: assign winds starting from 二筒 side; odd: from 一筒 side → whoever draws 東 sits 東位 and rolls to decide first dealer.

### 2.2 開門 & 配牌
Dealer rolls 3 dice → 數骰位 picks 開門人; count = break offset on 開門人's wall (right→left), break point defines 槓尾 (dead-wall side, drawn leftward for 補花/補槓) and 牆頭 (live draw, clockwise). Deal: 4 tiles × 4 rounds each (counter-clockwise from dealer) → 16 each. 補花: strict order 東→南→西→北, multi-round until no flowers in hands. **天叮 window:** after 補花, before dealer's first draw, any already-聽 player may declare 天叮 (+40番 on win). Dealer then draws tile 17 and the 局 begins (no 天叮 declarations accepted after this draw).

## 3. Turn engine (state machine — the heart of F1)

```
局 states: DEALING → SWAP(換牌, optional) → TIN_WINDOW(天叮) → TURN_LOOP → HAND_END
TURN_LOOP per player P:
  DRAW(P) ──flower──> replace from 槓尾 (repeat)
    ├─ P may: 自摸食糊 | 暗槓 | 加槓 | discard
    ├─ 暗槓/加槓 → CLAIM_WINDOW(搶槓, 加槓 only) → 補槓 draw → back to P-may
    └─ DISCARD(P) → CLAIM_WINDOW(discard)
CLAIM_WINDOW: collect intents {食, 碰, 槓, 上, 過} within timer
  → resolve priority 食 > 碰/槓 > 上 (multiple 食 all win: 雙響/三響)
  → winner-of-claim acts; else next player draws
HAND_END: 食糊 (→ scoring, 03) | 流局 (wall empty → 連莊, 拉莊+1)
```

Claim legality: 上 from 上家 only; 同巡 re-碰 of a declined tile blocked; only the most recent discard claimable; melds locked once made.

## 4. Actions detail

- **上:** meld shown with claimed tile in the middle. After 上, must discard.
- **碰:** from any player; forms 明刻; then discard.
- **暗槓:** on own turn; face-down; instantly pays 中途獎勵 (1底 = 5分 from each player, see 03 §3); revealed at hand end; then 補槓 from 槓尾 + discard. Cannot be robbed (十三么 included — 總例 forbids 搶暗槓 outright).
- **加槓:** add 4th tile to own 明刻; open to 搶槓 before 補槓 completes.
- **大明槓:** claim discard onto concealed triplet; face-up; 補槓 + discard.
- **搶槓:** any 聽 player may win the 加槓 tile (+10番 搶槓); treated as 加槓-player 出銃.
- **叮 (ready):** available whenever 聽; declares + rotates next discard 90°. Locks hand: no draw-swap (auto-discard drawn non-winning tiles), no 鳴牌, no 槓. Yields 叮+5番, 即食+5番 (win ≤1巡 after 叮, cancelled by any intervening 鳴牌/暗槓), 天叮40/地叮30/人叮20.
- **過水:** declining a winnable tile (discard, or 加槓 tile) → cannot win until own next discard (同巡); if 叮-ed, cannot win for the rest of the 局. Tracked automatically; 食 button suppressed with reason tooltip.

## 5. Flowers

Drawn flower → auto-expose + replace from 槓尾 (flowers never occupy hand slots). 花糊 events:
- **七搶一:** P has 7 flowers, Q draws the 8th → P chooses: claim instantly (30分 from Q, 中途獎勵-style) or 照補花 continue (flower value stacks onto a later win; 該點拉落下一鋪 when applicable).
- **兩台花:** P draws own 8th flower → choose instant 40分 from each, or continue (八隻花 = 40番 within a completed hand).
Digital UX: choice modal with 10 s timer, default = claim.

## 6. Dealership & flow between hands

莊家 win or 流局 → same dealer, 拉莊+1 (dealer adds 2N番 to wins AND losses at 拉N莊; base 莊家1番 always). Any 閒家 win → dealership passes counter-clockwise, 拉莊 resets. 一輪 = strict 4 圈 regardless of 連莊 count. Multiple simultaneous winners off dealer's discard: each counts 莊/拉莊 bonuses.

## 7. Blocked-move policy (D8)

The client only ever offers legal actions; the server validates anyway (defense in depth). Consequently 詐糊/空糊/相公/食換/改鳴/摸錯牌 cannot occur. 斷橋/曝露張 etc. are physical-world rules with no digital analogue — omitted. This policy is *by design*, not a simplification: the 總例's own preamble frames penalties as remedies for physical-play errors.

## 8. Configurable rule surface (consumed by preset system, see 04)

minimum-番-to-win (default 0) · claim timer (3/5/8 s) · 執位 full/quick · 東 count (1圈快局/1東/2東) · 中途獎勵 on/off · 即食 window on/off · 天叮 on/off · 花糊 instant-claim on/off · auto-pass when nothing claimable (default on) · 聽牌 helper on/off (room-level, host decides — it's an information advantage).
