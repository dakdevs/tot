#!/opt/homebrew/bin/bash
# Builds a universal (arm64 + x86_64) Release Tot.app stamped with a date-based version, signs it,
# and zips it for Sparkle: build/release/Tot.app and build/release/Tot.zip.
#
#   scripts/build-release.sh 20261021.1
#
# Signing: DEVELOPER_ID_IDENTITY (a "Developer ID Application: …" identity in the keychain) signs with
# the hardened runtime and a secure timestamp; without it the app is ad-hoc signed. When NOTARY_KEY_PATH,
# NOTARY_KEY_ID, and NOTARY_ISSUER_ID are also set, the app is notarized and stapled.
set -euo pipefail
cd "$(dirname "$0")/.."

version="${1:?usage: build-release.sh <YYYYMMDD.N>}"
[[ "$version" =~ ^[0-9]{8}\.[1-9][0-9]*$ ]] || { echo "invalid release version: $version" >&2; exit 2; }

xcodegen generate --quiet
xcodebuild -project Tot.xcodeproj -scheme Tot -configuration Release -derivedDataPath build \
  -destination 'generic/platform=macOS' ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO \
  MARKETING_VERSION="$version" CURRENT_PROJECT_VERSION="$version" -quiet build

out=build/release
rm -rf "$out"
mkdir -p "$out"
ditto build/Build/Products/Release/Tot.app "$out/Tot.app"
app="$out/Tot.app"

identity="${DEVELOPER_ID_IDENTITY:--}"
sign=(codesign --force --sign "$identity")
[[ "$identity" == "-" ]] || sign+=(--options runtime --timestamp)
# Inside-out, per Sparkle's signing guide; the Downloader keeps its sandbox entitlements.
sparkle="$app/Contents/Frameworks/Sparkle.framework/Versions/B"
"${sign[@]}" "$sparkle/XPCServices/Installer.xpc"
"${sign[@]}" --preserve-metadata=entitlements "$sparkle/XPCServices/Downloader.xpc"
"${sign[@]}" "$sparkle/Autoupdate"
"${sign[@]}" "$sparkle/Updater.app"
"${sign[@]}" "$app/Contents/Frameworks/Sparkle.framework"
"${sign[@]}" "$app"
codesign --verify --deep --strict "$app"

for key in CFBundleVersion CFBundleShortVersionString; do
  actual=$(/usr/libexec/PlistBuddy -c "Print :$key" "$app/Contents/Info.plist")
  [[ "$actual" == "$version" ]] || { echo "$key is $actual, expected $version" >&2; exit 1; }
done
archs=$(lipo -archs "$app/Contents/MacOS/Tot")
[[ "$archs" == *arm64* && "$archs" == *x86_64* ]] || { echo "not universal: $archs" >&2; exit 1; }

if [[ "$identity" != "-" && -n "${NOTARY_KEY_PATH:-}" ]]; then
  ditto -c -k --sequesterRsrc --keepParent "$app" "$out/notarize.zip"
  xcrun notarytool submit "$out/notarize.zip" --key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" \
    --issuer "$NOTARY_ISSUER_ID" --wait
  xcrun stapler staple "$app"
  rm "$out/notarize.zip"
fi

ditto -c -k --sequesterRsrc --keepParent "$app" "$out/Tot.zip"
echo "$out/Tot.zip"
