#!/opt/homebrew/bin/bash
# Regenerates docs/images/overlay-*.png from mock data (docs/demo/demo-seed.sql) over a neutral backdrop.
set -euo pipefail
cd "$(dirname "$0")/.."

work=build/readme-screenshots
rm -rf "$work"
mkdir -p "$work"
sqlite3 "$work/demo.sqlite" <tests/fixtures/t3-schema.sql
sqlite3 "$work/demo.sqlite" <docs/demo/demo-seed.sql

swift docs/demo/backdrop.swift &
backdrop=$!
trap 'kill $backdrop 2>/dev/null || true' EXIT
sleep 5

TEST_RUNNER_TOT_SCREENSHOT_DATABASE="$PWD/$work/demo.sqlite" \
  scripts/run-ui-tests.sh -only-testing:TotUITests/ReadmeScreenshotUITests >"$work/ui-tests.log" 2>&1 ||
  { tail -40 "$work/ui-tests.log"; exit 1; }

xcrun xcresulttool export attachments --path build/ui.xcresult --output-path "$work/attachments" >/dev/null
mkdir -p docs/images
jq -r '.[].attachments[] | "\(.exportedFileName)\t\(.suggestedHumanReadableName)"' "$work/attachments/manifest.json" |
  while IFS=$'\t' read -r file name; do
    cp "$work/attachments/$file" "docs/images/${name%%_0_*}.png"
  done
ls docs/images
