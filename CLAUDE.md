# SnakeStick — notes for coding agents

SnakeStick writes Windows 10/11 installation media on macOS. Read `docs/DESIGN.md` first; it describes
the design, the CLI and the known limitations. `README.md` (and its Korean copy `README.ko.md`) is the
user-facing page for people who download the app; keep the two in step. This file is about working in
the repository.

## Layout

| Path | What | Own docs |
|---|---|---|
| `SnakeStick/` | Xcode project: the app (`SnakeStick/SnakeStick`), the `SnakeStickHelper` root daemon, the daemon's launchd plist (`LaunchDaemons/`) | — |
| `SnakeStickCore/` | SwiftPM package: the pipeline library `SnakeStickCore` and the `snakestick` CLI | `docs/DESIGN.md` |
| `slopdisk/` | GPT engine and raw device backend (SlopDisk) | `slopdisk/README.md`, `slopdisk/CLAUDE.md` |
| `NTFS3G/` | libntfs-3g wrapper (submodule at `NTFS3G/Vendor/ntfs-3g`) | `NTFS3G/README.md` |
| `WIMLib/` | wimlib wrapper (submodule at `WIMLib/Vendor/wimlib`) | `WIMLib/README.md`, `WIMLib/CLAUDE.md` |
| `Prompts/` | Task documents (`<agent-task>`) and their reports for the top-level work | — |
| `docs/` | `DESIGN.md` (design and developer notes) and the images the READMEs use (`docs/images/`) | — |
| `distutil/` | `build_dmg.sh`: the release DMG (archive, Developer ID export, notarization); output in `dist/` | `docs/DESIGN.md` |
| `SnakeStick.xcworkspace` | Workspace that references the project and the four packages | — |

`SnakeStickCore/Sources/SnakeStickCore/`: `Model.swift` (the public request, event and error types),
`ISOInfo.swift`, `DiskCandidates.swift`, `Installer.swift` (`runInstaller`, cleanup), `Pipeline/`
(one file per concern: partitioning, mount guard, boot partition, CA 2023, verification, progress),
`HelperProtocol.swift` (app ↔ daemon messages), `Resources/UEFI-NTFS/` (bundled signed loaders; update
them only with `Scripts/update-uefi-ntfs.sh`).

Every package has a `Prompts/` directory with numbered task documents and `*.report.md` files. A
stage is done when its report exists. Read the report before relying on a package's API; the report
records where the implementation deviated from the document.

## Build and test

```sh
cd slopdisk && swift test                                   # SLOPDISK_TEST_HDIUTIL_ATTACH=1 for the attach tests
cd NTFS3G && swift test                                     # NTFS3G_INTEGRATION=1 for the multi-GiB tests
cd WIMLib && swift test
cd SnakeStickCore && swift test                             # SNAKESTICK_TEST_INTEGRATION=1 for the end-to-end build test
xcodebuild -workspace SnakeStick.xcworkspace -scheme SnakeStick -configuration Debug build
```

Long test runs: wrap them in a timeout so a stall is noticed. macOS has no `timeout`; use a
kill-after loop (`cmd & pid=$!; for …; do sleep 1; kill -0 $pid || break; done`).

- `SNAKESTICK_TEST_INTEGRATION=1` runs every suite nested in `IntegrationTests` (serialized as a
  whole): fixture ISOs made with `hdiutil makehybrid`, the whole pipeline on attached images, and the
  built `snakestick` binary. About 30 seconds, no root.
- The Xcode build puts its products under `~/Library/Developer/Xcode/DerivedData/Build/Products/`
  on this machine (the workspace setting), not under a per-project DerivedData folder.
- The app registers the daemon with `SMAppService`; the first time, it has to be allowed in System
  Settings > General > Login Items. The app also needs Full Disk Access (granted to the app, it
  covers the daemon inside the bundle): TCC keeps launchd daemons, root or not, away from
  removable disks and `~/Downloads`. The daemon logs to the unified log, subsystem
  `pl.unstabler.aislop.SnakeStick.helper`; read it with `/usr/bin/log` (zsh has a `log` builtin).
- Do not rebuild the app while its helper is writing: the build replaces the helper binary the
  running daemon was started from. The daemon exits when it has no connections and no job, and the
  next connection starts the new binary.
- Command-line `xcodebuild` leaves empty `.swiftpm/xcode` directories in packages that Xcode has not
  opened; Xcode then fails to load those packages ("Couldn't load project “xcode”"). Remove the
  empty directories, or open the workspace in Xcode once.
- NTFS3G is given the buffered slice `/dev/diskNs1`, not `/dev/rdiskNs1`: libntfs-3g issues
  unaligned I/O that raw nodes reject (U11 in `Prompts/10-implementation.report.md`). Everything else
  (SlopDisk, `newfs_msdos`) uses raw nodes.

## Safety rules for disk devices

These rules protect the developer's machine. They apply to code and to anything you run by hand.

- Never open, format, partition or write to a device path you guessed or typed from memory
  (`disk0`, `disk1`, ...). The only acceptable source of a device path in tests is the output of the
  `hdiutil attach` that the same test just ran on an image it created, checked against
  `^/dev/r?disk[0-9]+(s[0-9]+)?$`.
- Always attach images with `hdiutil attach -nomount -imagekey diskimage-class=CRawDiskImage`.
- Never run `snakestick make`, or the app's write path, against a real disk as part of automated
  testing. Manual runs against a real USB stick are the user's call; record them in the report.
  Identify the stick by diffing the disk list from before and after the user plugs it in, show its
  model and size, and have the user confirm it before anything opens it. Writing needs root: hand
  the user the exact `sudo` command instead of trying to escalate.
- `grep -rn dataLossRisk SnakeStickCore/Sources` must find exactly one line
  (`Partitioning.writePartitionTable`).
- Every read-write open of a device goes through `SDRawDevice(path:acknowledging: .dataLossRisk)`.
  `grep -rn dataLossRisk` should find exactly the places that are meant to write.
- NTFS3G's `format(path:)` does not check what the path is. Only hand it a partition slice
  (`/dev/rdiskNsK`) whose parent, offset and size were verified against the partition table.
- Detach every test image afterwards. `hdiutil info | grep -c image-path` must be the same before
  and after a test run.

## Git

Several agent sessions work in this repository at the same time, each in its own directory.

- Stage and commit with explicit paths only: `git add -- <paths>` and `git commit -m "..." -- <paths>`.
- Never use `git add -A`, `git add .`, `git commit -a`, `git stash`, or `git reset` without a path.
  They pick up or discard other sessions' work.
- Do not touch another package's directory unless the task document says so. Problems found there
  go into the report, not into a fix.
- Commit titles are short English imperatives ("Add ...", "Implement ...", "Switch ..."). No
  co-author trailers.
- Submodules stay unmodified. `git -C <submodule> status --short` must be empty. Workarounds live
  in the wrapper package.

## Task documents

Task documents use the `<agent-task>` XML-like format (the `agentxml` skill). `mode="execute"`
documents are meant to be carried out as written; blocks marked "다시 묻지 말 것" are settled
decisions. When the code contradicts a document, stop and report rather than improvising.
