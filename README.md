# GridSnap

**Your screen, on a grid. Your windows, exactly where you want them, one keystroke away.**

GridSnap is a tiny, native macOS menu bar app that turns window management into muscle
memory. Split your screen into a grid of any size, from a simple 2 × 2 up to a precise
16 × 16, then bind hotkeys that throw the focused window into any rectangle of that grid.
Left two-thirds for your editor, the top-right corner for Slack, a centred column for
reading — press the keys and it's there, pixel-perfect, on whichever display it's on.

There are no fixed presets to work around: every layout is one you draw yourself. Drag
across a grid in Settings, press the shortcut you want, and you're done.

And when it's time to concentrate, **Dim Background** fades everything except the window
you're working in, so the rest of your screen stops competing for your attention.

It's written in Swift and SwiftUI, with no third-party dependencies, no account and nothing
running in the background beyond a menu bar icon.

## Download

**[Download the latest GridSnap (DMG)](https://github.com/benwellby/gridsnap/releases/latest/download/GridSnap.dmg)**
for macOS 15 or later, on Apple silicon or Intel.

GridSnap isn't notarised by Apple, so the first time you open it, macOS will block it. Go
to **System Settings → Privacy & Security** and click **Open Anyway**. The DMG includes a
step-by-step install guide.

---

## Features

### Grid-based window snapping
- **A grid you define:** set any number of columns and rows from 1 to 16.
- **Unlimited shortcuts:** each one moves and resizes the focused window to a rectangle of
  grid cells you choose.
- **Per-shortcut grids:** give an individual shortcut its own grid (e.g. thirds for one,
  quarters for another) without changing the global grid.
- **Multi-display aware:** windows snap within the screen they're on, avoiding the menu bar
  and Dock.
- **Gap-free tiling:** adjacent snapped windows meet edge to edge with no stray pixels.
- **Plays nicely with Chrome and Electron apps:** works around their resize quirks.

### Easy to set up
- **Drag-to-select grid editor:** drag across a mini grid to pick an area.
- **Full-window editor:** click a mini grid to open a large editor that matches your screen's
  shape, for precise selections on dense grids. Set the shortcut's hotkey and custom grid
  there too.
- **Hotkey recorder:** click, press your combination, done. Esc cancels.
- **Conflict warnings:** see at a glance when a hotkey is used twice or already taken by
  macOS or another app.
- **Type or step:** enter grid sizes directly or use the arrows.
- **Sensible defaults:** halves, quarters, centre and maximise are ready to go on first launch.

### Dim Background
- **Focus mode:** dims every window except the one you're working in.
- **Adjustable:** opacity from 10% to 90%.
- **Toggle anywhere:** ⌃⌥⌘H by default (rebindable), or from the menu bar.
- **Follows your focus:** updates instantly when you switch apps, windows or Spaces.
- **Handles complex setups:** multiple displays with separate Spaces and full-screen apps
  are supported, with no flicker on the displays that didn't change.
- **Click-through:** the dimming never gets in the way of clicking on other windows.

### Menu bar app
- **Lives in the menu bar:** no Dock icon.
- **Quick access menu:** every shortcut is listed with a mini icon of its layout and its hotkey.
- **Status at a glance:** the menu bar icon shows when Dim Background is on.
- **Launch at login:** a single toggle.

---

## Technical specification

### At a glance

| | |
|---|---|
| Platform | macOS 15 or later (developed on macOS 27) |
| Architecture | Universal: Apple silicon (arm64) and Intel (x86_64) |
| Language / UI | Swift 6 toolchain (Swift 5 language mode), SwiftUI with AppKit where needed |
| Build system | Swift Package Manager, plus `build.sh` (universal `.app`) and `package.sh` (DMG); no Xcode project needed |
| Dependencies | None (system frameworks only) |
| App size | ~2.3 MB bundle and DMG (universal binary ~1.5 MB) |
| Codebase | ~1,300 lines of Swift across 7 files |
| Bundle ID | `com.benwellby.gridsnap` |
| App type | Menu bar agent (`LSUIElement`), no Dock icon |
| Permissions | Accessibility only; no Screen Recording or Input Monitoring needed |

### Architecture

| File | Responsibility |
|---|---|
| `GridSnapApp.swift` | App entry point, menu bar menu, Settings window scene, menu bar and menu icons |
| `Store.swift` | App state (grid, shortcuts, dim settings), persistence, hotkey routing |
| `Models.swift` | `GridArea`, `GridSize`, `HotKey` and `Shortcut` types |
| `WindowMover.swift` | Moves and resizes the focused window via the Accessibility API |
| `HotKeyManager.swift` | Registers system-wide hotkeys |
| `Dimmer.swift` | Dim Background overlays and focus tracking |
| `SettingsView.swift` | Settings UI: grid picker, full-window editor, hotkey recorder, number fields |

### How it works

**Window snapping**
- The focused window is found through the Accessibility API (`AXUIElement`, `kAXFocusedWindowAttribute`).
- The target frame is calculated from the display's `visibleFrame`, which excludes the menu bar and Dock.
- Cell edges are rounded, rather than cell sizes, so adjacent windows tile without gaps.
- Frames are converted between AppKit's bottom-left origin and Accessibility's top-left
  origin, which is anchored to the primary display.
- Windows are resized, moved, then resized again, so they fit correctly when crossing displays.
- `AXEnhancedUserInterface` is switched off during the move, which stops Chromium and Electron
  apps from animating or resisting the resize.

**Global hotkeys**
- Hotkeys use Carbon's `RegisterEventHotKey`, which needs no Input Monitoring permission.
- All hotkeys are paused while a new combination is being recorded.
- A failed registration is reported in Settings as a conflict.

**Dim Background**
- Each display gets a borderless, click-through black `NSWindow` at the normal window level.
  It's ordered directly below the focused window with `order(.below, relativeTo:)`.
- The focused window is identified with Accessibility plus `_AXUIElementGetWindow`, a private
  API that most window managers rely on. Stacking order from `CGWindowListCopyWindowInfo` is
  the fallback.
- Updates are triggered by:
  - app activation and Space-change notifications from `NSWorkspace`
  - an `AXObserver` watching focus and window changes within the active app
  - display configuration changes
  - a once-a-second safety check
- Overlays belong to a single Space, so they slide away with it. After a switch, only the
  overlays on displays whose Space changed are moved.
- When the focused window is full screen (`AXFullScreen`), the overlay on that display is
  removed.

**Persistence and system integration**
- All settings are stored as a single JSON blob in `UserDefaults` under the key `config`.
  New fields are optional, so older configs keep loading.
- Launch at login uses `SMAppService.mainApp`.
- Diagnostics go to the unified log via `os.Logger`, under the subsystem
  `com.benwellby.gridsnap` with categories `move` and `dim`.

### Limits and defaults

| Setting | Range | Default |
|---|---|---|
| Grid columns / rows | 1–16 | 4 × 2 |
| Dim opacity | 10–90% | 50% |
| Dim toggle hotkey | Any combination with ⌘, ⌥ or ⌃ | ⌃⌥⌘H |
| Shortcut hotkeys | Any combination with ⌘, ⌥ or ⌃ | ⌃⌥ + ← → U I J K C ↩ |

---

## Requirements

- macOS 15 or later
- Xcode Command Line Tools (to build)
- Accessibility permission (macOS will ask on first launch)

## Build

```bash
./build.sh
```

This produces `build/GridSnap.app`. Move it to `/Applications` if you plan to use
**Launch at login**.

## Sharing

```bash
./package.sh
```

This builds the app and produces `dist/GridSnap-<version>.dmg`. The DMG contains the app,
an Applications shortcut to drag it into, and a `How to install.txt` guide. The version
comes from `CFBundleShortVersionString` in `Resources/Info.plist`; bump it before each
release.

GridSnap is self-signed rather than notarised by Apple, so the first time someone opens
it, macOS blocks it. They then need to click **Open Anyway** in **System Settings →
Privacy & Security**. The install guide walks them through this.

Always sign releases with the same **GridSnap Developer** certificate. That way, people
who update keep their Accessibility permission. Back the certificate up by exporting it
from Keychain Access as a `.p12` file. If it's lost, everyone will have to grant access
again.

## One-time: signing certificate

macOS ties the Accessibility permission to the app's signing certificate. Without a stable
certificate, every rebuild looks like a new app and the permission prompt comes back.
Create a free self-signed one once:

1. Open **Keychain Access** → menu **Keychain Access → Certificate Assistant → Create a Certificate…**
2. Name: `GridSnap Developer`, Identity Type: **Self-Signed Root**, Certificate Type: **Code Signing**
3. Click **Create**, then run `./build.sh`

`build.sh` uses the certificate automatically.

If macOS still won't grant access after switching certificates, clear the old entry and
grant it again:

```bash
tccutil reset Accessibility com.benwellby.gridsnap
```

## Troubleshooting

GridSnap logs what it's doing under the subsystem `com.benwellby.gridsnap`:

```bash
/usr/bin/log show --last 10m --predicate 'subsystem == "com.benwellby.gridsnap"' --info
```

## App icon

The icon is drawn by `scripts/make-icon.swift`. After editing it, run
`scripts/make-icns.sh` to regenerate `Resources/AppIcon.icns`.
