# Pismo

A macOS menu bar app that switches the keyboard layout based on the focused app, and on the focused
field inside an app. For example: Cyrillic while writing a Slack message, Latin everywhere else.

## Install

Requires macOS 14+ on Apple silicon.

```sh
brew tap aleksandargosevski/tap
brew trust aleksandargosevski/tap
brew install pismo
brew services start pismo   # start now and at every login
```

Then allow Pismo in **System Settings → Privacy & Security → Accessibility**. Every release is
signed with the same certificate, so the permission survives `brew upgrade`.

The app can also be downloaded from [Releases](https://github.com/aleksandargosevski/pismo/releases).
Browsers mark downloads as quarantined and the app is not notarized, so macOS blocks the first
launch of each version: allow it under **System Settings → Privacy & Security → Open Anyway**, or run
`xattr -d com.apple.quarantine Pismo.app`.

## Install from source

Requires the Xcode Command Line Tools.

```sh
./scripts/create-cert.sh   # once: self-signed "Pismo Dev" signing certificate
./scripts/install.sh       # builds and installs into ~/Applications, then starts the app
```

On first launch, grant **Accessibility** access to Pismo in System Settings. Because every build is
signed with the same certificate, the permission survives rebuilds and upgrades.

Enable **Launch at Login** from the menu bar icon.

## Configuration

Rules live in `~/.config/pismo/rules.json` and are reloaded automatically when the file is saved.

```json
{
  "default": "ABC",
  "apps": {
    "com.tinyspeck.slackmacgap": {
      "fields": [
        {
          "name": "message composer",
          "match": { "role": "^AXTextArea$", "domClass": "^ql-editor$" },
          "layout": "Serbian"
        }
      ]
    },
    "com.apple.Notes": { "layout": "Serbian (Latin)" }
  }
}
```

For each focus change, Pismo uses the first matching field rule of the app, then the app's `layout`,
then the global `default`.

- **Layouts** are referenced by their name as shown in the input menu (`Serbian (Latin)`) or by input
  source id (`com.apple.keylayout.Serbian-Latin`). The available layouts are listed at the top of the
  inspector log.
- **Apps** are keyed by bundle id (`osascript -e 'id of app "Slack"'`).
- **Match** values are regular expressions; every listed attribute must match. Available attributes:
  `role`, `subrole`, `roleDescription`, `title`, `description`, `placeholder`, `help`, `identifier`,
  `domId`, `domClass` (matches any of the element's DOM classes in Electron/Chromium apps).
- `"ancestor": { ... }` matches when any parent element matches the nested rule.

The layout is applied only when the app or focused field changes, so switching layouts by hand
lasts until focus moves.

### Creating rules from the menu

1. Focus the field (or app) and switch to the layout you want.
2. Open the Pismo menu and pick **Use "…" for This Field in …** or **Use "…" for …**.

The generated rule is added to `rules.json`, where it can be refined.

### Finding field attributes

Every focus change is written to `~/Library/Logs/Pismo/inspector.log` with the field's attributes and
its parent elements (typed text is never read):

```sh
tail -f ~/Library/Logs/Pismo/inspector.log
```

**Copy Last Field Info** in the menu copies the same report for the last focused field.

## Hiding the input source popup

macOS shows a small layout indicator next to the cursor on every switch. It can only be disabled
system-wide (log out and back in to apply):

```sh
defaults write kCFPreferencesAnyApplication TSMLanguageIndicatorEnabled 0       # hide
defaults delete kCFPreferencesAnyApplication TSMLanguageIndicatorEnabled        # restore
```

## Development

```sh
./scripts/build.sh --run   # build into ./build and restart
./scripts/test.sh          # run tests
swift scripts/make-icon.swift Resources/AppIcon.icns   # regenerate the app icon
```

`Sources/PismoCore` contains the config format and rule matching (fully unit tested);
`Sources/Pismo` contains the AppKit, Accessibility and input source integration.

## Releasing

Pushing a tag like `v1.2.3` runs `.github/workflows/release.yml`, which tests, builds and signs the
app, publishes `Pismo-1.2.3.zip` as a GitHub release and updates `Formula/pismo.rb` in
[aleksandargosevski/homebrew-tap](https://github.com/aleksandargosevski/homebrew-tap).

Required repository secrets:

| Secret | Value |
|---|---|
| `PISMO_CERT_P12_BASE64` | `base64 -i pismo-dev.p12` of the "Pismo Dev" certificate exported from Keychain Access |
| `PISMO_CERT_PASSWORD` | password chosen when exporting the `.p12` |
| `HOMEBREW_TAP_TOKEN` | fine-grained token with Contents: read and write on the tap repository |

Releases must always be signed with the same certificate; a new certificate makes every user grant
the Accessibility permission again.
