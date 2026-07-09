#!/bin/bash
# G-Rump GitHub Release Script
# Usage: ./create-release.sh [version] [repo]
# Run this from the project root on your Mac after notarization is complete.

set -euo pipefail

TAG="${1:-v2.0.0}"
REPO="${2:-Aphrodine-wq/G-Rump}"

echo "=== G-Rump Release: $TAG ==="

# 1. Check if gh CLI is installed
if ! command -v gh &>/dev/null; then
    echo "Error: GitHub CLI (gh) not found. Install with: brew install gh"
    exit 1
fi

# 2. Check if authenticated
if ! gh auth status &>/dev/null; then
    echo "Error: Not authenticated. Run: gh auth login"
    exit 1
fi

# 3. Tag the release (if not already tagged)
if git rev-parse "$TAG" &>/dev/null; then
    echo "Tag $TAG already exists, using existing tag."
else
    echo "Creating tag $TAG..."
    git tag -a "$TAG" -m "G-Rump $TAG"
    git push origin "$TAG"
fi

# 4. Build the release zip if it doesn't exist
ZIP_PATH="dist/G-Rump.zip"
if [ ! -f "$ZIP_PATH" ]; then
    echo "Building release zip..."
    if [ -n "${DEVELOPER_ID:-}" ]; then
        make release-zip
    else
        echo "Warning: DEVELOPER_ID not set — building an unsigned (ad-hoc) zip."
        make zip
    fi
fi
VERSION="${TAG#v}"
cp "$ZIP_PATH" "dist/G-Rump-$VERSION.zip"

# 5. Create the GitHub release
echo "Creating GitHub release..."
gh release create "$TAG" \
    --repo "$REPO" \
    --title "G-Rump $TAG" \
    --notes-file RELEASE_NOTES.md \
    "dist/G-Rump-$VERSION.zip"

echo ""
echo "=== Release created! ==="
echo "View at: https://github.com/$REPO/releases/tag/$TAG"
