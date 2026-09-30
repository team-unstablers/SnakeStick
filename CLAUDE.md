# SnakeStick — notes for coding agents

SnakeStick writes Windows 10/11 installation media on macOS. Read `README.md` first; it describes the
design. This file is about working in the repository.

## Layout

| Path | What | Own docs |
|---|---|---|
| `SnakeStick/` | Xcode project: the app and the `SnakeStickHelper` root daemon | — |
| `SnakeStickCore/` | SwiftPM package: pipeline library and the `snakestick` CLI (planned, stage 10) | — |
| `slopdisk/` | GPT engine and raw device backend (SlopDisk) | `slopdisk/README.md`, `slopdisk/CLAUDE.md` |
| `NTFS3G/` | libntfs-3g wrapper (submodule at `NTFS3G/Vendor/ntfs-3g`) | `NTFS3G/README.md`, `NTFS3G/CLAUDE.md` |
| `WIMLib/` | wimlib wrapper (submodule at `WIMLib/Vendor/wimlib`; planned) | `WIMLib/Prompts/10-swift-api.xml` |
| `Prompts/` | Task documents (`<agent-task>`) and their reports for the top-level work | — |
| `SnakeStick.xcworkspace` | Workspace that references the project and the packages | — |

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

Long test runs: wrap them in a timeout so a stall is noticed (`timeout 600 swift test ...` or a
kill-after loop).

## Safety rules for disk devices

These rules protect the developer's machine. They apply to code and to anything you run by hand.

- Never open, format, partition or write to a device path you guessed or typed from memory
  (`disk0`, `disk1`, ...). The only acceptable source of a device path in tests is the output of the
  `hdiutil attach` that the same test just ran on an image it created, checked against
  `^/dev/r?disk[0-9]+(s[0-9]+)?$`.
- Always attach images with `hdiutil attach -nomount -imagekey diskimage-class=CRawDiskImage`.
- Never run `snakestick make`, or the app's write path, against a real disk as part of automated
  testing. Manual runs against a real USB stick are the user's call; record them in the report.
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
