# Panels

G-Rump has 18 built-in IDE panels accessible from the right sidebar icon bar.

## Panel List

| Panel | Icon | Description |
|---|---|---|
| **Chat** | `bubble.left.and.bubble.right.fill` | AI conversation (primary view) |
| **Files** | `folder.fill` | Project file navigator with search |
| **Preview** | `eye.fill` | Live preview of selected file |
| **Simulator** | `iphone` | iOS simulator controls |
| **Git** | `arrow.triangle.branch` | Git status, diff, commit, branch management |
| **Tests** | `checkmark.circle.fill` | Test explorer with run/debug |
| **Assets** | `photo.on.rectangle` | Asset catalog browser |
| **Localization** | `globe` | String catalog and localization management |
| **Schema** | `cylinder.split.1x2` | Data model schema viewer |
| **Profiling** | `gauge.with.dots.needle.bottom.50percent` | Performance profiling tools |
| **Logs** | `list.bullet.rectangle` | Unified log viewer |
| **SPM** | `shippingbox.fill` | Swift Package Manager dependencies |
| **Xcode** | `hammer.fill` | Xcode project tools |
| **Docs** | `book.fill` | Apple documentation browser |
| **Terminal** | `terminal.fill` | Inline terminal |
| **App Store** | `bag.fill` | App Store submission tools |
| **Accessibility** | `figure.stand` | Accessibility audit panel |
| **Memory** | `brain.head.profile` | Cognitive memory browser — stored memories, recall, consolidation |

## Panel Groups

Panels are organized into three groups in the sidebar:

- **Primary** — Chat, Files, Preview, Simulator
- **Apple Dev** — Git, Tests, Assets, Localization, Schema, Profiling, Logs, SPM, Xcode, Docs
- **Content** — Terminal, App Store, Accessibility, Memory

## Key Files

- `PanelTab.swift` — Enum defining all panels, icons, labels
- `RightPanelSidebar.swift` — Vertical icon sidebar
- `RightPanelManager.swift` — Panel state and content switching
- `Views/Layout/PanelLayoutView.swift` — Panel content view routing

## Panel Visibility

All panels are always available. The right panel can be collapsed/expanded. Panel selection is persisted across sessions.
