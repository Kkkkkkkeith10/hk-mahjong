# mj_app — 香港十六張麻雀 Flutter client

Release-candidate single-player build (you vs 3 bots) on top of
`mj_core`, with Keith's final art installed (tiles, avatars, felt,
app icon). Publishing steps live in `../publishing/PUBLISHING.md`.

## Run it (on your machine)

```bash
# 1. verify the engine port first (one-time)
cd mj_core
dart pub get
dart test          # replays fans/settle/game golden fixtures from Python

# 2. bootstrap the app's platform folders (one-time)
cd ../mj_app
flutter create --platforms=android,ios .   # adds android/ ios/ around lib/
flutter pub get
dart run flutter_launcher_icons            # generates launcher icons
flutter run
```

`flutter create .` only generates the missing platform scaffolding; it
will not touch `lib/`, `pubspec.yaml`, or `assets/`.

## What's in the build

| Screen | File | Notes |
|---|---|---|
| 主頁 | `lib/screens/home_screen.dart` | 開房/入房 stubbed (M3 online); 單機 live; 燒賣仔 avatar strip |
| 開房設定 | `lib/screens/setup_screen.dart` | presets 協會新章/新手場/百搭歡樂場; 百搭 0/4/8, 換牌 off/換三張/擲骰, 拉·踢半 toggle, 4/8/16局 |
| 對局枱面 | `lib/screens/game_screen.dart` | landscape, jade felt texture, avatar seat badges, action pills 食/碰/槓/上/叮/過, win overlay, 完場結算 |
| 番表管理 | `lib/screens/fan_editor_screen.dart` | edits persist across restarts (shared_preferences diff vs official); 還原官方 resets + clears |
| 規則書 | `lib/screens/rules_screen.dart` | 玩法概要 (own words) + 番種圖鑑 (from fan_table.json) |
| 設定 | `lib/screens/settings_screen.dart` | bot speed 快/中/慢 (persisted), sound toggle (pack lands later), about |

Game loop: `lib/model/game_controller.dart` — mj_core `Engine` per 局,
seat 0 = human (prompts via Completers), seats 1–3 = `L1Policy` paced
per the settings speed. Dealer rotation, 連莊拉N, persistent 拉 ledger,
match-end wipe. Persistence: `lib/model/app_settings.dart`.

## Assets (installed)

- Tiles: `assets/tiles/*.png` — 44 files, 256×352 RGBA. TileView still
  falls back to drawn glyphs if a file is ever missing.
- Avatars: `assets/avatars/` — seat order: siumai_jai(你),
  milk_tea_sam_si, egg_tart_go, pineapple_bun_jai
  (`avatarAssets` in game_controller.dart).
- Table felt: `assets/table/felt_jade.png` (game-screen background).
- App icon: `assets/icon/app_icon_512.png` (flutter_launcher_icons
  config in pubspec; adaptive background `#F6EDDC`).
- Still pending: display font (2-line change in `lib/theme.dart` once a
  .ttf lands) and the sound pack.

## Remaining scope (deliberate)

- 開房/入房 online rooms = M3 (Firebase).
- Sound effects — toggle exists, pack ships in an update.
- Rule interpretation gaps are logged as VERIFY-1..19 in
  `../data/VERIFICATION-fan-table.md` — engine picks a documented
  reading for each; flip them once Keith rules.
