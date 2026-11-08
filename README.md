# ScrollAuto

Android app (Flutter + Kotlin) that scrolls **Instagram Reels** and **YouTube Shorts** for you:

- **Auto-scroll when a reel ends**: watches the video's progress bar and swipes to the next reel when it finishes or loops.
- **Fallback timer**: if the app doesn't show a progress bar (common on Instagram), swipes after N seconds.
- **Hand gestures**
  - **Wave** (proximity sensor): wave over the top of the phone to go to the next reel. Cover the sensor for about 1.5 s to pause or resume auto-scroll. Low battery use.
  - **Air swipe** (front camera): move your hand up for the next reel, down for the previous one. There's an "invert" switch if your phone's camera is mounted the other way.

## Install (from your phone)

1. Every push to `main` builds the app with GitHub Actions.
2. Open **Releases → "ScrollAuto (latest build)"** and download `scrollauto.apk`.
3. Install it. Allow "install unknown apps" for your browser if asked.

### "App blocked to protect your device" (Play Protect)

In India (and some other countries), Play Protect blocks any app installed from a browser or file manager if it uses an Accessibility service. ScrollAuto needs one to swipe, so the block can't be avoided in code. To install it:

1. Play Store → your profile picture → **Play Protect** → ⚙️ → turn off **Scan apps with Play Protect**. This can't be changed during a phone call.
2. Install `scrollauto.apk`.
3. Turn **Scan apps with Play Protect** back on.

## First-time setup

1. Open ScrollAuto and tap **Enable service**. Turn on *ScrollAuto* under Accessibility → Installed apps.
2. If the toggle is greyed out ("Restricted setting", Android 13+ for sideloaded apps), go to **App info → ⋮ → Allow restricted settings** and try again.
3. Optional: pick a gesture mode. A small notification stays visible while the gesture listener is running.
4. Open Reels or Shorts. The status line in ScrollAuto shows what it's detecting.

## How it works

| Part | File |
|---|---|
| Flutter UI (settings and status) | `lib/main.dart` |
| Accessibility service: finds the reel screen and progress bar, performs swipe gestures | `android/.../ScrollAccessibilityService.kt` |
| Foreground service for gestures (proximity and camera) | `android/.../GestureService.kt` |
| Camera motion detector (32×24 frame-difference grid, no ML) | `android/.../CameraMotionDetector.kt` |
| Settings shared between Flutter and Kotlin | `android/.../Prefs.kt` |

**End-of-reel detection:** the service walks the window's accessibility tree every 400 ms, looking for:
- view IDs that mark the reel player (`reel_…` / `shorts` for YouTube, `clips_…` for Instagram), and
- the widest visible node with `RangeInfo` (the progress bar).

When progress reaches 98%, or jumps from above 75% back to the start (the video looped), it swipes up.

## Limitations

- Instagram and YouTube change their UI often. If the status says "Open a reel / short to start" even while you're on Reels, turn off **Only on Reels / Shorts screen**.
- Many Instagram reels don't expose a progress bar at all, so set the **fallback timer** (for example 20–30 s).
- Air-swipe works best in decent light with the phone held upright.

## Building locally

The repo only contains the app's own source files. Generate the rest once:

```bash
flutter create --platforms=android --org com.amaljith --project-name scrollauto .
flutter build apk --release
```
