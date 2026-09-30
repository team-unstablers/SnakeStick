# SnakeStick

A Windows 10/11 USB installer creator for macOS.

# STATUS

Design is settled; the application is not implemented yet. The task documents in `Prompts/` track the work:

| Stage | Document | Scope | State |
|---|---|---|---|
| 00 | `Prompts/00-metainit.xml` | Design interview and decisions | done (2026-09-30) |
| 10 | `Prompts/10-implementation.xml` | Core library, CLI, privileged helper, GUI | pending |

SnakeStick is built on three packages in this repository, each with its own task documents and reports:

| Package | Role | State |
|---|---|---|
| `slopdisk/` | GPT partition tables, raw device backend (`SDRawDevice`) | stages 10 and 20 implemented |
| `NTFS3G/` | NTFS volumes in user space on top of libntfs-3g | stage 10 implemented; stage 20 (`removeItem`) pending |
| `WIMLib/` | WIM metadata and extraction on top of wimlib | stage 10 pending |

# SYNOPSIS

```shell
# Launch the GUI (writes to a USB stick; follows the Figma mockups)
open SnakeStick.app

# Write an ISO to a USB stick (needs root; asks you to type the disk name unless --yes)
sudo snakestick make 'win11.iso' disk4

# Build a raw disk image for later mass production (no root needed)
# The image size is computed from the ISO contents by default.
snakestick build -o 'win11_usb_image.img' 'win11.iso'
snakestick build --imgsize 7.5G -o 'win11_usb_image.img' 'win11.iso'

# List eligible target disks, or inspect an ISO
snakestick disks
snakestick info 'win11.iso'
```

`--imgsize` uses SI units: `1G` is 1,000,000,000 bytes. A stick sold as "8 GB" often holds slightly
less than 8,000,000,000 bytes, so check the actual capacity of the smallest stick you plan to use.

Options shared by `make` and `build`: `--label` (volume label, defaults to the ISO's label),
`--no-verify` (skip reading the written files back), `--ca-2023` (use the Windows UEFI CA 2023
signed boot loaders from the ISO; Windows 11 25H2 or later only).

# HOW IT WORKS (PLANNED)

SnakeStick partitions the target directly and builds each file system on its partition slice. No
intermediate disk image is involved. `make` and `build` share one code path: `make` opens
`/dev/rdiskN`, `build` creates a sparse file and attaches it with `hdiutil` to get the same kind of
device.

1. **Open the ISO.** It is mounted read-only with `hdiutil`. The volume label comes from the ISO
   9660 descriptor; the Windows version and architecture come from the XML in `sources/boot.wim`
   (WIMLib). The required size is estimated from the file tree (NTFS3G).
2. **Prepare the target.** The disk is checked again against the eligibility rules (external or
   removable, not the boot disk, large enough), unmounted, and a DiskArbitration mount-approval
   callback keeps macOS from mounting anything on it while SnakeStick works.
3. **Write the partition table with SlopDisk.** A GPT with two partitions: an NTFS data partition
   (Microsoft Basic Data) that takes all the space, and a 1 MiB FAT partition at the end of the disk
   (EFI System Partition, named `UEFI:NTFS`) for the UEFI:NTFS boot loader. This is the same layout
   Rufus uses.
4. **Check the slices.** The kernel publishes `/dev/rdiskNs1` and `s2` after the table is written.
   Their parent disk, offset and size are compared with what SlopDisk wrote before anything is
   formatted.
5. **Format the NTFS partition with NTFS3G.** mkntfs runs in-process on `/dev/rdiskNs1`. Nothing is
   mounted for writing, so no macOS metadata (`.fseventsd`, `.Spotlight-V100`, `._*`, `.DS_Store`)
   ends up in the Windows partition.
6. **Copy the files** from the ISO into the NTFS partition through libntfs-3g. Files of 4 GiB or
   larger, such as `sources/install.wim`, are copied as they are; nothing is split. With
   `--ca-2023`, the boot loaders are replaced by the 2023-signed ones extracted from `boot.wim`,
   the way Rufus does it.
7. **Prepare the UEFI:NTFS partition.** `newfs_msdos`, then the Secure Boot signed UEFI:NTFS loader
   and NTFS driver (x64 and ARM64) are copied in through a short read-write mount that is scrubbed
   before it is unmounted.
8. **Verify.** The partition table is read back with SlopDisk, the FAT files are hashed, and unless
   verification is off, the NTFS partition is read back with NTFS3G and compared with the ISO file
   by file.

Only `make` needs elevated privileges. The GUI runs the whole pipeline in a root helper daemon
(registered with `SMAppService`, reached over XPC) and asks for administrator authentication once
per write. The CLI runs it in-process under `sudo`.

# DESIGN NOTES

- **Direct partitioning.** An earlier design built a complete disk image first and only block-copied
  it to the stick, to keep SlopDisk (written by an LLM coding agent) away from real disks. It was
  dropped: once the partition table is on the device, the kernel's partition slices give mkntfs the
  "device with just one partition" it needs, and the temporary partition image, the extra copy and
  the sparse-file bookkeeping all disappear. The price is that the disk-selection rules and the
  confirmation step are now the last line of defense, so they are checked in the app and again in
  the helper.
- **UEFI only.** Legacy BIOS boot is not supported. Windows 11 requires UEFI, and BIOS boot would need
  an MBR plus partition boot code.
- **NTFS plus UEFI:NTFS instead of FAT32.** FAT32 cannot hold files of 4 GiB or larger, and
  `sources/install.wim` often exceeds that. Instead of splitting the WIM, the installation files live on
  an NTFS partition. Most UEFI firmware only reads FAT, so a small FAT partition carries
  [UEFI:NTFS](https://github.com/pbatard/uefi-ntfs), a boot loader that loads an NTFS driver and then
  starts `\EFI\BOOT\BOOTX64.EFI` from the NTFS partition. Rufus uses the same arrangement.
- **NTFS in user space.** NTFS volumes are created by NTFS3G, a Swift package in this repository that
  wraps libntfs-3g, vendored as an unmodified submodule. WIMLib does the same for wimlib.
- **Bundled boot loaders.** The UEFI:NTFS loader and NTFS driver are Microsoft-signed binaries taken
  unmodified from the upstream releases; their versions, URLs and SHA-256 hashes are recorded next
  to them and checked by a test. They cannot be rebuilt without losing the signature.

# NON-GOALS

- Bypassing Windows 11 hardware requirements, unattended-install answer files, driver injection.
- Installing or updating Secure Boot certificates on the target PC.
- Legacy BIOS boot.

# KNOWN LIMITATIONS

These are accepted trade-offs, not design goals.

- **Images are not bit-for-bit reproducible.** mkntfs assigns a random volume serial number, and NTFS
  records creation and MFT change times that cannot be preset, so images differ between runs.
- **`build` images are tied to their size.** The NTFS partition fills the image, so an image cannot
  be written to a smaller stick, and if it is written to a larger one with `dd` the backup GPT ends
  up at the end of the image rather than the end of the disk. Firmware and partitioning tools may
  warn about or reject this. `make` writes a fresh table sized to the stick and has neither problem.
- **Booting depends on UEFI:NTFS.** The loader and its NTFS driver are third-party code. Some PCs only
  boot it with Secure Boot enabled after the "3rd party UEFI CA" is allowed in the firmware settings.
  Microsoft's 2011 Secure Boot certificates expire in 2026; the `--ca-2023` option covers the Windows
  boot loaders, and whether UEFI:NTFS itself is signed with the 2023 CA has not been verified.
- **Windows compatibility of NTFS3G volumes is not yet verified.** libntfs-3g creates file names in the
  POSIX namespace and does not generate DOS 8.3 names. Windows is expected to handle this, but it has
  not been tested on real hardware yet.
- **Writing straight to the stick mixes random writes into the copy.** NTFS metadata updates are
  small random writes. This may be slower than the old image-first design on some sticks; it has not
  been measured yet.

# LICENSE

GPLv3

Bundled packages keep their own licenses: SlopDisk is under the Artistic License 2.0, NTFS3G and
libntfs-3g are under the GNU GPL version 2 or later, WIMLib and wimlib are under the GNU LGPL
version 3 or later. The bundled UEFI:NTFS loader and NTFS driver binaries are under the GNU GPL
version 2; their sources are the upstream releases recorded in `SnakeStickCore/Resources/UEFI-NTFS/VERSIONS.md`.
