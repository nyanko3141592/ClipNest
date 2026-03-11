# ClipNest

A lightweight macOS menu bar clipboard manager with snippet support.

## Features

- **Clipboard History** — Automatically tracks your clipboard with configurable history size (10–100 items)
- **Snippets** — Organize frequently used text in nested folders for quick access
- **Global Hotkey** — Trigger ClipNest from anywhere (default: `Cmd+Shift+V`)
- **Auto-Paste** — Selecting an item copies it and pastes into the active app
- **Launch at Login** — Optional auto-start on login
- **Privacy-First** — All data stored locally in `~/Library/Application Support/ClipNest/`

## Requirements

- macOS 13.0 (Ventura) or later
- Swift 5.9+
- Accessibility permission (prompted on first launch)

## Build

```bash
swift build -c release
bash scripts/build-app.sh
```

This creates `ClipNest.app` in the project root.

## Install

```bash
cp -r ClipNest.app /Applications/
open /Applications/ClipNest.app
```

## Usage

1. ClipNest appears as a paperclip icon in the menu bar
2. Click the icon or press the global hotkey to open the menu
3. **History** submenu shows recent clipboard entries
4. Top-level items are your snippets — click to paste
5. Use **Edit Snippets...** to organize snippets into folders
6. Use **Settings...** to configure hotkey, history size, and launch at login

## License

[MIT](LICENSE)
