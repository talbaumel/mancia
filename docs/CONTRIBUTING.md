# Contributing to Mancia

Thanks for taking a look. Mancia is intentionally small, so keep changes
focused and proportionate.

By participating you agree to abide by the
[Code of Conduct](../CODE_OF_CONDUCT.md).

## Setup

- macOS 14 or newer.
- A recent Xcode/Swift toolchain with Swift 6 support.
- GitHub Copilot CLI installed and signed in if you want to test the real
  provider:

```sh
npm install -g @github/copilot
copilot
```

## Build And Test

```sh
make build
make test
make app
make run
make rerun
```

For provider-only checks:

```sh
swift run Mancia --provider-check
echo "some text" | swift run Mancia --complete rewrite
```

The `Makefile` targets run through `./scripts/swift.sh`, a thin wrapper around
`swift` that keeps SwiftPM dependency resolution working in restricted
environments (some sandboxes force `safe.bareRepository=explicit`, which breaks
SwiftPM's internal `git` calls). It is a no-op otherwise, so plain `swift build`
and `swift test` are fine for normal local work; reach for the wrapper only if
dependency resolution fails.

`make run` is the fastest manual loop because it builds a real `.app` bundle.
Use `make rerun` when testing first-run permission behavior: it quits Mancia,
resets all TCC grants for its bundle identifier, rebuilds the app, and launches
it again. Accessibility must be granted again after this command.
To avoid re-granting Accessibility after every rebuild, use a stable local
signing identity:

```sh
CODESIGN_ID="Mancia Dev Signing" make run
```

### Manual edit-safety checks

After changing pasteboard or Accessibility code, use unsent draft text in
Teams and a native editor such as TextEdit:

- Select a span, run an action, and check the result and surrounding text.
  Include spaces beside the span, repeated spaces, emoji, and Hebrew text in
  the rich-text editor.
- Approve a whole-document edit and confirm it includes the entire draft.
  An empty draft must not send a placeholder or invent a selection.
- Undo a Mancia version, then run another action. Check that range offsets
  still target only the edited span.
- Change the field or its text during generation. Mancia must retain the
  output rather than paste into the changed target.
- Copy unrelated text during the operation. Cleanup must not overwrite that
  newer clipboard value. Do not send the test message.
- Enable **Settings → General → Show automatically after selecting text**.
  Check mouse drag/double-click, Shift-navigation, and Command-A selection.
  The ribbon should open once, after a short pause, without changing the
  clipboard or running an action. Carets, password fields, Mancia's own
  windows, and ordinary typing must not open it. An existing session must not
  be interrupted. Disable the toggle and confirm the shortcut still works.
  Repeat mouse and Command-A checks in a disposable VS Code editor with
  `editor.accessibilitySupport` at its default `auto`, including the first
  activation while Electron's Accessibility tree initializes. Allow a few
  seconds for that initial warm-up; no editor settings should be rewritten.

## Code Style

- Preserve Swift 6 strict-concurrency safety.
- Keep UI, hotkey, pasteboard, and Accessibility code on the main actor unless
  there is a clear reason not to.
- Keep provider and prompt logic testable with pure/static helpers.
- Surface user-facing failures as clear errors or panel state, not crashes.
- Avoid new dependencies unless the need is strong and discussed first.
- Keep files small and aligned with the existing layout: `Ribbon/`, `Panel/`,
  `Providers/`, `Settings/`, and one primary type per file.

## Pull Requests

- Keep PRs focused.
- Run `make test` before opening a PR.
- Add or update tests for prompt/provider logic.
- Document manual testing for hotkey, panel, pasteboard, or Accessibility
  changes.

CI runs `swift build` and `swift test` on every pull request and on pushes to
`main` (see [.github/workflows/ci.yml](../.github/workflows/ci.yml)). Keep the
build warning-free and the tests green.

## Releasing

Push a version tag to make a release. Do not create releases in the GitHub UI.
The [release workflow](../.github/workflows/release.yml) builds and tests the
tag, packages `Mancia-<version>.dmg`, and publishes the release with the DMG.
This repository has immutable releases, so the workflow attaches the DMG before
it publishes.

1. In a pull request, set `CFBundleShortVersionString` and `CFBundleVersion` in
   `Support/Info.plist` to the new version. In `CHANGELOG.md`, move the
   `[Unreleased]` entries under a dated heading for that version. A test fails
   if the newest changelog version and the plist version are different.
2. Merge the pull request.
3. Tag the merge commit on an up-to-date `main` and push the tag:

```sh
git switch main && git pull
git tag 0.5.0
git push origin 0.5.0
```

The workflow writes the tag version into the app's `Info.plist`. It removes a
leading `v` if there is one.

See [ARCHITECTURE.md](ARCHITECTURE.md) for the current app structure and
[SPEC.md](SPEC.md) for implementation notes.
