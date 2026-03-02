<h1 align="center">🐦‍⬛ Magpie</h1>

<p align="center">
  <strong>Copy freely. Everything is saved.</strong>
</p>

<p align="center">
  A fast, searchable clipboard manager for macOS.<br>
  Never lose a copy again.
</p>

<p align="center">
  <a href="https://github.com/Good-Feels/magpie/releases/latest">
    <img src="https://img.shields.io/github/v/release/Good-Feels/magpie?style=flat-square" alt="Latest Release">
  </a>
  <img src="https://img.shields.io/badge/macOS-13%2B-blue?style=flat-square" alt="macOS 13+">
  <img src="https://img.shields.io/badge/Swift-5.9-orange?style=flat-square" alt="Swift 5.9">
  <a href="LICENSE">
    <img src="https://img.shields.io/github/license/Good-Feels/magpie?style=flat-square" alt="License">
  </a>
</p>

---

## The Problem

You have something important on your clipboard. Now you need to copy something else. Do you paste first? Open a scratch file? Panic?

**Magpie fixes this.** It silently saves everything you copy, so you can always go back and find it. Like a magpie collecting shiny things — nothing is ever lost.

## Screenshots

*Coming soon — screenshots of the popover, search, and settings.*

<!-- Uncomment when screenshots are added:
<p align="center">
  <img src="assets/screenshots/clipboard-history.png" alt="Clipboard History" width="360">
  &nbsp;&nbsp;
  <img src="assets/screenshots/search.png" alt="Search" width="360">
</p>

<p align="center">
  <img src="assets/screenshots/settings.png" alt="Settings" width="420">
</p>
-->

## Features

- **Instant search** — Find any clip you've ever copied. No more "I know I copied that..."
- **Rich content** — Text, images, rich text, and file paths are all captured
- **Source app tracking** — See which app each clip came from, with its icon
- **Pin favorites** — Keep your most-used clips at the top
- **App exclusions** — Exclude password managers and other sensitive apps
- **Lightweight** — Lives in your menu bar, uses SQLite, under 2MB
- **Auto-updates** — Direct downloads update automatically via Sparkle
- **Private** — Everything stays on your Mac. No cloud, no telemetry, no accounts

## Install

### Mac App Store

*Coming soon*

### Download (Direct)

1. Download `Magpie.dmg` from the [latest release](https://github.com/Good-Feels/magpie/releases/latest)
2. Open the DMG and drag **Magpie** to your Applications folder
3. Launch Magpie — it appears in your menu bar (no Dock icon)
4. The direct download version includes automatic updates via Sparkle

### Build from Source

```bash
git clone https://github.com/Good-Feels/magpie.git
cd magpie
./run.sh
```

Requires Xcode 15+ and macOS 13+.

## Usage

| Action | How |
|--------|-----|
| Open history | Click the 📋 icon in your menu bar |
| Search | Just start typing — the search bar auto-focuses |
| Copy a clip | Click any item (shows "Copied!" then auto-dismisses) |
| Pin a clip | Right-click → Pin |
| Delete a clip | Right-click → Delete |
| Settings | Click the ⚙ gear icon in the popover footer |
| Quit | Click "Quit" in the popover footer |

## Tech Stack

- **Swift + SwiftUI** — Native macOS, no Electron
- **SQLite via [GRDB](https://github.com/groue/GRDB.swift)** — Fast, reliable local storage
- **NSStatusItem + NSPopover** — Proper menu bar integration
- **[Sparkle](https://sparkle-project.org)** — Auto-updates for direct distribution
- **SMAppService** — Launch at login (macOS 13+)
- **App Sandbox** — Mac App Store compatible

## Project Structure

```
├── Package.swift                    # Root package (app executable)
├── ClipboardEngine/                 # Core logic (local Swift package)
│   └── Sources/ClipboardEngine/
│       ├── Models/ClipItem.swift    # Data model
│       ├── Monitoring/              # Clipboard polling + app resolver
│       └── Storage/                 # SQLite via GRDB
├── Magpie/                          # App target
│   ├── App/                         # AppDelegate, AppState, entry point
│   ├── Views/                       # SwiftUI views
│   ├── Services/                    # Launch at login, exclusions, updater
│   └── Magpie.entitlements          # App Sandbox for MAS compatibility
├── run.sh                           # Build & run for development
└── scripts/build-release.sh         # Build signed DMG for distribution
```

## Roadmap

- [x] Global keyboard shortcut to toggle history
- [x] First-launch onboarding and clipboard permission guidance
- [x] Signed/notarized direct release pipeline (DMG + appcast)
- [ ] Keyboard navigation (arrow keys + Enter)
- [ ] Paste directly into frontmost app
- [x] Sparkle auto-updates (direct download)
- [ ] Mac App Store submission
- [ ] CLI (`magpie list`, `magpie search`, `magpie copy`)
- [ ] Snippets / templates

## License

MIT License. See [LICENSE](LICENSE) for details.

---

<p align="center">
  Made with ❤️ by <a href="https://github.com/Good-Feels">Good Feels</a>
  <br>
  Built with OpenAI Codex
</p>
