# SnakeStick — design notes

A Windows 10/11 USB installer creator for macOS.

This document is for building SnakeStick from source and working on it: the command-line tool, how
the pipeline works, the design decisions and the known limitations. What the app does and how to use
it is in the [README](../README.md).

# STATUS

Implemented. The task documents in `Prompts/` track the work:

| Stage | Document | Scope | State |
|---|---|---|---|
| 00 | `Prompts/00-metainit.xml` | Design interview and decisions | done (2026-09-30) |
| 10 | `Prompts/10-implementation.xml` | Core library, CLI, privileged helper, GUI | implemented (`Prompts/10-implementation.report.md`) |

SnakeStick is built on three packages in this repository, each with its own task documents and reports:

| Package | Role | State |
|---|---|---|
| `slopdisk/` | GPT partition tables, raw device backend (`SDRawDevice`) | stages 10 and 20 implemented |
| `NTFS3G/` | NTFS volumes in user space on top of libntfs-3g | stages 10 and 20 (`removeItem`) implemented |
| `WIMLib/` | WIM metadata and extraction on top of wimlib | stage 10 implemented |

A stick written by `snakestick make` from a Windows 11 ISO has booted into Windows Setup on an x64 PC
with Secure Boot on. A complete installation from such a stick has not been tried yet.

# SYNOPSIS

```shell
# The app (writes to USB sticks only; follows the Figma mockups)
open SnakeStick.app

# Write an ISO to a USB stick (needs root; asks you to type the disk name unless --yes)
sudo snakestick make win11.iso disk4

# Build a raw disk image instead (no root needed)
# The image size is computed from the ISO contents by default.
snakestick build -o win11_usb_image.img win11.iso
snakestick build --imgsize 7.5G -o win11_usb_image.img win11.iso

# List the disks make can write to (and why the others are left out), or inspect an ISO
snakestick disks
snakestick info win11.iso
```

`--imgsize` uses SI units: `1G` is 1,000,000,000 bytes. A stick sold as "8 GB" often holds slightly
less than 8,000,000,000 bytes, so check the actual capacity of the smallest stick you plan to use.

Options shared by `make` and `build`: `--label` (volume label, defaults to the ISO's label),
`--no-verify` (skip reading the written files back), `--ca-2023` (use the Windows UEFI CA 2023
signed boot loaders from the ISO; Windows 11 25H2, build 26200, or later), `--verbose` (print every
step and external command to stderr).

Exit codes follow `sysexits.h`: 0 success, 1 declined at the confirmation, 64 usage, 65 not a
Windows ISO, 66 ISO missing, 69 target not eligible or too small, 73 image file exists, 74 I/O or
verification failure, 77 `make` without root, 130 interrupted (Ctrl-C; cleanup runs first).

## The app

The app offers `make` only. It lists external and removable disks, greys out the ones too small for
the chosen ISO, and asks before erasing. The write runs in a root helper daemon that the app
registers with `SMAppService`. Two one-time approvals are needed:

1. **Login Items.** The first write asks you to allow the helper in System Settings > General >
   Login Items.
2. **Full Disk Access.** macOS keeps launchd daemons, even root ones, away from removable disks and
   from folders such as `~/Downloads` unless they have Full Disk Access. Add **SnakeStick** (the app;
   this covers the helper inside it) in System Settings > Privacy & Security > Full Disk Access. The
   app shows a notice with a button to that page when the helper reports it is missing.

Every write then asks for an administrator once; the helper requests the right through the app's
authorization, so the dialog appears in your session.

# HOW IT WORKS

SnakeStick partitions the target directly and builds each file system on its partition slice. No
intermediate disk image is involved. `make` and `build` share one code path: `make` opens
`/dev/rdiskN`, `build` creates a sparse file and attaches it with `hdiutil` to get the same kind of
device.

1. **Open the ISO.** It is mounted read-only with `hdiutil`. The volume label comes from the ISO
   9660 descriptor. The Windows release and architecture come from the XML of
   `sources/install.wim` (or `install.esd`), as Rufus reads them, with `sources/boot.wim` image 2 as
   the fallback. The required size is estimated from the file tree (NTFS3G).
2. **Prepare the target.** The disk is checked again against the eligibility rules (whole, external
   or removable, not a disk image or APFS container, not beneath the startup disk, large enough), a
   DiskArbitration mount-approval callback starts refusing every mount of it, and its volumes are
   unmounted.
3. **Write the partition table with SlopDisk.** A GPT with two partitions: an NTFS data partition
   (Microsoft Basic Data) that takes all the space, and a 1 MiB FAT partition in the last MiB before
   the backup GPT (EFI System Partition, named `UEFI:NTFS`) for the UEFI:NTFS boot loader. This is the
   layout Rufus uses.
4. **Check the slices.** The kernel publishes `diskNs1` and `s2` after the table is written. Their
   parent disk, byte offset, size and block size (IOKit) are compared with what SlopDisk wrote before
   anything is formatted.
5. **Format the NTFS partition with NTFS3G.** mkntfs runs in-process on the slice, with the disk's
   sector size and the partition's start LBA recorded in the boot sector. Nothing is mounted for
   writing, so no macOS metadata ends up in the Windows partition.
6. **Copy the files** from the ISO into the NTFS partition through libntfs-3g. Files of 4 GiB or
   larger, such as `sources/install.wim`, are copied as they are; nothing is split. With
   `--ca-2023`, the boot loaders and fonts are replaced by the 2023-signed ones extracted from
   `boot.wim`, the way Rufus does it.
7. **Prepare the UEFI:NTFS partition.** `newfs_msdos` (FAT12 at 1 MiB), then the Secure Boot signed
   UEFI:NTFS loader and NTFS driver (x64 and ARM64) are copied in through a short read-write mount;
   the metadata macOS leaves (`.fseventsd` and the like) is removed before it is unmounted.
8. **Verify.** The partition table is read back with SlopDisk and the FAT files are hashed. Unless
   verification is off, the NTFS partition is read back with NTFS3G and compared with the ISO file by
   file, byte by byte.

Cancelling (Ctrl-C, or Stop in the app) stops at the next check, cleans up (unmounts, detaches the
ISO and any image, releases the mount guard, removes the work directory under `/tmp`) and leaves the
stick unbootable.

# DESIGN NOTES

- **Direct partitioning.** An earlier design built a complete disk image first and only block-copied
  it to the stick, to keep SlopDisk (written by an LLM coding agent) away from real disks. It was
  dropped: once the partition table is on the device, the kernel's partition slices give mkntfs the
  "device with just one partition" it needs, and the temporary partition image, the extra copy and
  the sparse-file bookkeeping all disappear. The price is that the disk-selection rules and the
  confirmation step are the last line of defense, so they are checked in the app, in the CLI and
  again in the helper, and slices are matched against the table before they are formatted.
- **UEFI only.** Legacy BIOS boot is not supported. Windows 11 requires UEFI, and BIOS boot would need
  an MBR plus partition boot code.
- **NTFS plus UEFI:NTFS instead of FAT32.** FAT32 cannot hold files of 4 GiB or larger, and
  `sources/install.wim` often exceeds that. Instead of splitting the WIM, the installation files live on
  an NTFS partition. Most UEFI firmware only reads FAT, so a small FAT partition carries
  [UEFI:NTFS](https://github.com/pbatard/uefi-ntfs), a boot loader that loads an NTFS driver and then
  starts `\EFI\BOOT\BOOTX64.EFI` from the NTFS partition. Rufus uses the same arrangement.
- **NTFS in user space.** NTFS volumes are created by NTFS3G, a Swift package in this repository that
  wraps libntfs-3g, vendored as an unmodified submodule. WIMLib does the same for wimlib.
- **A root daemon for the app.** The app never runs as root. The helper daemon is registered with
  `SMAppService`, accepts XPC connections only from the app (same Team ID and bundle identifier),
  checks the target again, acquires an Authorization Services right (`pl.unstabler.aislop.SnakeStick.write`,
  authenticate as admin) through the authorization the app sends, and only then runs the pipeline.
  It runs one job at a time, cancels it if the app disconnects, and exits when idle. The CLI runs the
  same pipeline in-process under `sudo`.
- **Automatic mounts are refused, not raced.** macOS probes and mounts new slices as soon as the
  partition table appears. A DiskArbitration mount-approval callback refuses every mount of the
  target while SnakeStick works, except the two mounts of the FAT partition that SnakeStick itself
  requests.
- **Verification by reading back.** The NTFS partition is compared with the ISO through NTFS3G, not
  through macOS's NTFS driver, so the check does not depend on FSKit and does not mount the volume.
- **Bundled boot loaders.** The UEFI:NTFS loader and NTFS driver are Microsoft-signed binaries taken
  unmodified from the upstream releases; `SnakeStickCore/Scripts/update-uefi-ntfs.sh` downloads them
  and records versions, URLs and SHA-256 hashes in `VERSIONS.md` next to them, and a test checks the
  hashes. They cannot be rebuilt without losing the signature.

# NON-GOALS

- Bypassing Windows 11 hardware requirements, unattended-install answer files, driver injection.
- Installing or updating Secure Boot certificates on the target PC.
- Legacy BIOS boot.
- Writing images to disks (`dd`-style) or writing from the app to image files; `build` is CLI-only.

# KNOWN LIMITATIONS

These are accepted trade-offs, not design goals.

- **Images are not bit-for-bit reproducible.** mkntfs assigns a random volume serial number, and NTFS
  records creation and MFT change times that cannot be preset, so images differ between runs.
- **`build` images are tied to their size.** The NTFS partition fills the image, so an image cannot
  be written to a smaller stick, and if it is written to a larger one with `dd` the backup GPT ends
  up at the end of the image rather than the end of the disk. Firmware and partitioning tools may
  warn about or reject this. `make` writes a fresh table sized to the stick and has neither problem.
- **NTFS goes through the buffered slice.** libntfs-3g issues reads and writes that are not whole
  sectors, which raw disk nodes (`/dev/rdiskNs1`) reject with `EINVAL`. NTFS3G is therefore given
  `/dev/diskNs1`, which goes through the buffer cache. On the stick that was measured this copied at
  about 57% of a raw sequential write (12.9 vs 22.5 MB/s); an 8.7 GB ISO took 16 minutes including
  verification.
- **The FAT partition does not start on a 1 MiB boundary.** It takes exactly the last MiB before the
  backup GPT, which leaves the NTFS partition (aligned at its start) a size that is not a whole number
  of MiB.
- **Booting depends on UEFI:NTFS.** The loader and its NTFS driver are third-party code. Some PCs only
  boot it with Secure Boot enabled after the "3rd party UEFI CA" is allowed in the firmware settings.
  Microsoft's 2011 Secure Boot certificates expire in 2026; the `--ca-2023` option covers the Windows
  boot loaders, and whether UEFI:NTFS itself is signed with the 2023 CA has not been verified.
- **Windows compatibility of NTFS3G volumes is only partly verified.** libntfs-3g creates file names in
  the POSIX namespace and does not generate DOS 8.3 names. Windows Setup has started from such a
  stick; a full installation and `chkdsk` have not been tried.
- **The app needs Full Disk Access** (see [The app](#the-app)), because the helper that writes the
  disk is a launchd daemon and macOS gives daemons no way to ask for narrower permissions.

# REQUIREMENTS

- macOS 26 for the app (deployment target 26.6); macOS 14 for `SnakeStickCore` and the CLI
- Xcode 27 / Swift 6.4 to build (the packages use swift-tools-version 6.4)

# TESTING

```sh
cd SnakeStickCore && swift test                                # unit tests, no devices
cd SnakeStickCore && SNAKESTICK_TEST_INTEGRATION=1 swift test  # also builds fixture ISOs and images with hdiutil
xcodebuild -workspace SnakeStick.xcworkspace -scheme SnakeStick -configuration Debug build
```

The integration tests need no root. They make small Windows-like ISOs with `hdiutil makehybrid`, run
the whole pipeline against sparse images attached with `hdiutil attach -nomount`, and read the
results back. Device paths come only from the output of the `hdiutil attach` a test just ran. No
automated test writes to a real disk.

# LICENSE

GPL-3.0-or-later. The full text is in `COPYING`.

Bundled packages and binaries keep their own licenses:

- SlopDisk: Artistic License 2.0
- NTFS3G and libntfs-3g: GNU GPL version 2 or later
- WIMLib: GNU LGPL version 2.1 or later; wimlib: GNU GPL version 3 or later, with libwim also
  available under the GNU LGPL version 2.1 or later when built without libntfs-3g (as here)
- UEFI:NTFS loader and the ntfs-3g UEFI driver: GNU GPL version 2, shipped as the upstream signed
  binaries; versions, sources and hashes are in `SnakeStickCore/Sources/SnakeStickCore/Resources/UEFI-NTFS/VERSIONS.md`
