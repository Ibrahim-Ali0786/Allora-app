# Play Store release checklist

## 1. App identity (done in code)
- `applicationId` / `namespace`: **app.allorachat.messenger**
  (`com.example.*` is rejected by Play Console). Installs of the old debug
  package are a different app and won't upgrade in place.
- Version: `2.0.0+2` in `pubspec.yaml` — bump `+N` (versionCode) every upload.

## 2. Signing (you must do this once)
```bash
keytool -genkey -v -keystore ~/upload-keystore.jks -keyalg RSA \
        -keysize 2048 -validity 10000 -alias upload
```
Create `android/key.properties` (already gitignored — verify!):
```
storeFile=/absolute/path/upload-keystore.jks
storePassword=***
keyAlias=upload
keyPassword=***
```
`android/app/build.gradle` picks it up automatically; release builds are
minified + resource-shrunk with the provided proguard rules.

## 3. Backend hardening (strongly recommended before launch)
- Deploy `supabase/functions/allora-provision`, set
  `SYNAPSE_REGISTRATION_SECRET`, then **rotate** the old secret in
  `homeserver.yaml` and delete the legacy fallback block in
  `lib/main.dart` (`_registerAndLogin`). Until rotation, the old secret is
  still recoverable from previously shipped APKs.
- Deploy `supabase/functions/allora-ai` with `ANTHROPIC_API_KEY` to light up
  Allora AI (the app degrades gracefully without it).

## 4. Build & upload
```bash
flutter pub get
flutter test
flutter build appbundle          # -> build/app/outputs/bundle/release/app-release.aab
```
Upload the `.aab` in Play Console.

## 5. Store listing notes
- **Data safety form**: messages are relayed via your Matrix homeserver
  (matrix.allorachat.app); auth via Supabase (email/OTP); AI requests are
  proxied server-side; no ads, no analytics SDKs in the app.
- **Permissions used**: INTERNET, WAKE_LOCK, RECEIVE_BOOT_COMPLETED
  (background wipe/scheduled sends), USE_BIOMETRIC/USE_FINGERPRINT
  (app lock), VIBRATE (haptics). Camera/photos are accessed through the
  system picker (no broad storage permission).
- Provide a privacy policy URL (required for messaging apps).

## 6. Known post-launch work
- Push notifications for a killed app need a Matrix push gateway
  (sygnal + FCM). The in-app Notifications section already explains the
  current behaviour to users.
