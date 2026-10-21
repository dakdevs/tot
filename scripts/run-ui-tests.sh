#!/opt/homebrew/bin/bash
# Runs the XCUITest suite against fixture data; results land in build/ui.xcresult. Extra arguments go to
# xcodebuild (e.g. -only-testing:TotUITests/UpdateUITests); update tests need TEST_RUNNER_TOT_UPDATE_FIXTURE_URL.
set -euo pipefail
cd "$(dirname "$0")/.."
xcodegen generate --quiet
rm -rf build/ui.xcresult
xcodebuild -project Tot.xcodeproj -scheme Tot -derivedDataPath build \
  -resultBundlePath build/ui.xcresult test "$@"
