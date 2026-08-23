#!/usr/bin/env bash
# Export, validate, and upload a distribution IPA to TestFlight.
# The archive is signed by automatic development signing, then Xcode re-signs it
# with the App Store distribution profile during export. The final IPA is
# validated before the upload begins.
#
# Prerequisites: Xcode signed in (Xcode → Settings → Accounts) with team YXG4MP6W39.
#
# Usage:
#   ./scripts/upload-testflight.sh [path/to/BabyDocs.xcarchive]
#
# Default archive: ./build/BabyDocs.xcarchive

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ARCHIVE="${1:-$ROOT/build/BabyDocs.xcarchive}"
STBABYDOCS="$ROOT/build/upload-stbabydocs"
PLIST="$ROOT/AppStoreUploadOptions.plist"
EXPECTED_BUNDLE_ID="com.jackwallner.babydocs"
EXPECTED_TEAM_ID="YXG4MP6W39"
VERIFY_DIR="$(mktemp -d "${TMPDIR:-/tmp}/babydocs-export-verify.XXXXXX")"
KEY_DIR="$(mktemp -d "${TMPDIR:-/tmp}/babydocs-upload-keys.XXXXXX")"
trap 'rm -rf "$VERIFY_DIR" "$KEY_DIR"' EXIT

if [[ ! -d "$ARCHIVE" ]]; then
  echo "error: archive not found: $ARCHIVE" >&2
  echo "Create one first:" >&2
  echo "  cd babydocs && bash scripts/testflight.sh" >&2
  exit 1
fi

if [[ ! -f "$PLIST" ]]; then
  echo "error: missing $PLIST" >&2
  exit 1
fi

verify_archive_bundle() {
  local bundle="$1"
  local label="$2"
  local details="$VERIFY_DIR/${label// /-}.codesign.txt"

  [[ -d "$bundle" ]] || {
    echo "error: $label is missing: $bundle" >&2
    exit 1
  }

  local bundle_id
  bundle_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$bundle/Info.plist")
  [[ "$bundle_id" == "$EXPECTED_BUNDLE_ID" ]] || {
    echo "error: $label has bundle id $bundle_id, expected $EXPECTED_BUNDLE_ID" >&2
    exit 1
  }

  codesign --verify --deep --strict --verbose=2 "$bundle"
  codesign --display --verbose=4 "$bundle" >"$details" 2>&1
  grep -Eq "Authority=Apple (Development|Distribution)" "$details" || {
    echo "error: $label is not signed by an Apple certificate" >&2
    cat "$details" >&2
    exit 1
  }
  grep -Fq "TeamIdentifier=$EXPECTED_TEAM_ID" "$details" || {
    echo "error: $label is signed for the wrong team" >&2
    cat "$details" >&2
    exit 1
  }
}

verify_distribution_bundle() {
  local bundle="$1"
  local label="$2"
  local details="$VERIFY_DIR/${label// /-}.codesign.txt"
  local entitlements="$VERIFY_DIR/${label// /-}.entitlements.plist"

  [[ -d "$bundle" ]] || {
    echo "error: $label is missing: $bundle" >&2
    exit 1
  }

  local bundle_id
  bundle_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$bundle/Info.plist")
  [[ "$bundle_id" == "$EXPECTED_BUNDLE_ID" ]] || {
    echo "error: $label has bundle id $bundle_id, expected $EXPECTED_BUNDLE_ID" >&2
    exit 1
  }

  codesign --verify --deep --strict --verbose=2 "$bundle"
  codesign --display --verbose=4 "$bundle" >"$details" 2>&1
  grep -Fq "Authority=Apple Distribution" "$details" || {
    echo "error: $label is not signed by Apple Distribution" >&2
    cat "$details" >&2
    exit 1
  }
  grep -Fq "TeamIdentifier=$EXPECTED_TEAM_ID" "$details" || {
    echo "error: $label is signed for the wrong team" >&2
    cat "$details" >&2
    exit 1
  }

  codesign --display --entitlements :- "$bundle" >"$entitlements" 2>/dev/null
  if /usr/libexec/PlistBuddy -c 'Print :get-task-allow' "$entitlements" 2>/dev/null | grep -Fq true; then
    echo "error: $label still has get-task-allow" >&2
    exit 1
  fi
  if /usr/libexec/PlistBuddy -c 'Print :aps-environment' "$entitlements" 2>/dev/null | grep -Fq development; then
    echo "error: $label still has a development push entitlement" >&2
    exit 1
  fi
}

verify_archive_bundle \
  "$ARCHIVE/Products/Applications/BabyDocs.app" \
  "archive"

mkdir -p "$STBABYDOCS"
find "$STBABYDOCS" -maxdepth 1 -type f -name '*.ipa' -delete
echo "Exporting archive for App Store Connect..."
echo "  archive: $ARCHIVE"
echo "  plist:   $PLIST"

xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$STBABYDOCS" \
  -exportOptionsPlist "$PLIST" \
  -allowProvisioningUpdates

shopt -s nullglob
IPAS=("$STBABYDOCS"/*.ipa)
shopt -u nullglob
if [[ "${#IPAS[@]}" -ne 1 ]]; then
  echo "error: expected one exported IPA in $STBABYDOCS, found ${#IPAS[@]}" >&2
  exit 1
fi

IPA_VERIFY="$VERIFY_DIR/ipa"
mkdir -p "$IPA_VERIFY"
unzip -q "${IPAS[0]}" -d "$IPA_VERIFY"
verify_distribution_bundle "$IPA_VERIFY/Payload/BabyDocs.app" "exported-ipa"

if [[ -z "${ASC_API_KEY_ID:-}" || -z "${ASC_ISSUER_ID:-}" || -z "${ASC_KEY_PATH:-}" ]]; then
  CREDENTIALS="${HOME}/.baseball_credentials"
  if [[ -f "$CREDENTIALS" ]]; then
    source "$CREDENTIALS"
  fi
fi

if [[ -z "${ASC_API_KEY_ID:-}" || -z "${ASC_ISSUER_ID:-}" || -z "${ASC_KEY_PATH:-}" ]]; then
  echo "error: App Store Connect API credentials are required for the verified upload" >&2
  exit 1
fi

cp "$ASC_KEY_PATH" "$KEY_DIR/AuthKey_${ASC_API_KEY_ID}.p8"
chmod 600 "$KEY_DIR/AuthKey_${ASC_API_KEY_ID}.p8"
export API_PRIVATE_KEYS_DIR="$KEY_DIR"

echo "Validating the exported IPA with App Store Connect..."
xcrun altool --validate-app "${IPAS[0]}" \
  --api-key "$ASC_API_KEY_ID" \
  --api-issuer "$ASC_ISSUER_ID"

echo "Uploading the validated IPA to TestFlight..."
xcrun altool --upload-app -f "${IPAS[0]}" \
  --api-key "$ASC_API_KEY_ID" \
  --api-issuer "$ASC_ISSUER_ID"

echo "Uploaded verified distribution IPA: ${IPAS[0]}"
echo "Check App Store Connect TestFlight for Processing."
