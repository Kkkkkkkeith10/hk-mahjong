# 01 · Style Guide — Visual & Audio Identity
**Direction (locked):** 茶餐廳/麻雀館 Hong Kong vibe · simple avatars

---

## 1. Mood

Late-night 麻雀館 above a 茶餐廳: warm tungsten light on a wooden table, neon glow bleeding through the window, formica textures, hand-painted signage type. Nostalgic but clean — the HK-ness lives in the frame (environment, type, sound); the play area itself stays high-contrast and legible. **Readability always beats decoration.**

## 2. Color palette

| Role | Color | Hex (starting point) |
|---|---|---|
| Table wood | Deep rosewood | `#5C3A21` |
| Table surface inlay | Felt green (desaturated, warm) | `#2E5E4E` |
| Background | Charcoal night | `#1B1B1F` |
| Primary accent | Neon red (招牌紅) | `#E8443A` |
| Secondary accent | Neon jade (招牌青) | `#2EC4A9` |
| Gold (score/win) | Brass gold | `#D9A441` |
| Tile face | Warm ivory | `#F4EFE6` |
| Tile back | 麻雀綠 classic | `#1F7A5C` |
| Text on dark | Off-white | `#F2EDE4` |
| Danger/warning | Amber | `#E2A33C` |

Rules: neon accents for interactive elements (buttons, highlights, claim prompts); gold reserved for scoring moments; suit colors on tiles stay traditional (萬 red/black, 筒 blue/black, 索 green, 中 red, 發 green, 白 blue frame) for instant recognition.

## 3. Typography

- **Display (titles, 番種 names, win banners):** a HK-signage-flavored display face — target the look of 北魏楷書 neon signs. Licensed options to evaluate: justfont/THE 明體 display cuts, or commission a small custom set for ~30 key words (開枱/食糊/自摸/叮/碰/上/槓/流局/拉/踢半 + numerals). Fallback: Noto Serif TC Black.
- **UI body:** Noto Sans TC (Regular/Medium/Bold) — free, complete 繁中 coverage, crisp at small sizes.
- **Numerals (scores, timers):** tabular lining figures (Noto Sans TC tnum or a mono digit face) so counters don't jitter.
- Minimum body size 14 sp; 番 values in lists 16 sp bold gold.

## 4. Tile design

- Face: warm ivory with subtle top bevel + soft drop shadow; engraved-style glyphs (inner shadow) like real 象牙白 tiles; traditional glyph forms, slightly bolded for phone legibility.
- **百搭 tile:** ivory face, gold-foil 「百搭」 glyph with a neon-jade outer glow — must read as *special* at a glance and in the smallest river size.
- Back: 麻雀綠 with a faint mahjong-parlor lattice pattern.
- States: selected = tile rises 8 px + neon underglow; disabled (過水) = 40% desat + lock micro-icon; winning-tile highlight = gold pulse outline; 叮 discard = rotated 90° + subtle red corner tag.
- Three render sizes (own hand / melds & river / opponent minis) from one atlas per scale factor.

## 5. Environment & props

- Table: rosewood frame, green inlay play field, worn-edge texture (subtle). 2 alt themes post-v1 (茶餐廳 formica, dark tournament).
- Center hub: square 拉牌盒-style panel showing 圈風/局數/剩餘牌數/骰; dealer marker = brass 莊 coin; 拉莊 counter = stacked red chips with 拉N numeral.
- Frame dressing (non-play area): faint neon signs (「開枱」「夜麻雀」), window rain glow, hanging cable — all low-contrast so the table pops.
- Avatars: simple round icons (12–16 preset designs: 茶餐廳 iconography — 奶茶, 菠蘿包, 蛋撻, 雀友 caricatures) + name plate + seat wind chip (東南西北).

## 6. Motion design

Principles: fast (mahjong players hate waiting — every mandatory animation ≤ 400 ms, skippable/speed toggle), weighty (tiles slam with slight overshoot + haptic tick), celebratory only at wins.
Signature moments: deal sweep (staggered 40 ms/tile) · claim slam + neon flash of the action word (碰!) · 叮 = red stamp thunk on the rotated tile · win reveal = hand fans out, 番種 rows cascade in with gold count-up, big hands (≥100番) add neon-sign flicker + confetti · 拉 record = gold chain-link snaps between two avatars; 踢半 = chain shatters · dice = 3D-ish tumble in the center hub, 600 ms.

## 7. Audio direction

- **Voice:** Cantonese callouts — 上/碰/槓/食/自摸/叮/搶槓/雙響. v1: one neutral male + one female set; each AI/player assigned a set. Record clean, dry, short (< 600 ms).
- **SFX:** real mahjong foley (tile clack, shuffle 洗牌 wash, wall build, discard tap), dice rattle, brass ding for 番 count-up ticks, deep gong for 420番-class hands, soft 茶餐廳 ambience layer in lobby (cups, chatter — very low).
- **BGM:** lo-fi 港風 loops (electric piano + vinyl crackle, hints of 粵曲 samples) — lobby ≠ in-game tracks; in-game mix ducks under voice; all channels separately volume-controlled; default BGM low.

## 8. Iconography & UI chrome

Line icons with 2 px stroke, rounded caps, neon-accent active states. Buttons: pill shape, dark base, neon border glow when actionable, disabled = flat grey. Action buttons color-coded: 食 red / 碰 jade / 槓 gold / 上 blue / 叮 red-stamp style / 過 grey. Dialogs: dark card, thin gold rule line at top (mahjong-parlor menu vibe).

## 9. Accessibility

Colorblind-safe: suits distinguished by glyph, never color alone; optional high-contrast tile set. Large-tile mode (+20%). All voice/SFX have visual equivalents (claim words flash as text). Haptics on claim windows & own-turn start, toggleable.

## 10. Store/branding assets

App icon: single ivory tile at an angle showing 「開」 glyph with neon-red glow on charcoal. Feature graphic: table-top view, fanned winning hand, neon sign title. Screenshots follow palette; captions in 繁中 display type.
