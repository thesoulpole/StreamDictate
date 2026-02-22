# StreamDictate

A macOS menu bar app that opens a floating text editor on a hotkey, auto-starts system dictation, and injects the result at your cursor via CGEvent.

Solves two problems with native macOS dictation:

1. **Unreliable activation** — the dictation hotkey often requires multiple presses to activate. StreamDictate uses a CGEventTap that fires on the first press, every time.
2. **Misplaced overlay** — the dictation popup appears in the wrong position in terminals. StreamDictate uses its own text editor, so dictation always works correctly.

## How it works

Press **Right Command** → a floating panel appears with macOS dictation already active. Speak, edit, then submit. The text is injected at the cursor position in whatever app you were using.

## Keyboard shortcuts

| Shortcut | Action |
|---|---|
| Right Command | Open panel (+ start dictation) / Submit if already open |
| Right Shift + Enter | Submit text and close |
| Right Shift + ] | Toggle dictation on/off |
| Enter | Newline |
| Escape | Cancel (close without injecting) |

## Requirements

- macOS 14.0+
- **Accessibility permission** — needed for the hotkey (CGEventTap) and text injection (CGEvent). Grant in System Settings > Privacy & Security > Accessibility.
- **Dictation enabled** — System Settings > Keyboard > Dictation must be turned on.
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) — to generate the Xcode project from `project.yml`.

## Build

```bash
brew install xcodegen
xcodegen generate
open StreamDictate.xcodeproj
```

Build and run from Xcode (Cmd+R). The app appears as a microphone icon in the menu bar with no Dock icon.

To run standalone, copy the built app to `~/Applications` and enable **Launch at Login** from the menu bar icon's menu.

## Architecture

The codebase is intentionally small (6 Swift files):

| File | Purpose |
|---|---|
| `main.swift` | NSApplication entry point |
| `AppDelegate.swift` | Coordinates hotkey, panel, and text injection |
| `DictationPanel.swift` | Floating NSPanel with NSTextView + key handling |
| `HotkeyMonitor.swift` | CGEventTap for Right Command key |
| `Config.swift` | UserDefaults for hotkey and activation mode |
| `PermissionChecker.swift` | Mic + accessibility permission checks |

Text injection uses `CGEvent.keyboardSetUnicodeString` to type at the cursor position in any app. The panel uses `NSApp.sendAction("startDictation:")` to programmatically activate macOS system dictation.

## Configuration

The hotkey and activation mode can be changed in `Config.swift`:

- **Hotkey**: Default is Right Command (`0x36`). Change to Right Option (`0x3D`) or any other modifier key.
- **Activation mode**: `pushToTalk` (hold to dictate) or `toggle` (press on/off).
