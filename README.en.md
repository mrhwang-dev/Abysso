# Abysso

[한국어](README.md) | **English**

A personal cleaning utility for macOS. Safely find and clean caches, large files, and app leftovers. **Free beta** — no account or subscription required. All deletions go through the Trash (except Delete Completely), with a dark-only theme and a 7-language UI.

- **Version:** v0.0.1 (Free Beta)
- **Bundle ID:** `app.abysso.mac`
- **Platform:** macOS (Apple Silicon), SwiftUI + Swift Package Manager
- **Website:** [abysso-ten.vercel.app](https://abysso-ten.vercel.app) (7-language landing page, `web/`)

![System Status dashboard](docs/screenshots/dashboard.png)

## Features

A sidebar with 3 sections and 9 tabs.

| Section | Tab | Description |
|---------|-----|-------------|
| Monitoring | **System Status** | Live CPU · memory · disk dashboard (hero cards + live tiles) |
| Clean | **Smart Clean** | Clean caches, logs, broken downloads + Privacy (history · cookies) |
| Clean | **Large Files** | Size-ranked bar chart of big files, with file-meaning labels |
| Clean | **App Uninstaller** | Remove an app together with its leftover files |
| Clean | **Delete Completely** | Securely shred files beyond recovery |
| Manage | **Optimization** | Login items · resource-heavy apps · running apps |
| Manage | **Maintenance** | System tune-up tasks |
| Manage | **Extensions** | Manage browser & system extensions |
| Manage | **Update** | Check app · Homebrew · macOS updates |

Also: menu bar assistant (popover), launch at login, low-RAM alerts, Sparkle auto-updates.

## Screenshots

**Smart Clean** — category-based scans with safety badges

![Smart Clean](docs/screenshots/smart-clean.png)

**Large Files** — size-ranked bars that also tell you what cryptic files are (e.g. "Git repository data")

![Large Files](docs/screenshots/space-lens.png)

**App Uninstaller** — the app plus its leftover caches, settings, and support files

![App Uninstaller](docs/screenshots/uninstall.png)

**Optimization** — login items, resource-heavy apps, running apps

![Optimization](docs/screenshots/optimization.png)

## Languages

한국어 · English · 日本語 · 繁體中文 · Deutsch · Español · Français (7 languages)

`Resources/{ko,en,ja,zh-Hant,de,es,fr}.lproj/Localizable.strings`. The English (`en`) file is the superset template of all keys; translation consistency is checked with `python3 validate_strings.py`.

## Build

Builds with Command Line Tools + SPM — no Xcode required.

```bash
./build-app.sh          # produces build/Abysso.app (ad-hoc signed) + syncs /Applications
./create-dmg.sh         # creates a distributable DMG
swift Tools/make-icon.swift   # regenerate the app icon
```

## Project structure

```
Sources/Abysso/       # app source (SwiftUI views + models)
  AbyssoApp.swift     # entry point + AppDelegate (menu bar, template-menu pruning)
  ContentView.swift   # sidebar + tab routing, model ownership
  CacheView.swift     # Smart Clean
  LargeFilesView.swift# Large Files (parallel scan)
  Theme.swift         # dark theme + shared components
  ...
Resources/*.lproj/    # localized strings
web/                  # landing page (7 languages, deployed on Vercel — Root Directory: web)
Tools/                # icon & DMG background generators
Info.plist            # bundle config (Sparkle public key, etc.)
build-app.sh          # build script
validate_strings.py   # translation-key consistency checker
```

## Releasing (Sparkle auto-update)

1. Bump the version in `Info.plist`
2. Create a DMG with `./create-dmg.sh`
3. Sign it with `sign_update <dmg>`
4. Update `enclosure` (sparkle:edSignature, length) in `appcast.xml` → publish under `web/` (`https://abysso-ten.vercel.app/appcast.xml`)

> The EdDSA private key lives in the login keychain. **Never regenerate it** — existing installs would stop updating.

---

Personal project
