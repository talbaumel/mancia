<p align="center">
  <img src="docs/assets/mancia-logo.png" alt="Mancia logo" width="180">
</p>

<h1 align="center">Mancia</h1>

<p align="center">
  <b>Edit text with AI in any macOS app, without leaving the app you write in.</b>
</p>

<p align="center">
  <a href="https://github.com/talbaumel/mancia/releases/latest"><img src="https://img.shields.io/github/v/release/talbaumel/mancia?display_name=tag" alt="Latest release"></a>
  <a href="https://github.com/talbaumel/mancia/actions/workflows/ci.yml"><img src="https://github.com/talbaumel/mancia/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="License: MIT"></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-black?logo=apple" alt="macOS 14+">
  <img src="https://img.shields.io/badge/Swift-6-orange?logo=swift" alt="Swift 6">
</p>

Select text anywhere on your Mac and Mancia opens a compact ribbon beside it.
Fix text typed with the wrong English or Hebrew keyboard layout locally with
**Oops**, open **Snippets** to paste a saved local value, or open **Smart Edit**
and say what you want changed. Smart Edit runs through GitHub Copilot CLI and
replaces the text in place — no chat window, no copy-paste round trip.

- Works in any app with standard **Copy**, **Select All** and **Paste**.
- Opens automatically when you finish selecting text, or on demand from the
  global shortcut or menu bar.
- Starts as a small **Oops · Snippets · Smart Edit** ribbon. Snippets replaces
  that row with one button per YAML key and resizes the ribbon to fit; Smart
  Edit replaces it with the AI controls.
- Opens just below the pointer that invoked it, or just above near the bottom
  of the screen, instead of opening in a distant corner.
- **Oops** switches text between English and Hebrew physical-key layouts
  without calling Copilot.
- Each snippet key is a direct button that pastes its private value from a
  local YAML file without calling Copilot.
- Smart Edit offers one-tap **Improve**, three coding-agent presets, or any
  free-form instruction.
- Step back and forth between versions until one is right.
- Your clipboard is snapshotted and restored after every edit.
- No telemetry, no Dock icon, no direct calls to any AI API.

## Install

Download the latest `.dmg` from
[Releases](https://github.com/talbaumel/mancia/releases/latest), open it, and drag
Mancia to **Applications**.

Or build it — Mancia is a Swift Package, with no Xcode project:

```sh
git clone https://github.com/talbaumel/mancia.git
cd mancia
make app && open build/Mancia.app
```

> [!NOTE]
> Release builds are not notarized yet. If macOS refuses to open the app,
> right-click it in Finder and choose **Open**, or run
> `xattr -dr com.apple.quarantine /Applications/Mancia.app`. Apps you compile
> yourself open normally.

## Set up

**1. GitHub Copilot CLI** does the actual editing, so install it and sign in.
It needs [Node.js 22+](https://nodejs.org) and a Copilot subscription.

```sh
npm install -g @github/copilot
copilot   # then follow the /login prompt
```

> [!TIP]
> If Mancia cannot find `copilot`, run `which copilot` and paste the absolute
> path into **Settings**.

**2. Accessibility permission** lets Mancia copy your selection and paste the
result back. Trigger the shortcut once and approve Mancia under **System
Settings → Privacy & Security → Accessibility**. Development builds are ad-hoc
signed, so macOS asks again after each rebuild.

## Use it

1. Select text in any app.
2. The compact ribbon opens automatically. You can also press
  <kbd>⌥</kbd><kbd>⌘</kbd><kbd>A</kbd> or choose **Edit
   Selection…** from the menu bar.
3. Choose what the text needs:
   - **Oops** immediately fixes text typed with the wrong English or Hebrew
     keyboard layout, replaces it in place, and closes the ribbon. This is a
     local conversion and does not use Copilot.
   - **Snippets** replaces the ribbon with the keys from
     `~/Documents/Mancia/snippets.yaml` and resizes it to fit. Pressing a key
     pastes its value over the selection (or at the caret), restores your
     clipboard, and closes the ribbon.
   - **Smart Edit** replaces the compact buttons with Target, Action,
     Direction, and Run; Oops and Snippets are no longer shown. Leave Direction
     empty for **Improve**, choose **Sharpen**, **Plan first**, or **Tighten**,
     or type your own instruction — *“make it decisive, one sentence”*,
     *“rewrite in a friendlier tone”*, *“turn these notes into bullets”*.
4. Press <kbd>Return</kbd> or **Run**. The ribbon stays visible with progress
   and Cancel controls while Copilot works, then shows the applied result and
   version navigation.

The result replaces the selection in place. With nothing selected, invoking
Mancia targets the whole document and, by default, asks before overwriting it.
Before each run, Mancia checks the live selection and frontmost app so a new
selection becomes the target instead of silently editing stale text. Click
outside the ribbon, resume typing in the app underneath it, or press
<kbd>Esc</kbd> to close it.

The Smart Edit actions are deliberately different:

- **Improve** fixes grammar, wording, and clarity while preserving meaning.
- **Sharpen** restructures text into a clear instruction for a coding agent.
- **Plan first** turns an implementation request into an
  investigate-then-plan request.
- **Tighten** removes filler while preserving every requirement and concrete
  detail.
- **Your instruction** runs exactly the direction you type. When a preset is
  selected, typed Direction text becomes additional guidance for that preset.

### Snippets file

Mancia creates `~/Documents/Mancia/snippets.yaml` with mock values the first
time the ribbon opens. Replace them with your own flat `name: value` entries:

```yaml
# Values are pasted exactly as strings. Quotes preserve leading zeroes.
My wife ID: "123456789"
My ID: "987654321"
Office code: "00246810"
```

The file is reloaded whenever a new ribbon session opens. Keep values quoted
when they are numeric identifiers rather than quantities. Snippets stay local
and are never included in a Copilot prompt.

| Key | Does |
| --- | --- |
| <kbd>Return</kbd> | Activate the focused control; initially opens Smart Edit, then runs from Direction or Run |
| <kbd>⌘</kbd><kbd>Return</kbd> | Run Smart Edit from anywhere in the expanded ribbon |
| <kbd>Tab</kbd> / <kbd>⇧</kbd><kbd>Tab</kbd> | Move forward or backward through the visible ribbon controls |
| <kbd>⌘1</kbd>…<kbd>⌘9</kbd> | Activate the matching visible button from left to right; in Smart Edit, ⌘1…⌘4 pick Improve, Sharpen, Plan first, or Tighten |
| <kbd>⌘0</kbd> | In Smart Edit, return to using your own instruction |
| <kbd>⌘T</kbd> | In Smart Edit, switch target: selection ↔ whole document |
| <kbd>⌘,</kbd> | Settings |
| <kbd>Esc</kbd> | Close the ribbon |

**Settings** (from the menu bar) shows shortcut, Accessibility, and Copilot
readiness. It also changes the global shortcut, whether selecting text opens
the ribbon automatically, launch at login, and — under Advanced — the Copilot
model, reasoning effort, and CLI path. Smart Edit closes immediately when a
response is ready and applies it without a review or completion animation.

## Privacy

Mancia has no analytics or telemetry and never calls an AI API directly.
**Oops and Snippets stay entirely local.** Smart Edit passes your selected text
and instruction to the local `copilot` process, which may send them on to
GitHub Copilot services. The pasteboard is used to read and replace text, then
restored to what it held before.

Report a vulnerability through our [security policy](SECURITY.md).

## Contributing

Contributions are welcome — read the [contributing guide](docs/CONTRIBUTING.md)
and the [Code of Conduct](CODE_OF_CONDUCT.md) first, then
[open an issue](https://github.com/talbaumel/mancia/issues/new/choose) or a pull
request.

```sh
make build   # debug build
make test    # unit tests
make run     # build the .app and launch it
make rerun   # quit, reset macOS permissions, rebuild, and launch
```

Copilot CLI is the only provider today; `Sources/Mancia/Providers` is the
extension point for others. See [Architecture](docs/ARCHITECTURE.md) for how
the pieces fit, and the [Changelog](CHANGELOG.md) for what has landed.

## License

[MIT](LICENSE)
