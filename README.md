# GridSnap

A menu bar window manager: define an X × Y grid, then bind hotkeys that move and
resize the focused window to an area of that grid.

## Features

- Global grid up to 16 × 16, with optional per-shortcut grid overrides
- Hotkeys that move and resize the focused window to a grid area, across multiple displays
- Drag-to-select grid editor, with a full-window view for dense grids
- Dim Background: dims everything behind the focused window (toggle with ⌃⌥⌘H, adjustable opacity), handling multiple displays and full-screen Spaces
- Launch at login

## Build

```bash
./build.sh
```

Produces `build/GridSnap.app`. Requires the Xcode Command Line Tools.

## One-time: signing certificate

macOS ties the Accessibility permission to the app's signing certificate. Without
a stable certificate, every rebuild looks like a new app and the permission prompt
comes back. Create a free self-signed one once:

1. Open **Keychain Access** → menu **Keychain Access → Certificate Assistant → Create a Certificate…**
2. Name: `GridSnap Developer`, Identity Type: **Self-Signed Root**, Certificate Type: **Code Signing**
3. Click **Create**, then run `./build.sh`

`build.sh` picks the certificate up automatically.

## App icon

The icon is drawn by `scripts/make-icon.swift`. After editing it, run
`scripts/make-icns.sh` to regenerate `Resources/AppIcon.icns`.
