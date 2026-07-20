# Token King Release Workflow

Token King has two intentionally different distribution paths. Do not confuse
an ad-hoc local install with a public, notarized release.

## 1. Local development install

Use this only to test the app and desktop widget on the current Mac:

```bash
make release
make run
```

`make release` builds a Release app, installs it at `/Applications/Token King.app`,
ad-hoc signs the host and widget extension, and refreshes PlugInKit registration.
It is not suitable for distribution: Gatekeeper may require a one-time
right-click → Open after every rebuild.

## 2. Release readiness

Before creating a version tag, confirm the intended files only:

```bash
git status --short
make lint
make test-membership
make test-boundaries
xcodebuild test -project CopilotMonitor/CopilotMonitor.xcodeproj \
  -scheme CopilotMonitor -destination 'platform=macOS'
```

For widget-affecting releases, also run the real-desktop checklist in
`AGENTS.md` with `scripts/r18-manual-test.sh`.

Update the version through the release workflow input or a version tag; the
built app derives its version from git. Stage deliberately — never use a broad
`git add .` command — then commit the release notes and tag.

## 3. Signed and notarized GitHub release

The repository workflows are the source of truth for public artifacts:

- `.github/workflows/build-release.yml` builds every push and pull request;
  tags beginning with `v` and an explicit workflow version run the signed path.
- `.github/workflows/manual-release.yml` is the controlled manual release path.

The signed path imports the Developer ID certificate from GitHub Actions
secrets, creates a universal (`arm64` + `x86_64`) archive, notarizes the app
and DMG, staples both, generates the appcast, and uploads
`Token-King-<version>.dmg` to GitHub Releases.

Required repository secrets are managed only in GitHub Actions:

- Developer ID certificate and password
- keychain password and Apple team ID
- notarization credentials
- Sparkle signing material, when appcast publication is enabled

Never put these values in source files, shell history, release notes, or this
document.

## 4. Artifact acceptance

Download the published DMG on a clean macOS account and confirm:

```bash
spctl --assess --type open --context context:primary-signature "Token King.app"
codesign --verify --deep --strict --verbose=2 "Token King.app"
xcrun stapler validate "Token King.app"
xcrun stapler validate "Token-King-<version>.dmg"
```

The release is complete only when the DMG, app signature, notarization ticket,
universal slices, appcast entry, and widget registration all agree on the same
version.
