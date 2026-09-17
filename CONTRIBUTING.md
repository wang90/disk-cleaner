# Contributing to DiskCleaner

Thanks for taking the time to contribute! 🎉

## Ways to help

- **Report a bug** — use the bug report template. Please include your macOS version,
  whether your Mac is Apple Silicon or Intel, and the relevant lines from
  `~/Library/Logs/diskautoclean.log`.
- **Suggest a cleanup target** — very welcome. Please say which tier it belongs to and
  why it is safe to delete.
- **Translate the UI** — the interface is currently Simplified Chinese only.
  English (and other) localizations are the top roadmap item.
- **Improve the docs / screenshots** — typos, clearer wording, better examples.

## Project layout

| Path | What it is |
|---|---|
| `scripts/diskautoclean.sh` | The whole cleaning engine. POSIX-ish bash 3.2 (macOS default). |
| `Sources/*.swift` | SwiftUI app. No third-party dependencies. |
| `Resources/Info.plist` | Bundle metadata (version lives here). |
| `tools/make_icon.py` | Generates the app icon from scratch (stdlib only). |
| `build.command` | Builds `DiskCleaner.app` (universal). |
| `release.command` | Builds + zips + checksums into `dist/`. |

## Development

```bash
git clone https://github.com/wang90/disk-cleaner.git
cd disk-cleaner
./build.command            # build & run
./scripts/diskautoclean.sh --help
```

Requirements: macOS 14+, Command Line Tools (`xcode-select --install`) for the app;
a POSIX shell for the script.

### Useful dev flags

The app accepts a couple of flags that are handy when working on the UI:

```bash
open -n DiskCleaner.app --args --demo            # pre-load the storage breakdown
open -n DiskCleaner.app --args --settings-only   # render the Settings page as the window
```

There is also `DISKCLEANER_UI=settings|demo` as an environment-variable equivalent.

## Ground rules

**Safety first.** This tool deletes files unattended. Any change that touches deletion
behaviour must:

1. Keep the **home-directory whitelist** and the **protected-path guard** intact.
   Never add a target outside `$HOME` without a very good reason.
2. Delete by **age** whenever possible (only remove things nobody touched for N days).
3. Use NUL-safe iteration (`find -print0` + `read -d ''`) — never `for f in $(ls)`.
4. Never introduce a code path that can hang: every `du`/`find` must stay behind the
   existing timeout helpers.
5. Add new targets to the **lowest tier that makes sense**, never silently to tier 3.

**Style**

- Shell: bash 3.2 compatible (macOS default). No bash 4 features
  (no associative arrays, no `mapfile`, no `${var,,}`). Quote everything.
- Swift: Swift 5 language mode, no third-party packages, no `@State`
  (the SwiftUI macro plugin is not available with Command Line Tools only —
  use `@StateObject`).
- Keep the JSON protocol in sync between `scripts/diskautoclean.sh` and `Sources/Models.swift`.

## Pull requests

1. Fork, create a topic branch.
2. Make your change; keep commits focused and the message descriptive.
3. Run the checks:

   ```bash
   bash -n scripts/diskautoclean.sh
   ./scripts/diskautoclean.sh --status --json
   ./build.command
   ```

4. Update `CHANGELOG.md` under an `## [Unreleased]` heading if the change is user-visible.
5. Open the PR and describe **what** and **why**.

## License

By contributing you agree that your contributions are licensed under the
[MIT License](LICENSE).
