# Publishing guide — 香港十六張麻雀

Everything below the "YOU do" lines needs Keith personally (account/payment/identity).
Everything else is already done or scripted.

## State (2026-07-07)
- Android app id: `com.keithlau.hkmahjong` (permanent — never change)
- iOS bundle id: `com.keithlau.hkmahjong` (configured; building needs a Mac + Apple Developer US$99/yr)
- Signing: `mj_app/android/upload-keystore.jks` + `mj_app/android/key.properties`
  (both git-ignored). **BACK BOTH UP** — password manager / private cloud.
  Play App Signing will hold the real signing key; the upload key can be reset if lost.
- Release bundle: `mj_app/build/app/outputs/bundle/release/app-release.aab`
  (rebuild anytime with `mj_app/build_release.bat`)
- Store assets: `store/` — icon 512 (`../assets/app_icon_512.png`),
  feature graphic (`feature-graphic-1024x500.png`), screenshots
  (`screenshot-1.png` … `screenshot-3.png`, 2448×1377 16:9),
  listing text (`play-listing.md`), privacy policy (`privacy-policy.html`)

## Step 1 — YOU do: create the Play developer account
1. Go to https://play.google.com/console/signup
2. Sign in with your Google account → choose **Personal** account type
3. Pay the US$25 one-time fee, complete identity verification (can take a day or two)

Note for new personal accounts: before you can publish to PRODUCTION, Google requires
a **closed test with at least 12 testers opted-in for 14 consecutive days**. Internal
testing (up to 100 testers by email) is available immediately — that's our first stop.

## Step 2 — YOU do: put the privacy policy online
Any public URL works. Easiest: push `store/privacy-policy.html` to a GitHub repo and
enable GitHub Pages, or use any static host. Keep the URL — the console requires it.

## Step 3 — Create the app in Play Console (I can drive this with you)
- Create app → name 香港十六張麻雀, default language Chinese (Hong Kong) zh-HK,
  App (Game), Free
- App content forms: privacy policy URL; ads = No; data safety (collects: user IDs
  [anonymous auth] + in-app actions [game moves], not shared, not optional for
  multiplayer, deletable on request via email); content rating questionnaire
  (gambling-themed card/board game, no real money) — expect PEGI 12/Teen-ish for
  simulated gambling; target audience 13+ (do NOT target children).
- Store listing: copy from `play-listing.md`, upload icon + feature graphic +
  at least 2 screenshots (16:9 landscape ones are in `store/`).

## Step 4 — Internal testing release
Testing → Internal testing → Create release → upload `app-release.aab`
→ add tester emails (your own + friends) → rollout. Testers install via the opt-in
link on their Android phones.

## Step 5 — The 14-day closed test → production
Promote the build to Closed testing, recruit 12+ testers, wait 14 days,
then apply for production access in the console.

## iOS (later, needs a Mac)
1. Apple Developer Program (US$99/yr), Xcode on a Mac
2. `flutter build ipa` in `mj_app/` on the Mac (bundle id already set)
3. Upload via Xcode/Transporter → TestFlight (Apple's testing track) → App Store review

## Version bumps
Edit `version:` in `mj_app/pubspec.yaml` (e.g. `1.0.1+2` — the `+N` is the Play
versionCode and must increase every upload), then rerun `build_release.bat`.
