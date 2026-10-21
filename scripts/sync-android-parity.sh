#!/bin/sh
# Compiles the iOS rule sources with scripts/android-export/main.swift and
# writes the Android port's reference data and parity fixture:
#   android/app/src/main/resources/babydocs-reference.json (states, offices,
#     counties, sources: loaded by the app, never transcribed)
#   android/app/src/test/resources/babydocs-parity.json (every rule evaluated
#     over a fixed input matrix, checked by PortParityTest)
# Rerun whenever Shared/Rules, Shared/Models enums, DateOnly or PlanSeed change.
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
# The enums only: everything above the first SwiftData model.
awk '/^\/\/ MARK: - Child/ { exit } { print }' "$root/Shared/Models/BabyModels.swift" | grep -v 'import SwiftData' > "$work/Enums.swift"
# macOS 12 toolchains lack TimeZone.gmt; the fallback is never taken.
sed 's/?? \.gmt/?? TimeZone(identifier: "UTC")!/' "$root/Shared/Utilities/DateOnly.swift" > "$work/DateOnly.swift"
# PlanSeed minus `make(child:profile:)`, which needs the SwiftData models.
awk '/@MainActor/ { skip = 1 } /MARK: - Links/ { skip = 0 } !skip { print }' "$root/Shared/Services/PlanSeed.swift" > "$work/PlanSeed.swift"
swiftc -O -o "$work/export" \
  "$work/Enums.swift" "$work/DateOnly.swift" "$work/PlanSeed.swift" \
  "$root/Shared/Rules/RequirementCatalog.swift" \
  "$root/Shared/Rules/SourceManifest.swift" \
  "$root/Shared/Rules/StateVitalRecords.swift" \
  "$root/Shared/Rules/USCounties.swift" \
  "$root/Shared/Services/DeterministicID.swift" \
  "$root/scripts/android-export/main.swift"
mkdir -p "$root/android/app/src/main/resources" "$root/android/app/src/test/resources"
TZ=America/Los_Angeles "$work/export" \
  "$root/android/app/src/main/resources/babydocs-reference.json" \
  "$root/android/app/src/test/resources/babydocs-parity.json"
