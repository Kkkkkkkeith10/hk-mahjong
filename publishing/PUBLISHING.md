# Publishing checklist — 香港十六張麻雀 v1.0 (single-player release)

Everything below runs on Keith's machine. Items marked ☐ are yours;
code-side items are already done in the repo.

## 0. Sanity (already scripted)

- ☐ `cd mj_core && dart pub get && dart test` — golden parity green
- ☐ `cd mj_app && flutter create --platforms=android,ios . && flutter pub get`
- ☐ `flutter run` — full playtest: one 4-局 match, one 百搭歡樂場 match,
  edit a fan value → kill app → relaunch → value survived

## 1. App identity

- ☐ Application ID: pick a reverse-domain id you own, e.g.
  `com.keithlau.hkmahjong16` — set in `android/app/build.gradle`
  (`applicationId`). **Cannot be changed after first Play upload.**
- ☐ App name: edit `android/app/src/main/AndroidManifest.xml`
  `android:label="香港十六張麻雀"`.
- ☐ Icons: `dart run flutter_launcher_icons` (config already in
  pubspec — generates adaptive icons from `assets/icon/app_icon_512.png`
  with cream `#F6EDDC` background).
- Version: pubspec is `1.0.0+1`. Bump the `+N` build number on every
  Play upload.

## 2. Android release config

- ☐ Create an upload keystore (once, and BACK IT UP — losing it means
  losing the app listing):
  ```
  keytool -genkey -v -keystore ~/upload-keystore.jks -keyalg RSA \
    -keysize 2048 -validity 10000 -alias upload
  ```
- ☐ Create `android/key.properties` (never commit it):
  ```
  storePassword=...
  keyPassword=...
  keyAlias=upload
  storeFile=/Users/keith/upload-keystore.jks
  ```
- ☐ Wire signing into `android/app/build.gradle` per the standard
  Flutter docs snippet (signingConfigs.release + key.properties load).
- ☐ Build: `flutter build appbundle --release` → upload the `.aab`.
- Orientation: the game screen forces landscape itself; leave the
  manifest unrestricted so menus stay portrait.

## 3. Play Console setup

- ☐ Developer account ($25 one-time). NOTE: new personal accounts must
  run a closed test with ≥12 testers for 14 continuous days before
  production access — recruit the testers now, not later.
- ☐ Create app → 繁體中文 (香港) as default language.
- ☐ Store listing: copy in `publishing/store-listing.md`; screenshots —
  take from a real device/emulator: home, setup, gameplay with pills
  showing, win overlay, fan editor (2–8 phone screenshots, 16:9 or 9:16).
- ☐ Privacy policy: host `publishing/privacy-policy.md` at a public URL
  (GitHub Pages is fine) and link it in Play Console.
- ☐ Data safety form: declare **no data collected, no data shared** —
  true for this build (everything is on-device; no network calls, no
  ads, no analytics). Re-do this form when M3 (Firebase) lands.
- ☐ Content rating questionnaire: card/board game, **no real-money
  gambling** — the game uses points only, no purchases, no cash-out.
  Expect a low age rating; answer the simulated-gambling questions as
  "simulated gambling: no" (no wagering mechanic; scores only). If the
  reviewer classifies mahjong scoring as simulated gambling, accept the
  higher rating rather than appeal — it doesn't block release.
- ☐ App category: 紙牌／桌遊 (Card/Board). Ads declaration: none.
- ☐ Closed testing track → 14 days → apply for production.

## 4. iOS (optional, later)

Apple Developer $99/yr; `flutter build ipa`; App Store review is
stricter about gambling-adjacent apps — the "points only, no purchase,
no payout" positioning matters. Park this until Android is live.

## 5. When M3 (online rooms) ships — re-visit

- Data safety form (accounts, matchmaking data)
- Privacy policy update (Firebase, identifiers)
- Server region + Firestore rules review

## Out of scope for v1.0 (tracked, deliberate)

- Sound effects (toggle exists; pack lands in an update)
- 番表 sharing between friends (with M3)
- VERIFY-1..19 rulings — engine currently uses the documented default
  readings; each ruling that changes behaviour should bump the app
  version and regenerate golden fixtures.
