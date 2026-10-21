# Releases and updates

## Versions

Every release is named `YYYYMMDD.N`: the UTC date of the workflow run, then that day's release count from 1
(`20261021.1`, `20261021.2`, … `20261021.10`, then `20261022.1`). The same string is the Git tag, the release name,
and both `CFBundleShortVersionString` and `CFBundleVersion`. Sparkle compares versions component by component as
numbers, so `.10` is newer than `.9` and a new day is newer than any earlier counter.
`tests/tot-core-tests/release-version-ordering-tests.swift` pins this against Sparkle's own comparator. Local
builds are version `0`, so any release counts as newer.

## Workflow

`.github/workflows/release.yml`:

- **check**: runs on every pull request and push. It runs swift-format lint, prettier, `bun test` (Swift unit
  tests plus release-script tests), and a Debug build. Hosted runners can't grant XCUITest accessibility access,
  so `bun run test:e2e` runs locally only.
- **release**: runs after **check** passes, on pushes to `main` that change more than Markdown or `docs/`, and on
  manual runs (**Actions → CI and release → Run workflow** on `main`). It:
  1. Picks the version with `scripts/release-version.ts`. If this commit already has a release tag, it reuses
     that tag, and stops early if the release is already published, so reruns are idempotent.
  2. Builds a universal Release app with `scripts/build-release.sh`, which also checks the stamped version and
     both architectures.
  3. Signs `Tot.zip` with the EdDSA key, renders `appcast.xml`, and verifies the signature, length, and versions
     with WebCrypto, independently of Sparkle's tools.
  4. Creates a draft with both assets, publishes it as Latest, then downloads the public feed and archive to
     verify them again.

Releases are serialized (`concurrency: release`), so two runs can't claim the same number. A newer pending run
replaces an older pending one, and a run whose commit is no longer the tip of `main` doesn't publish; the newest
commit's release includes the skipped ones. Releases and tags
created with `GITHUB_TOKEN` don't trigger workflows, so a release never starts another run.

## Updates in the app

Tot uses [Sparkle 2](https://sparkle-project.org) (`app/tot/update-controller.swift`). The feed is
`https://github.com/dakdevs/tot/releases/latest/download/appcast.xml`; GitHub's `latest` alias skips drafts and
prereleases, and Sparkle never offers a version lower than the installed one.

- Tot checks hourly, including at launch when the last check is more than an hour old. When a newer release exists, Sparkle's alert comes to the front, since
  Tot briefly becomes a regular app while it shows. It offers **Install Update**, **Remind Me Later** (asks again
  at the next check), and **Skip This Version**.
- Nothing installs without a click: `SUAutomaticallyUpdate` and `SUAllowsAutomaticUpdates` are off.
- **Settings → Updates** shows the version, an automatic-check toggle, the last result (checking, up to date,
  available, or the error), and **Check for Updates…**. A manual check also offers skipped versions.
- Sparkle refuses an archive unless its EdDSA signature matches `SUPublicEDKey` in `Info.plist`. It checks the
  signature before extracting the archive (`SUVerifyUpdateBeforeExtraction`).

## Signing

- **Update signing (EdDSA)** is separate from Apple code signing. The private key lives in the maintainer's login
  Keychain (account `dev.dak.tot`; `generate_keys --account dev.dak.tot -p` prints the public key) and in the
  `SPARKLE_ED_PRIVATE_KEY` Actions secret. If the key is lost, installed copies can't verify future updates.
- **Apple signing.** Without Developer ID secrets, releases are ad-hoc signed and not notarized, and each
  release's notes state what the built app carries. To sign with Developer ID and notarize, add these repository secrets:
  `DEVELOPER_ID_P12_BASE64` and `DEVELOPER_ID_P12_PASSWORD` (a Developer ID Application certificate exported as
  .p12), plus `NOTARY_KEY_P8_BASE64`, `NOTARY_KEY_ID`, and `NOTARY_ISSUER_ID` (an App Store Connect API key).
  Ad-hoc copies accept a Developer ID update, because the EdDSA signature still verifies.

## Local checks

```sh
bun run test:e2e                         # includes updater UI against local feeds (served by e2e/update-fixture-server.ts)
bun run test:update-install              # builds 20000101.1 and .2, installs .2 through Sparkle, checks relaunch
scripts/capture-readme-screenshots.sh    # regenerates docs/images from mock data
```

`test:update-install` signs with the Keychain key, so it runs only on the maintainer's Mac.
