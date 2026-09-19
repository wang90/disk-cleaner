# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0-beta.2] — 2026-09-19

Bug-fix release. **If you downloaded `v1.0.0-beta`, please replace it with this build** —
the first beta crashed on launch roughly one time in three.

### Fixed

- **Random crash on launch.** `EXC_BAD_ACCESS` (SIGSEGV) with
  *"Could not determine thread index for stack guard region"* — the main thread ran out of
  stack. The crash report showed **1715 levels of recursion** alternating between
  `AppKitWindowController.updateRootHost` → `AppGraph.graphDidChange` →
  `GraphHost.flushTransactions` → `AppGraph.sceneList`, i.e. the SwiftUI scene list kept
  rebuilding itself until the stack was exhausted (the fatal frame merely happened to be
  inside opaque-type metadata resolution for `View.keyboardShortcut(_:)`).

  Root cause: SwiftUI's `MenuBarExtra` scene. Measured over 8 fresh launches per variant:

  | Menu bar implementation | Crashes |
  |---|---|
  | `MenuBarExtra` + custom `label:` closure | 3 / 8 |
  | `MenuBarExtra` + single `Label` | 2 / 8 |
  | `MenuBarExtra`, title passed as a parameter | 2 / 8 |
  | `MenuBarExtra`, fully static title | 1 / 8 |
  | no menu bar item | 0 / 8 |
  | **AppKit `NSStatusItem` + `NSPopover`** | **0 / 8** |

  The menu bar extra is now implemented in AppKit (`Sources/MenuBarController.swift`),
  wired up through an `NSApplicationDelegateAdaptor` and a shared `CleanerModel` instance.
  As a bonus this also makes the free-space number next to the icon, the warning icon when
  below target, and a tooltip with the configured target possible.

- Command menus moved into a dedicated `AppCommands: Commands` type.
- Restored the system **New Window** item, so ⌘N reopens the main window after closing it.

### Verified

- 8/8 clean launches locally, 10/10 with the packaged universal build.
- Menu bar icon with free-space text confirmed present via a menu-bar screenshot diff.

## [1.0.0-beta] — 2026-09-17

First public release — **beta**. 🎉

Everything described below works and has been tested on macOS 14+; it is labelled beta
because the UI is Simplified-Chinese-only and the build is not yet notarized.

### Added

**App (SwiftUI)**

- Native macOS dashboard: free space vs. target, whole-disk usage and memory at a glance.
- macOS *Storage*-style category breakdown (Applications, Documents & Desktop, Downloads,
  Photos, Music, Movies, Mail & Messages, Developer caches, App data, System & app caches,
  System data & other, Free) rendered as a colour stacked bar.
  - Hover any segment to see its exact size and share.
  - `123` button toggles printing the sizes directly on the bar (hover keeps working).
- Per-app usage: bundle size **plus** its user data under `~/Library/Containers`,
  `~/Library/Caches` and `~/Library/Application Support`, sorted by size.
- Per-volume list (boot container + any external disks / DMGs).
- Three-tier cleaning with safety status per item (`ok` / `timeout` / `fail`).
- Live log panel, dry-run mode, deep clean, optional `purge` for memory.
- Background auto-clean toggle that installs/removes a `LaunchAgent`.
- One-click permission request for macOS protected folders (triggers the system prompt and
  opens *Full Disk Access* settings).
- Settings window with theme selection: **Follow system / Light / Dark**, auto-clean and
  file locations.
- **Dedicated About window** (`DiskCleaner → About DiskCleaner`, or the button at the
  bottom of Settings): feature rundown, safety design, links to the repo and releases.
- **Menu bar extra**: small icon in the menu bar with the free space next to it
  (`21.8G`), turning into a warning triangle when below target. Clicking it opens a popover
  with free space vs. target, whole-disk and memory usage, and quick actions
  (open main window / clean / quit). Toggle it in Settings → 菜单栏.
  Implemented with AppKit `NSStatusItem` + `NSPopover` — see the Fixed note below for why
  SwiftUI's `MenuBarExtra` could not be used.
- Version has a single source of truth (`Resources/Info.plist`) and is displayed as
  `1.0.0 (beta)`; a `BETA` badge is shown in the header.
- Decimal units for storage (matching macOS) and binary units for memory (matching
  About This Mac).

### Fixed

- **Random crash on launch** (`EXC_BAD_ACCESS` / SIGSEGV with
  "Could not determine thread index for stack guard region", i.e. a main-thread stack
  overflow). Root cause: SwiftUI's `MenuBarExtra` scene. With this toolchain the compiler
  emits a *recursive* opaque type descriptor for the scene, and resolving that type metadata
  at startup recurses until the stack is exhausted.
  Measured with 8 fresh launches each:

  | Menu bar implementation | Crashes |
  |---|---|
  | `MenuBarExtra` + custom `label:` closure | 3 / 8 |
  | `MenuBarExtra` with a single `Label` | 2 / 8 |
  | `MenuBarExtra` title passed as a parameter | 2 / 8 |
  | `MenuBarExtra`, fully static title | 1 / 8 |
  | **no menu bar item** | **0 / 8** |
  | **AppKit `NSStatusItem` + `NSPopover`** | **0 / 8** |

  The menu bar extra is now an AppKit `NSStatusItem` (`Sources/MenuBarController.swift`),
  which also makes the free-space number and the warning icon possible.
  The command menus were additionally moved into a dedicated `AppCommands: Commands` type.

**Engine (`scripts/diskautoclean.sh`)**

- Auto-cleaning that stops as soon as the free-space target is met.
- Tier 1: `~/Library/Caches` (>14d), `~/.cache` (>14d), Xcode DerivedData, simulator caches,
  crash reports (>7d), truncation of logs larger than 200 MB.
- Tier 2: npm / npx / pnpm / pip / Homebrew / Go / TypeScript / Yarn / uv / Electron /
  Playwright / Cargo / Gradle caches, old iOS device support files.
- Tier 3 (opt-in only): Xcode Archives, iOS backups, Trash, old downloads.
- Protected-path guard, home-directory whitelist, age-based deletion.
- Hard per-path timeout so a hung `du` (stale mount, permission prompt) can never freeze a run.
- Machine-readable output for the GUI: `--status`, `--scan`, `--apps`, `--storage`,
  `--volumes` all support `--json`, plus `@@`-prefixed progress events while cleaning.
- Concurrency lock, refuses to run as root, full audit log.

**Project**

- `build.command` — builds a universal (arm64 + x86_64) `DiskCleaner.app` using only the
  macOS Command Line Tools.- `release.command` — builds, zips (`ditto`) and emits a SHA-256 checksum into `dist/`.
- GitHub Actions workflows for CI and tagged releases.
- Procedurally generated app icon (`tools/make_icon.py`, standard library only).

### Known limitations

- The user interface is currently **Simplified Chinese only**.
- Release builds are **ad-hoc signed**, not notarized, so macOS Gatekeeper requires a
  right-click → Open on first launch.

[1.0.0-beta]: https://github.com/wang90/disk-cleaner/releases/tag/v1.0.0-beta
