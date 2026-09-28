#!/usr/bin/env bash
# Capture the raw App Store screenshots from a headless simulator.
#
#     ./scripts/capture-screenshots.sh
#     ./scripts/compose-screenshots.py
#
# Runs ScreenshotUITests against the leased pool device and pulls the named PNGs
# out of the .xcresult into fastlane/screenshots/raw/.
#
# The test writes each shot as an XCTAttachment as well as to the runner's own
# /tmp. The attachment is what this reads: the runner is sandboxed, so its /tmp
# is not the device's /tmp and the files are not where they look like they are.
#
# Capture must run on slot 1 (iPhone 17 Pro, 1206x2622). Bare checkout now uses
# iPhone 18 Pro on iOS 27. A different device changes the geometry the composer
# scales from, so never use `agent-sim checkout --any` for this.
set -euo pipefail

cd "$(dirname "$0")/.."
RAW="${2:-fastlane/screenshots/raw}"

if [ -n "${1:-}" ]; then
  UDID="$1"
else
  if ! UDID=$(agent-sim udid babydocs 2>/dev/null) || [ -z "$UDID" ]; then
    echo "No simulator lease. Run: agent-sim checkout babydocs --slot 1" >&2
    exit 1
  fi
fi

agent-sim boot babydocs >/dev/null
xcrun simctl status_bar "$UDID" override \
  --time 9:41 \
  --batteryState charged \
  --batteryLevel 100 \
  --cellularBars 4 \
  --wifiBars 3

xcodegen generate >/dev/null
DERIVED="$(mktemp -d "${TMPDIR:-/tmp}/babydocs-screenshot-derived.XXXXXX")"
RESULT="$DERIVED/capture.xcresult"
xcodebuild test \
  -project BabyDocs.xcodeproj \
  -scheme BabyDocs \
  -destination "id=$UDID" \
  -only-testing:BabyDocsUITests/ScreenshotUITests \
  -derivedDataPath "$DERIVED" \
  -resultBundlePath "$RESULT" \
  >/dev/null

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE" "$DERIVED"' EXIT
xcrun xcresulttool export attachments --path "$RESULT" --output-path "$STAGE" >/dev/null

mkdir -p "$RAW"
python3 - "$STAGE" "$RAW" <<'PY'
import json, re, shutil, sys
from pathlib import Path

stage, out = Path(sys.argv[1]), Path(sys.argv[2])

def attachments(node):
    """The manifest nests attachments under per-test entries, and the shape has
    moved between Xcode versions. Walking for the key is what survives that."""
    if isinstance(node, dict):
        for item in node.get("attachments", []):
            yield item
        for value in node.values():
            yield from attachments(value)
    elif isinstance(node, list):
        for value in node:
            yield from attachments(value)

seen = set()
for item in attachments(json.loads((stage / "manifest.json").read_text())):
    suggested = item.get("suggestedHumanReadableName", "")
    exported = item.get("exportedFileName")
    # XCTest appends an index and a UUID to keep names unique per run.
    name = re.sub(r"_\d+_[0-9A-F-]{36}\.png$", ".png", suggested)
    if not name.endswith(".png") or name in seen or not exported:
        continue
    seen.add(name)
    shutil.copy(stage / exported, out / name)
    print(f"  {name}")

print(f"==> {len(seen)} raws")
PY
