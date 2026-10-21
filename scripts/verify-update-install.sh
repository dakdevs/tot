#!/usr/bin/env bash
# End-to-end install check on a maintainer Mac: builds release apps 20000101.1 (installed) and
# 20000101.2 (update), signs the update with Tot's EdDSA key from the login Keychain, serves the feed
# locally, lets UpdateInstallUITests click Install and Relaunch, then checks the bundle was replaced
# and the new version is running.
set -euo pipefail
cd "$(dirname "$0")/.."

work=build/update-install
rm -rf "$work"
mkdir -p "$work/feed"
scripts/build-release.sh 20000101.2 >/dev/null
mv build/release/Tot.zip "$work/feed/Tot.zip"
scripts/build-release.sh 20000101.1 >/dev/null
mv build/release/Tot.app "$work/Tot.app"

bin=build/SourcePackages/artifacts/sparkle/Sparkle/bin
signature=$("$bin/sign_update" --account dev.dak.tot -p "$work/feed/Tot.zip")
echo "Install check" >"$work/notes.txt"
bun scripts/appcast.ts render 20000101.2 "$signature" "$work/feed/Tot.zip" "$work/notes.txt" |
  sed "s#https://github.com/dakdevs/tot/releases/download/20000101.2/Tot.zip#http://127.0.0.1:8737/Tot.zip#" \
    >"$work/feed/appcast.xml"

bun -e "Bun.serve({ hostname: '127.0.0.1', port: 8737, fetch: (r) => new Response(Bun.file('$work/feed' + new URL(r.url).pathname)) })" &
server=$!
trap 'kill $server 2>/dev/null; pkill -f "$PWD/$work/Tot.app/Contents/MacOS/Tot" || true' EXIT

TEST_RUNNER_TOT_INSTALL_APP="$PWD/$work/Tot.app" TEST_RUNNER_TOT_INSTALL_FEED_URL=http://127.0.0.1:8737/appcast.xml \
  scripts/run-ui-tests.sh -only-testing:TotUITests/UpdateInstallUITests >"$work/ui-tests.log" 2>&1 ||
  { tail -40 "$work/ui-tests.log"; exit 1; }

for _ in {1..30}; do
  pgrep -f "$PWD/$work/Tot.app/Contents/MacOS/Tot" >/dev/null && break
  sleep 1
done
installed=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$work/Tot.app/Contents/Info.plist")
[[ "$installed" == 20000101.2 ]] || { echo "bundle is still $installed" >&2; exit 1; }
pgrep -f "$PWD/$work/Tot.app/Contents/MacOS/Tot" >/dev/null || { echo "updated app did not relaunch" >&2; exit 1; }
codesign --verify --deep --strict "$work/Tot.app"
echo "installed and relaunched 20000101.2"
