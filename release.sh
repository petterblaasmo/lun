#!/bin/bash
# Makes a release and puts it on GitHub as a draft, for a person to publish.
#
#   ./release.sh            the version in VERSION, as a draft release
#   ./release.sh --try      the same files, unnotarised, and nothing uploaded
#
# What it does:
#   1. ./build.sh release ship — the app signed with the Developer ID, the
#      disk image and the ZIP notarised, and the feed (appcast.json) written
#      and signed, naming this release's own files.
#   2. gh release create v<version> --draft, with its files: Lun.dmg for
#      people; Lun.zip, appcast.json and appcast.json.zip for the updater;
#      and the developer tools packages the feed offers.
#
# A draft is seen by nobody and changes nothing: the updater reads the
# newest *published* release (Updater.feed), so publishing the draft on
# GitHub is the moment everyone's Lun is offered it. Look the draft over,
# open the DMG on another Mac, then press Publish.
#
# Needs, once (see build.sh): a Developer ID Application certificate, and
#   xcrun notarytool store-credentials "search"
# and the GitHub CLI signed in: gh auth status.
#
# Apple silicon only for now: an Intel build has no feed (Updater.feed).
set -euo pipefail

cd "$(dirname "$0")"
REPO="petterblaasmo/lun"
VERSION="$(tr -d '[:space:]' < VERSION)"
TAG="v$VERSION"
STEP="ship"
[ "${1:-}" = "--try" ] && STEP="dmg"

[ "$(uname -m)" = "arm64" ] || { echo "release.sh builds the Apple silicon release; run it on one" >&2; exit 1; }
if [ "$STEP" = "ship" ]; then
  [ -z "$(git status --porcelain)" ] || { echo "uncommitted changes: a release is what is committed" >&2; exit 1; }
  [ "$(git rev-parse --abbrev-ref HEAD)" = "main" ] || { echo "a release is cut from main" >&2; exit 1; }
  gh release view "$TAG" -R "$REPO" >/dev/null 2>&1 && { echo "$TAG is already a release: raise VERSION first" >&2; exit 1; }
fi

# Apple's provisioning profile (issue 130). Without it the release still
# works, with three things off; said here in full, rather than build.sh
# stopping halfway with one line.
if [ "$STEP" = "ship" ] && [ ! -f "Search.provisionprofile" ]; then
  if [ -z "${SEARCH_ALLOW_NO_PASSKEYS:-}" ]; then
    cat >&2 <<'SAY'
There is no Search.provisionprofile here, so this release would ship with
passkeys, Sync with iCloud and the protected keychain (a proxy's password,
"Always allow" for a coding agent) turned off. Saved passwords still work.

Either put the profile beside build.sh (it is git-ignored; how to get one
is in issue 130), or release without those three:

  SEARCH_ALLOW_NO_PASSKEYS=1 ./release.sh
SAY
    exit 1
  fi
  echo "release: no provisioning profile; passkeys, Sync with iCloud and the protected keychain are off in this one"
fi

# The feed names this release's own files, which never move; the feed
# itself is read from the newest release.
export SEARCH_DOWNLOAD_URL="https://github.com/$REPO/releases/download/$TAG"
# The developer tools packages beside them: a release has no folders.
export SEARCH_DEVTOOLS_URL="$SEARCH_DOWNLOAD_URL"
./build.sh release "$STEP"

FILES=(build/Lun.dmg build/Lun.zip build/appcast.json build/appcast.json.zip build/devtools/*.zip)
for FILE in "${FILES[@]}"; do
  [ -f "$FILE" ] || { echo "$FILE is missing" >&2; exit 1; }
done

if [ "$STEP" = "dmg" ]; then
  echo "tried: ${FILES[*]} — unnotarised, nothing uploaded"
  exit 0
fi

# What is new, for the release's page: this version's part of the changelog.
NOTES="$(awk -v v="## $VERSION" '$0 == v { on = 1; next } on && /^## / { exit } on' CHANGELOG.md)"
# Pinned to the commit it was built from: a draft has no tag until it is
# published, and "main" by then may be newer than what is in it.
gh release create "$TAG" -R "$REPO" --draft --target "$(git rev-parse HEAD)" --title "Lun $VERSION" \
  --notes "${NOTES:-Lun $VERSION}" "${FILES[@]}"
echo "drafted: $TAG on GitHub — open the DMG on another Mac, then publish the draft"
