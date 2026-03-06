# Magpie Release Runbook

This is the canonical process to ship a direct-distribution release (DMG + Sparkle appcast) from this repo.

## Important Sparkle Signing Note

For sandboxed Sparkle updates, do not sign `Magpie.app` with `codesign --deep`.

The working pattern is:
- re-sign Sparkle's embedded helpers first
- sign `Sparkle.framework`
- sign the top-level `Magpie.app` with entitlements, but without `--deep`

If you accidentally sign the app with `--deep`, Sparkle may still download and extract the update, but fail at installer launch with errors like:
- `Failed to submit installer job`
- `Failed to gain authorization required to update target`
- `If your application is sandboxed please follow steps at: https://sparkle-project.org/documentation/sandboxing/`

The release/build scripts in this repo already implement the correct signing order. Preserve that logic.

## One-Time Setup (Per Machine)

1. Confirm Apple Developer signing identity exists:

```bash
security find-identity -v -p codesigning
```

Expected: `Developer ID Application: Good Feels Inc (HTPHAYLD9X)` appears.

2. Confirm notary profile exists:

```bash
xcrun notarytool history --keychain-profile "AC_NOTARY" >/dev/null
```

3. Confirm Sparkle signing key exists in Keychain:

```bash
.build/artifacts/sparkle/Sparkle/bin/generate_keys -p
```

If this says no key exists, run:

```bash
.build/artifacts/sparkle/Sparkle/bin/generate_keys
```

Then copy the printed public key into `SUPublicEDKey` in [Info.plist](/Users/jason/Development/CopyOfCopyClip/Magpie/Info.plist).

## Release Checklist (vX.Y.Z)

### 1. Prepare branch and version numbers

1. Start clean:

```bash
git fetch origin
git checkout main
git pull --ff-only
git status
```

2. Bump app version (example shown for `1.0.1`):
   - [Info.plist](/Users/jason/Development/CopyOfCopyClip/Magpie/Info.plist)
   - `CFBundleShortVersionString` -> target release version (for example `1.0.1`)
   - `CFBundleVersion` -> increment build number (for example `2`)

3. Commit version bump:

```bash
git add /Users/jason/Development/CopyOfCopyClip/Magpie/Info.plist
git commit -m "chore(release): bump version to <version>"
```

### 2. Build signed + notarized release artifacts

Set your release variables:

```bash
VERSION="1.0.1"
TAG="v${VERSION}"
REPO="Good-Feels/magpie"
```

Run:

```bash
./scripts/build-release.sh \
  --sign-identity "Developer ID Application: Good Feels Inc (HTPHAYLD9X)" \
  --notarize \
  --keychain-profile "AC_NOTARY" \
  --tag "$TAG" \
  --repo "$REPO"
```

This produces:
- `dist/Magpie.app`
- `dist/Magpie.dmg`
- `dist/Magpie.dmg.sha256`
- updated and Sparkle-signed [appcast.xml](/Users/jason/Development/CopyOfCopyClip/appcast.xml)

Hard gates before proceeding:
1. Script exits successfully.
2. Notarization completes (no errors in output).
3. `appcast.xml` contains a new enclosure URL for your tag and includes `sparkle:edSignature`.
4. Auto-update smoke test from the previous installed version succeeds before trusting the release as an updater base.

### 3. Commit appcast update

```bash
git add /Users/jason/Development/CopyOfCopyClip/appcast.xml
git commit -m "chore(release): update appcast for $TAG"
```

### 4. Tag and push

```bash
git tag -a "$TAG" -m "Magpie $TAG"
git push origin main
git push origin "$TAG"
```

### 5. Publish GitHub Release assets

```bash
gh release create "$TAG" \
  --repo "$REPO" \
  --verify-tag \
  --generate-notes \
  dist/Magpie.dmg \
  dist/Magpie.dmg.sha256
```

### 6. Post-release smoke test

1. Install from released DMG on a non-dev path (`/Applications`).
2. Launch once and ensure app opens without Gatekeeper warnings.
3. Trigger `Check for Updates` from settings:
   - expected: no signature/feed error.
   - expected: reports up-to-date on fresh install of that tag.
4. Test one real Sparkle hop from the prior installed version to the new version:
   - expected: download, extract, authorize, install, and relaunch all succeed.
   - if it fails after extraction or installer launch, inspect macOS logs for `Magpie`, `Installer`, and `org.sparkle-project.Sparkle`.

## Fast Rollback

If a release is bad after publish:

1. Delete that GitHub Release assets (or entire release).
2. Revert appcast commit on `main` and push.
3. Publish a fixed new patch version (for example `1.0.2`) with the same process.

Do not reuse tag names after public release.

## CI Workflow Notes

Workflow file: [release-direct.yml](/Users/jason/Development/CopyOfCopyClip/.github/workflows/release-direct.yml)

Required GitHub secrets:
- `MACOS_CERT_P12_B64`
- `MACOS_CERT_PASSWORD`
- `KEYCHAIN_PASSWORD`
- `MACOS_SIGN_IDENTITY`
- `APPLE_ID`
- `APPLE_TEAM_ID`
- `APPLE_APP_SPECIFIC_PASSWORD`

Current CI build intentionally uses `--skip-appcast` because Sparkle private key is local-Keychain based unless you explicitly provision Sparkle private key material for CI signing.
