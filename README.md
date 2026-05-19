# flutter_bg_wedge_repro

Minimal repro for the flutter_background_geolocation Android wedge issue through fast restart while TrackingService FGS is alive.

## Issue Description

This app reproduces a bug in `flutter_background_geolocation: 5.1.2` on Android where:
1. User swipe-kills app from recents
2. User reopens within ~200ms while the plugin's `TrackingService` is still foreground-promoted
3. The recreated `MainActivity` attaches a new `FlutterEngine` 
4. Main-isolate listeners (`onLocation`, `onHeartbeat`, etc.) **never fire again**
5. Headless isolate continues receiving events normally (proving native source is alive)

The wedge persists until the user force-stops the app. App lifecycle bounces don't recover it.

See `../upstream-issue-draft.md` for the full technical analysis.

## Prerequisites

- Flutter 3.x with Dart 3.11+
- Android device or emulator
- Location permissions granted at OS level
- Fast fingers (or `adb shell am force-stop` + quick relaunch)

## Setup

```bash
flutter pub get
```

## How to Reproduce the Wedge

1. **Cold launch**: `flutter run` and wait for "Phase: running" in the UI
2. **Confirm healthy**: Watch `adb logcat | grep "LocationService\|Headless"` — you should see both main-isolate and headless events arriving
3. **Swipe-kill**: Swipe app from recents (don't use back button — that calls `onPause`/`onDestroy` differently)
4. **Fast reopen**: Within 200ms, tap the app icon to relaunch
5. **Observe wedge**: 
   - UI shows "Phase: running" and `bg.start: enabled=true`
   - Main-isolate event counts remain at 0
   - Headless events keep arriving: `adb logcat | grep Headless`
   - After 10s, UI shows red "WEDGE DETECTED" banner

## What to Look For

### Healthy session (cold launch):
```
[LocationService] onProviderChange.received {enabled:true}
[LocationService] onLocation.received {accuracy:12.3}
[Headless] event.fired {name:heartbeat}
```

### Wedged session (fast restart while FGS alive):
```
[Headless] event.fired {name:heartbeat}        ← headless keeps working
[Headless] event.fired {name:enabledchange}    ← native source is alive
```
**No `[LocationService]` events** — main isolate dispatch is dead.

### Diagnostic Logs

The MainActivity includes probes that confirm:
- `BgPluginProbe.mActivity.read {matchesCurrent=true}` — the 5.1.2 fix engaged
- `BgPluginProbe.fgs.state {trackingServiceForeground=true}` — TrackingService was alive during reattach

## Recovery

Force-stop the app (`Settings > Apps > flutter_bg_wedge_repro > Force Stop`) and cold-launch. The wedge only occurs on fast restart while `TrackingService` FGS is still alive.

## Config

This repro uses:
- `foregroundService: true` 
- `stopOnTerminate: true`
- `enableHeadless: true`
- `heartbeatInterval: 10` (for observable events)

Same config shape that triggers the issue in production SafeNow apps.

## Capturing the truncated log for the upstream issue

The upstream issue body asks for a curated five-phase trace under "Relevant log output". To produce one from a real run on your device:

```bash
# Terminal A — start the capture (clears logcat ring, filters to relevant tags)
scripts/capture-log.sh wedge.log

# Terminal B — cold launch, then reproduce per "How to Reproduce" above
flutter run

# Once the red "WEDGE DETECTED" banner has been visible for a few seconds,
# Ctrl-C the capture in Terminal A.

# Format the raw capture into the five-phase Markdown block:
scripts/format-log.py wedge.log > truncated.md
```

`truncated.md` is ready to paste into the upstream issue. The formatter segments on observable lifecycle markers (`activityCreateCount=2`, `InitBG enter`, `start.returned`) — if it warns that no recreate was found, the swipe-and-fast-reopen did not land in the same process and you'll need to re-capture with a tighter gap.

## Filing Upstream

This repro was built to accompany the upstream issue report to [flutter_background_geolocation](https://github.com/transistorsoft/flutter_background_geolocation/issues). The maintainer can `flutter run` this directly to observe the wedge on any Android device.