#!/bin/bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$DIR/.."

SCHEME="BabyDocs"
ARCHIVE_PATH="$PROJECT_DIR/build/BabyDocs.xcarchive"
PLAN_URL="https://jackwallner.com/ios/babydocs/plan.html"
PRIVACY_URL="https://jackwallner.com/ios/babydocs/privacy-policy.html"
TEAM_ID="YXG4MP6W39"

cd "$PROJECT_DIR"

for arg in "$@"; do
  case "$arg" in
    --dry-run|--help|-h)
      exec "$HOME/ios/release/testflight.sh" --project BabyDocs.xcodeproj --scheme BabyDocs "$@"
      ;;
    --) break ;;
  esac
done

# The schema drift check went with the backend. There is no server, no database
# and no DTO that can fall out of step with one, so there is nothing here to
# verify before a build. See AGENTS.md for why that is the architecture rather
# than a gap.
#
# One thing does need a human eye instead: docs/plan.html has to be published at
# its exact path before any build whose share links are live, because those links
# outlive the build that wrote them.
echo "==> Checking published pages..."
LIVE_PLAN_FILE=$(mktemp "${TMPDIR:-/tmp}/babydocs-live-plan.XXXXXX")
LIVE_PRIVACY_FILE=$(mktemp "${TMPDIR:-/tmp}/babydocs-live-privacy.XXXXXX")
trap 'rm -f "$LIVE_PLAN_FILE" "$LIVE_PRIVACY_FILE"' EXIT

curl --fail --silent --show-error --location --max-time 20 \
  --output "$LIVE_PLAN_FILE" "$PLAN_URL"
curl --fail --silent --show-error --location --max-time 20 \
  --output "$LIVE_PRIVACY_FILE" "$PRIVACY_URL"

if ! cmp -s "$LIVE_PLAN_FILE" docs/plan.html; then
  echo "error: published shared-plan page differs from docs/plan.html" >&2
  exit 1
fi
if ! cmp -s "$LIVE_PRIVACY_FILE" docs/privacy-policy.html; then
  echo "error: published privacy policy differs from docs/privacy-policy.html" >&2
  exit 1
fi


# TestFlight release for BabyDocs. The shared fleet script does the work: bump the
# build in project.yml, xcodegen, archive Release signed with the App Store
# Connect API key, upload, then commit and push the bump once Apple accepts it.
# Flags (--upload-only, --no-bump, --clean, --post-archive) and credentials are
# documented in ~/ios/release/testflight.sh.
"$HOME/ios/release/testflight.sh" --project BabyDocs.xcodeproj --scheme BabyDocs --clean "$@" -- CODE_SIGN_IDENTITY="Apple Development" DEVELOPMENT_TEAM="$TEAM_ID"
exit $?
