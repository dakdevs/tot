#!/opt/homebrew/bin/bash
# Generates the Xcode project from project.yml and builds Tot.app into build/.
set -euo pipefail
cd "$(dirname "$0")/.."
xcodegen generate --quiet
xcodebuild -project Tot.xcodeproj -scheme Tot -configuration "${CONFIGURATION:-Debug}" \
  -derivedDataPath build -quiet build
echo "build/Build/Products/${CONFIGURATION:-Debug}/Tot.app"
