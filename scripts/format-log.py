#!/usr/bin/env python3
"""Format a raw `adb logcat -v time` capture into the five-phase truncated
trace used by upstream-issue-draft.md's "Relevant log output" section.

Reads the file produced by scripts/capture-log.sh, segments it on the
observable lifecycle markers, and emits a Markdown block with one fenced
`shell` chunk per phase, ready to paste into the upstream issue body.

Phase boundaries are detected from log content, not from time:
  Phase 1: first onPause of the original Activity through the recreate.
  Phase 2: lifecycle.onCreate {activityCreateCount=2} through onResume.done.
  Phase 3: first `[InitBG] enter` after recreate through `start.returned`.
  Phase 4: from `start.returned` to ~10s after, or end of capture.
  Phase 5: everything after the Phase 4 window.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

# `adb logcat -v time` line shape:
#   MM-DD HH:MM:SS.mmm L/TAG    (PID): message
LINE_RE = re.compile(
    r"^(?P<date>\d{2}-\d{2})\s+"
    r"(?P<time>\d{2}:\d{2}:\d{2}\.\d{3})\s+"
    r"(?P<level>[VDIWEF])/"
    r"(?P<tag>[^(]+?)\s*\(\s*(?P<pid>\d+)\):\s*"
    r"(?P<msg>.*)$"
)

# The repro's Dart-side print() emits lines of the form:
#   [InitBG] 2025-05-19T11:55:51.530... start.calling
# which arrive in logcat under tag "flutter". Unwrap them so the curated
# trace shows the inline tag instead of the generic "flutter".
DART_PRINT_RE = re.compile(r"^\[(?P<tag>\w+)\]\s+\S+\s+(?P<body>.*)$")

NATIVE_TAGS = {"MainActivity", "BgPluginProbe", "TSLocationManager", "HeadlessTask"}

PHASE_TITLES = [
    ("Phase 1 — Healthy pre-swipe session ends",
     "`MainActivity` is paused, then destroyed. The plugin's `onTaskRemoved` fires shortly after; `TrackingService` begins its async teardown but is still foreground-promoted."),
    ("Phase 2 — User reopens while TrackingService FGS is alive",
     "The OS finds the process still pinned by `TrackingService` and reuses it. A new `MainActivity` instance is created against the same PID. The 5.1.2 fix engages — `BgPluginProbe` reports `matchesCurrent=true` at every probe site."),
    ("Phase 3 — Dart initialization on the new engine",
     "`bg.ready()` returns the post-`onTaskRemoved` state. `bg.start()` re-enables tracking and returns `enabled:true`. All listeners are re-registered. From Dart, everything looks normal."),
    ("Phase 4 — The wedge",
     "For ~10s the main isolate receives zero events. Headless continues to receive events from the same native source. The native side is firing; only main-engine dispatch is dead."),
    ("Phase 5 — Persistence",
     "Wedge persists for the lifetime of this `MainActivity`. Subsequent lifecycle cycles do not heal it."),
]


def parse(path: Path) -> list[dict]:
    rows: list[dict] = []
    for raw in path.read_text(errors="replace").splitlines():
        m = LINE_RE.match(raw)
        if not m:
            continue
        d = m.groupdict()
        tag = d["tag"].strip()
        msg = d["msg"].strip()
        if tag == "flutter":
            dm = DART_PRINT_RE.match(msg)
            if not dm:
                continue
            tag = dm.group("tag")
            msg = dm.group("body")
        elif tag not in NATIVE_TAGS:
            continue
        rows.append({"time": d["time"], "level": d["level"], "tag": tag, "msg": msg})
    return rows


def to_seconds(t: str) -> float:
    h, m, rest = t.split(":")
    s, ms = rest.split(".")
    return int(h) * 3600 + int(m) * 60 + int(s) + int(ms) / 1000.0


def find(rows: list[dict], pred, start: int = 0) -> int | None:
    for i in range(start, len(rows)):
        if pred(rows[i]):
            return i
    return None


def render(rows: list[dict]) -> str:
    out = []
    for r in rows:
        out.append(f"{r['time']}  {r['level']} {r['tag']:<22} {r['msg']}")
    return "\n".join(out)


def segment(rows: list[dict]) -> dict:
    recreate = find(rows, lambda r: r["tag"] == "MainActivity"
                    and "lifecycle.onCreate" in r["msg"]
                    and "activityCreateCount=2" in r["msg"])
    if recreate is None:
        return {"error": "no recreate (activityCreateCount=2) found — needs a real swipe-and-fast-reopen run."}

    p1_start = find(rows, lambda r: r["tag"] == "MainActivity" and "lifecycle.onPause" in r["msg"])
    if p1_start is None:
        p1_start = 0

    p3 = find(rows, lambda r: r["tag"] == "InitBG" and "enter" in r["msg"], recreate + 1)
    p4 = find(rows, lambda r: r["tag"] == "InitBG" and "start.returned" in r["msg"], (p3 or recreate) + 1)

    if p4 is not None:
        threshold = to_seconds(rows[p4]["time"]) + 10.0
        p5 = find(rows, lambda r: to_seconds(r["time"]) >= threshold, p4 + 1)
    else:
        p5 = None

    return {
        "p1_start": p1_start,
        "p2_start": recreate,
        "p3_start": p3 if p3 is not None else recreate,
        "p4_start": p4 if p4 is not None else (p3 if p3 is not None else recreate),
        "p5_start": p5 if p5 is not None else len(rows),
        "end": len(rows),
    }


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("log", help="path to raw filtered logcat capture (from capture-log.sh)")
    args = ap.parse_args()

    path = Path(args.log)
    if not path.exists():
        print(f"file not found: {path}", file=sys.stderr)
        return 2

    rows = parse(path)
    if not rows:
        print("No matching lines. Was the capture done with capture-log.sh (which sets the tag filter)?", file=sys.stderr)
        return 2

    seg = segment(rows)
    print("## Relevant log output")
    print()
    print("Curated trace from one captured wedge. Timestamps are device wall-clock from `adb logcat -v time`; the tag column shows the originating component (Dart `print()` lines have been unwrapped to their inline tag).")
    print()

    if "error" in seg:
        print(f"> Warning: {seg['error']}")
        print(">")
        print("> Showing the full filtered trace below; re-capture if the recreate did not happen.")
        print()
        print("```shell")
        print(render(rows))
        print("```")
        return 0

    starts = [seg["p1_start"], seg["p2_start"], seg["p3_start"], seg["p4_start"], seg["p5_start"]]
    ends = starts[1:] + [seg["end"]]

    for (title, blurb), s, e in zip(PHASE_TITLES, starts, ends):
        print(f"### {title}")
        print()
        print(blurb)
        print()
        chunk = rows[s:e]
        if not chunk:
            print("_(no lines in this phase — capture may be too short)_")
            print()
            continue
        print("```shell")
        print(render(chunk))
        print("```")
        print()

    return 0


if __name__ == "__main__":
    sys.exit(main())
