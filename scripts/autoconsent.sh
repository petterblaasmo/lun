#!/bin/bash
# DuckDuckGo's autoconsent (github.com/duckduckgo/autoconsent, MPL-2.0), as
# published on npm and unchanged, into Autoconsent/: the script each page
# runs, built to be injected as it is (dist/autoconsent.playwright.js), its
# rules in their compact form (rules/compact-rules.json), its licence and
# which release they are from. Lun's side is Sources/Search/Autoconsent.swift.
#
# Run by hand, never by the app: Lun fetches nothing. The script and the
# rules are a pair, so both come from the same release. Afterwards run
# `swift test --filter "SearchTests\.AutoconsentTests"`, which reads the new
# files, and say the new version in THIRD_PARTY_NOTICES.md.
#
#   scripts/autoconsent.sh            the latest release
#   scripts/autoconsent.sh 18.14.0    that one
set -euo pipefail
cd "$(dirname "$0")/../Autoconsent"
WANT="${1:-latest}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
(cd "$TMP" && npm pack --silent "@duckduckgo/autoconsent@$WANT" > /dev/null && tar xzf ./*.tgz)
cp "$TMP/package/dist/autoconsent.playwright.js" autoconsent.js
cp "$TMP/package/rules/compact-rules.json" rules.json
cp "$TMP/package/LICENSE" LICENSE
python3 -I -c 'import json, sys; print(json.load(open(sys.argv[1]))["version"])' "$TMP/package/package.json" > VERSION
echo "autoconsent $(cat VERSION)"
