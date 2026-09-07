# Clipboard History 1.0.0

A private, local macOS menu-bar utility for keeping a history of copied text and images.

## Requirements

- macOS 14 (Sonoma) or later
- Xcode 15 or later

## Run from Xcode

1. Open `ClipboardHistory.xcodeproj` in Xcode.
2. Select the `ClipboardHistory` scheme and a local Mac destination.
3. Press **Run** (`Cmd + R`).
4. Click the clipboard icon in the menu bar, then choose **Quit Clipboard History** to exit.

The app is configured as a menu-bar-only agent application, so it will not appear in the Dock.

## Privacy

Clipboard history, images, settings, and exclusions stay on this Mac. There is no account, cloud sync, or network access. You can exclude applications by bundle identifier in **Clipboard History → Settings**; exclusion is best-effort because macOS cannot always identify which app created clipboard content.

## Tests

Run the core test suite from Xcode with `Cmd + U`, or from Terminal:

```sh
xcodebuild -project ClipboardHistory.xcodeproj -scheme ClipboardHistory -sdk macosx test
```
