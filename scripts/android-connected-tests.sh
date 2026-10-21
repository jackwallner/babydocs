#!/bin/bash
# Runs the Android instrumented tests (SmokeTest) on a booted emulator on this
# fleet machine (jmbp or jmbp2), one test per process with cleared app data.
# Prints a per-test result, writes JUnit XML, and exits non-zero on any failure
# or a zero executed count.
#
#   ANDROID_SERIAL=emulator-5556 scripts/android-connected-tests.sh [--no-build]
#
# The reviewer-code test reads PLAY_REVIEW_CODE from ~/.babydocs_credentials and
# passes it as an instrumentation argument; it never enters the repo.
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
serial="${ANDROID_SERIAL:?set ANDROID_SERIAL to the leased emulator}"
adb="$HOME/Library/Android/sdk/platform-tools/adb -s $serial"
pkg="com.jackwallner.babydocs"
runner="$pkg.test/androidx.test.runner.AndroidJUnitRunner"
test_class="$pkg.SmokeTest"
review_code="$(grep '^PLAY_REVIEW_CODE=' "$HOME/.babydocs_credentials" 2>/dev/null | cut -d= -f2 || true)"

if [[ "${1:-}" != "--no-build" ]]; then
  (cd "$repo/android" && JAVA_HOME="${JAVA_HOME:-$HOME/jdks/temurin-17/Contents/Home}" ./gradlew -q assembleDebug assembleDebugAndroidTest)
fi
apk="$repo/android/app/build/outputs/apk/debug/app-debug.apk"
test_apk="$repo/android/app/build/outputs/apk/androidTest/debug/app-debug-androidTest.apk"

if [[ "$($adb shell getprop sys.boot_completed | tr -d '\r')" != "1" ]]; then
  echo "$serial is not booted." >&2
  exit 1
fi
$adb install -r -t "$apk" >/dev/null
$adb install -r -t "$test_apk" >/dev/null

tests="$(grep -oE '@Test fun [A-Za-z0-9_]+' "$repo/android/app/src/androidTest/java/com/jackwallner/babydocs/SmokeTest.kt" | awk '{print $3}')"
passed=0
failed=0
raw_dir="$repo/android/app/build/outputs/androidTest-results/connected/raw"
rm -rf "$raw_dir" && mkdir -p "$raw_dir"
for t in $tests; do
  $adb shell pm clear "$pkg" >/dev/null
  out="$($adb shell am instrument -r -w -e reviewCode "$review_code" -e class "$test_class#$t" "$runner")"
  printf '%s\n' "$out" > "$raw_dir/$t.txt"
  if grep -q 'OK (1 test)' <<<"$out"; then
    echo "PASS $t"
    passed=$((passed + 1))
  else
    echo "FAIL $t"
    grep -m1 'stack=' <<<"$out" || true
    failed=$((failed + 1))
  fi
done
$adb shell pm clear "$pkg" >/dev/null

report="$repo/android/app/build/outputs/androidTest-results/connected/TEST-babydocs-smoke.xml"
python3 "$repo/scripts/android-instrument-junit.py" "$report" "$raw_dir"/*.txt || true
echo "Executed $((passed + failed)) instrumented tests on $serial: $passed passed, $failed failed."
[[ $failed -eq 0 && $passed -gt 0 ]]
