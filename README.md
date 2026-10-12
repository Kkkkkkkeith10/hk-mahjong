# hk-mahjong

A Hong Kong 16-tile mahjong game (港式台牌) for Android, built with Flutter. You play against three AI players, or online with friends in a private room. The rules follow the Hong Kong Mahjong Association rules by default, and every scoring rule (番種) can be edited to match your own table.

**Started:** 7 Jul 2026


## What is in this repo

| Folder | Contents |
|---|---|
| `mj_app/` | Flutter client: table UI, claim window, settlement, fan-table editor, online lobby |
| `mj_core/` | Dart rules engine (tiles, wall, hand decomposition, scoring, settlement), compiled to wasm for the server |
| `ref_engine/` | Python reference engine used to generate golden test fixtures for `mj_core` |
| `data/` | Default fan table (`fan_table.json`) and how it was checked |
| `game-design-doc/` | Game design document: rules, scoring, modes, UI/UX, multiplayer, AI, assets |
| `assets/` | Tiles, avatars, table art and app icon |
| `store/`, `publishing/` | Store listing, screenshots and privacy policy |

## Run it

```bash
cd mj_core && dart pub get && dart test
cd ../mj_app && flutter pub get && flutter run
```

## Configuration (nothing secret is committed)

| File (git-ignored) | Template | Used for |
|---|---|---|
| `mj_app/env.json` | `mj_app/env.example.json` | Supabase URL and anon key for online play (`--dart-define-from-file=env.json`; `run_app.bat` and `build_release.bat` pass it) |
| `mj_core/.env` | `mj_core/.env.example` | Same values plus an upload key for `upload_assets.bat` and `bin/test_mp.dart` |
| `mj_app/android/key.properties` + your `.jks` | `mj_app/android/key.properties.example` | Release signing; create your own upload keystore |

Without `env.json` the app still runs single-player.

## Screenshots

See `store/screenshot-1.png` to `store/screenshot-3.png`.


## Progress log

This public repo is a cleaned snapshot. The full development history stays private.

### July 2026

- 7 Jul: Started the game project and the Flutter home screen.
- 7 Jul: Matched all screens to the reference UI and added tile assets.
- 7 Jul: Gameplay UX: seat callouts, table animations, two-tap discard and clearer claim buttons.
- 7 Jul: Multiplayer, phase A: deterministic replay of a match.
- 7 Jul: Multiplayer, phase B: engine compiled to WebAssembly, deploy scripts and a remote smoke test.
- 7 Jul: Multiplayer, phase C: online client, lobby (開房/入房) and online table UI.
- 7 Jul: Android/iOS release setup and store assets.

## Licence

Code: MIT, see `LICENSE`. Art in `assets/` and `store/`: all rights reserved unless stated otherwise.
