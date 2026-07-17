# Snaplet

A fast, native macOS menu-bar app for capturing screenshots and marking them up - full screen, a window, or a drag-selected area, then annotate with arrows, text, and speech bubbles.

Snaplet lives in the menu bar (no Dock icon) and is built entirely on Apple frameworks - ScreenCaptureKit for capture, AppKit + SwiftUI for the UI, and the Carbon Event Manager for global hotkeys. No third-party dependencies.

## Features

- **Three capture modes**
  - Full screen (the display holding the focused window)
  - Window - dims the screen and highlights the window under the cursor; click to capture
  - Area - drag out a rectangle with a live selection and a reticle cursor
- **Annotation editor** opens automatically after every capture
  - Tools: Select, Arrow, Text, and Speech Bubble
  - Select any annotation to move, resize, recolor, restyle, or delete it
  - Color palette plus a system color picker, and adjustable arrow thickness
  - Single-level undo
- **Export**
  - Save as PNG to a configurable folder, or Copy to the clipboard
  - A brief confirmation shows, then the editor closes
- **Global hotkeys** that fire from any app, and are re-registerable in Preferences
- **Launch at Login** via `SMAppService`
- Multi-display aware: per-screen selection overlays and correct scaling on Retina

## Requirements

- macOS 14 (Sonoma) or later - uses `SCScreenshotManager` from ScreenCaptureKit
- Xcode 15 or later to build

## Building

No package manager or dependencies are needed.

```sh
# Open in Xcode and press Run
open Snaplet.xcodeproj

# ...or build from the command line
xcodebuild -project Snaplet.xcodeproj -scheme Snaplet -configuration Release build
```

On first launch macOS will prompt for **Screen Recording** permission (required for any screen capture). Grant it in System Settings > Privacy & Security > Screen Recording, then relaunch.

> Tip: assign a signing Team in the target's Signing & Capabilities. A stable code signature keeps the Screen Recording grant from being dropped each time you rebuild.

## Usage

Click the reticle icon in the menu bar for the capture menu, or use the global hotkeys:

| Action           | Default shortcut |
| ---------------- | ---------------- |
| Capture Full Screen | `Option + Shift + S` |
| Capture Window      | `Option + Shift + W` |
| Capture Area        | `Option + Shift + A` |

After a capture, the annotation editor opens:

1. Pick a tool (Select / Arrow / Text / Bubble) from the toolbar.
2. Draw on the image. With **Select**, click an annotation to move it, drag its handles to resize, or press Delete to remove it.
3. Choose a color and arrow thickness; changing them restyles the selected annotation.
4. Click **Save** (writes a PNG) or **Copy** (to the clipboard). The editor confirms and closes.

Saved files default to `~/Pictures/Screenshots`, named like `Snaplet 2026-07-17 at 14.30.00.png`.

## Preferences

Open **Preferences…** from the menu bar:

- **Hotkeys** - rebind each capture shortcut (each needs at least one modifier, or a function key)
- **Save Location** - choose the save folder, reveal it in Finder, or reset to default
- **General** - toggle Launch at Login

## Tests

```sh
xcodebuild -project Snaplet.xcodeproj -scheme Snaplet -configuration Debug test
```

## License

[MIT](LICENSE) (c) 2026 Mike Ison
