# 09 · Asset Manifest
All visual assets follow 01-STYLE (茶餐廳/麻雀館 palette). Export: PNG atlases @1x/2x/3x (Flame sprite sheets) unless noted. Naming: `category_name_state@scale.png`.

---

## 1. Tiles (highest priority, gate for M3)

| Item | Count | Notes |
|---|---|---|
| Suit faces 萬/筒/索 1–9 | 27 | engraved-glyph style, traditional colors |
| Winds 東南西北 | 4 | |
| Dragons 中發白 | 3 | 白 = blue frame |
| Flowers 春夏秋冬梅蘭菊竹 | 8 | slightly ornate, distinct silhouettes |
| **百搭 face** | 1 | gold 「百搭」+ jade glow — must pop at river size |
| Tile back / side / face-down wall pair | 3 | 麻雀綠 lattice |
| **Total unique faces** | **43** + chrome | |

States rendered via engine (glow/raise/desat overlays), not per-face art — keeps atlas small. Sizes: hand 96×128 pt design base; river/meld 64×86; opponent minis 40×54.

## 2. Table & props

Table wood frame + green inlay (9-patch or full bg per aspect) · charcoal room backdrop with neon-sign dressing (2–3 layered PNGs, parallax-lite) · center hub panel (拉牌盒 style) · 莊 brass coin · 拉莊 red chip stack (numbered 1–9) · dice faces 1–6 + tumble sprite sheet · wind chips 東南西北 (small) · seat frame/name plate · robot badge · connection badges (wifi-off, AI) · room-code card + QR frame · 叮 red corner tag.

## 3. Avatars

12–16 preset round icons, 茶餐廳/雀友 theme: 奶茶, 菠蘿包, 蛋撻, 燒賣, 涼茶樽, 貓店長, 雀友伯伯/姨姨 caricatures, neon-sign glyphs… (128×128, flat with 1 accent). 4 reserved AI-mascot variants (robot-ified versions).

## 4. UI kit

Buttons: action pills 食/碰/槓/上/叮/過 (6 colorways × normal/pressed/disabled) · primary/secondary menu buttons · toggle, stepper, slider, radio-card (wizard presets) · countdown ring (shader or sheet) · dialog/sheet frames (dark + gold rule) · list cells (editor rows, 圖鑑 cards) · summary chip · ledger strip elements (chain link, broken chain, 口 dot) · tab bar · icons ≈ 30 line icons (settings, share, sound, voice, help, edit, save, replay, QR, exit, kick, crown/host, fairness-check, etc.).

## 5. VFX & animation sheets

Deal sweep trail · claim word flashes 上!/碰!/槓!/食!/自摸!/搶槓!/雙響! (display-type cards with neon burst, 7) · 叮 stamp · win fan glow · gold count-up particles · confetti (big win) · neon flicker overlay (≥100番) · 拉 chain link/shatter · dice tumble · 流局 wall-collapse · flower-replace sparkle · turn-glow ring · 過水 red flash.

## 6. Audio

**Voice (per pack: 9 lines):** 上/碰/槓/食/自摸/叮/搶槓/雙響/流局 — v1: 2 packs (M/F Cantonese), stretch 4. Studio-clean, < 600 ms, -16 LUFS.
**SFX (~20):** tile clack ×3 variants, shuffle wash, wall build, discard tap, draw slide, dice rattle+land, button tap, claim stinger, 叮 thunk, win fanfare small/large, gong (超大糊), brass tick (count-up), chain clink, chain shatter, 流局 sting, notification pop, error thud.
**BGM:** lobby loop + 2 in-game loops (lo-fi 港風), 60–90 s seamless, separate stems if affordable.

## 7. Data & content assets

`fan_table.json` (verified official 番種簡表 — M1 gate) · 番種 example-hand definitions for 圖鑑 (~150 curated hands, authorable as JSON tile lists — grind, can ship progressively) · rules reference text (own wording pending R1) · canned chat phrases (~12: 快啲啦/好牌!/唔好意思/食得好…) · sample-hand for editor preview · tutorial script · store listing copy 繁中.

## 8. Store assets

App icon 512 (ivory tile 「開」 neon glow) · feature graphic 1024×500 · ≥8 phone screenshots (table, win overlay, editor, wizard, 百搭, ledger, 圖鑑, lobby) with caption bands · privacy policy page · IARC questionnaire answers doc.

## 9. Production notes & order

Art critical path: tiles → table/hub → action buttons (playable M3) → win overlay/VFX → meta UI (M4) → avatars/dressing/store (M5–6). Tile faces are the one asset worth commissioning professionally if budget exists; everything else survives solo-dev quality. Fonts: verify Noto (OFL, fine) + any display face's embedding license before build. Voice: record both packs in one session (script above). All sources kept as SVG/Figma masters; atlas packing via `flame_texturepacker` pipeline.
