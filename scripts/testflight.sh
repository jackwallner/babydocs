#!/bin/bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$DIR/.."

SCHEME="BabyDocs"
ARCHIVE_PATH="$PROJECT_DIR/build/BabyDocs.xcarchive"

cd "$PROJECT_DIR"

# The schema drift check went with the backend. There is no server, no database
# and no DTO that can fall out of step with one, so there is nothing here to
# verify before a build. See CLAUDE.md for why that is the architecture rather
# than a gap.
#
# One thing does need a human eye instead: docs/plan.html has to be published at
# its exact path before any build whose share links are live, because those links
# outlive the build that wrote them.

# Auto-increment build number so TestFlight never rejects a duplicate
echo "==> Bumping build number..."
CURRENT_BUILD=$(grep 'CURRENT_PROJECT_VERSION:' project.yml | sed 's/.*: *"\(.*\)".*/\1/')
NEXT_BUILD=$((CURRENT_BUILD + 1))
sed -i '' "s/CURRENT_PROJECT_VERSION: \"$CURRENT_BUILD\"/CURRENT_PROJECT_VERSION: \"$NEXT_BUILD\"/" project.yml
echo "    $CURRENT_BUILD -> $NEXT_BUILD"

echo "==> Regenerating Xcode project..."
if command -v xcodegen &> /dev/null; then
  xcodegen generate
else
  echo "warning: xcodegen not found. Using existing BabyDocs.xcodeproj."
fi

echo "==> Cleaning..."
xcodebuild -project BabyDocs.xcodeproj -scheme "$SCHEME" clean

echo "==> Archiving..."
xcodebuild -project BabyDocs.xcodeproj -scheme "$SCHEME" -configuration Release archive -archivePath "$ARCHIVE_PATH" -destination "generic/platform=iOS" -allowProvisioningUpdates

echo "==> Exporting & Uploading..."
exec "$DIR/upload-testflight.sh" "$ARCHIVE_PATH"
