#!/usr/bin/env bash
# Capture the filtered logcat trace this repro needs to populate the
# upstream issue's "Relevant log output" section.
#
# Filters down to the tags this repro and the plugin emit:
#   MainActivity      - Kotlin lifecycle + configureFlutterEngine
#   BgPluginProbe     - reflective mActivity probe + FGS state probe
#   TSLocationManager - plugin native (onTaskRemoved, setActivity, tracking)
#   HeadlessTask      - plugin's destroyBackgroundIsolate logs
#   flutter           - Dart print() lines: [InitBG], [LocationService], [Headless]
#
# Usage:
#   scripts/capture-log.sh path/to/wedge.log
#
# Reproduce the wedge while this is running:
#   1. flutter run (cold launch). Wait for "Phase: running".
#   2. Swipe app from recents.
#   3. Within ~200ms, tap the app icon to reopen.
#   4. Wait ~10s until the red "WEDGE DETECTED" banner appears.
#   5. Ctrl-C this script.
#
# Then format for pasting into the issue body:
#   scripts/format-log.py path/to/wedge.log > truncated.md
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <output.log>" >&2
  exit 64
fi
out="$1"

command -v adb >/dev/null || { echo "adb not found in PATH" >&2; exit 127; }

devices="$(adb devices | awk 'NR>1 && $2=="device" {print $1}')"
if [[ -z "$devices" ]]; then
  echo "No adb devices attached. Plug in / start an emulator first." >&2
  exit 1
fi

# Clear the ring buffer so the capture only contains this session.
adb logcat -c

echo "Capturing to $out. Reproduce the wedge now; Ctrl-C when the WEDGE banner has been visible for a few seconds." >&2
exec adb logcat -v time \
  MainActivity:I \
  BgPluginProbe:I \
  TSLocationManager:I \
  HeadlessTask:D \
  flutter:I \
  '*:S' \
  | tee "$out"
