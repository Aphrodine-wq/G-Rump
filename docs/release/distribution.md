# G-Rump 2.0 Distribution Guide

Distributing G-Rump outside the Mac App Store (direct download, website, Homebrew).

## Quick Start

```bash
# Just build the .app (no signing)
make app

# Build + create .dmg (requires create-dmg)
make dmg

# Build + sign + .dmg (requires Apple Developer account)
make package

# Build + sign + .dmg + notarize (full distribution-ready)
make notarize

# Reset app state for fresh-boot testing
make reset
```

Output goes to `dist/G-Rump.app` and `dist/G-Rump.dmg`.

## Prerequisites

### For unsigned builds (testing)
No special setup needed. Just `make app`.

### For DMG builds
```bash
brew install create-dmg
```

### For signed + notarized builds (distribution)

1. **Apple Developer Program** membership ($99/year)
2. **Developer ID Application** certificate — create in [Apple Developer portal](https://developer.apple.com/account/resources/certificates/list)
3. **App-specific password** — create at [appleid.apple.com](https://appleid.apple.com/account/manage) → Sign-In and Security → App-Specific Passwords

### Environment variables for signing/notarization

```bash
export DEVELOPER_ID="Developer ID Application: Your Name (TEAMID)"
export APPLE_ID="your@email.com"
export TEAM_ID="YOUR_TEAM_ID"
export APP_PASSWORD="xxxx-xxxx-xxxx-xxxx"
```

Tip: add these to a `.env.local` file (gitignored) and `source .env.local` before packaging.

## Makefile Targets

| Target | What it does |
|---|---|
| `make app` | Release build → `.app` bundle in `dist/` |
| `make dmg` | Release build → `.app` → `.dmg` (requires `create-dmg`) |
| `make sign` | Release build → signed `.app` |
| `make package` | Release build → signed `.app` → signed `.dmg` |
| `make notarize` | Release build → signed `.app` → signed `.dmg` → notarized + stapled |
| `make reset` | Wipe UserDefaults + app data for fresh-boot testing |

## App Icon

The app icon is auto-generated from SwiftUI's `FrownyFaceLogo` via:
```bash
swift scripts/generate-app-icon.swift
```

This creates PNGs in `Sources/GRump/Resources/Assets.xcassets/AppIcon.appiconset/`. The packaging script auto-generates `AppIcon.icns` from these PNGs if it doesn't already exist.

To manually regenerate the `.icns`:
```bash
swift scripts/generate-app-icon.swift   # regenerate PNGs
make app                                # .icns is auto-generated during packaging
```

## Entitlements

The app uses `GRump.entitlements` at the project root. Key entitlements:
- **Network client/server** — for AI provider API calls
- **File access** — for reading/writing project files
- **JIT / unsigned memory** — for terminal emulation and LSP

Sandbox is **disabled** (`com.apple.security.app-sandbox = false`) because G-Rump needs to run shell commands, access arbitrary project directories, and spawn child processes (LSP, language servers, etc.).

## Update Mechanism

Settings → Updates → "Check for updates" opens the releases page. Users download new versions manually. Future: Sparkle framework for auto-updates.
