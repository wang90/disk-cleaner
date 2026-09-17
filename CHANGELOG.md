# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] — 2026-09-17

First public release. 🎉

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
- Settings window with app info and theme selection: **Follow system / Light / Dark**.
- Decimal units for storage (matching macOS) and binary units for memory (matching
  About This Mac).

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
  macOS Command Line Tools.
- `release.command` — builds, zips (`ditto`) and emits a SHA-256 checksum into `dist/`.
- GitHub Actions workflows for CI and tagged releases.
- Procedurally generated app icon (`tools/make_icon.py`, standard library only).

### Known limitations

- The user interface is currently **Simplified Chinese only**.
- Release builds are **ad-hoc signed**, not notarized, so macOS Gatekeeper requires a
  right-click → Open on first launch.

[1.0.0]: https://github.com/wang90/disk-cleaner/releases/tag/v1.0.0
