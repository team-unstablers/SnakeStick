# SnakeStick

A Windows 10/11 USB installer creator for macOS.

# SYNOPSIS

```shell
# Launch the GUI
open SnakeStick.app

# Write an ISO to a USB stick
./SnakeStick.app/Contents/MacOS/SnakeStick make 'win11.iso' '/dev/disk42'

# Build a raw disk image for later mass production
# (the image size is computed from the ISO contents by default)
./SnakeStick.app/Contents/MacOS/SnakeStick build -o 'win11_usb_image.img' 'win11.iso'
./SnakeStick.app/Contents/MacOS/SnakeStick build --imgsize 7.5G -o 'win11_usb_image.img' 'win11.iso'

# Write a prebuilt image to a USB stick, fitting the GPT to the stick's size
./SnakeStick.app/Contents/MacOS/SnakeStick write 'win11_usb_image.img' '/dev/disk42'
```

`--imgsize` uses SI units: `1G` is 1,000,000,000 bytes. A stick sold as "8 GB" often holds slightly
less than 8,000,000,000 bytes, so check the actual capacity of the smallest stick you plan to use.

# HOW IT WORKS (PLANNED)

SnakeStick never partitions or formats the target disk directly. It prepares everything in a raw disk
image, and the only thing that ever touches the target disk is a plain block copy.

1. **Create a raw disk image.**
    - `make`: a sparse file exactly as large as the target disk. On APFS the unused space is not
      allocated, so this costs only as much as the contents.
    - `build`: sized from the ISO contents plus headroom, or as given by `--imgsize`.
2. **Partition it with SlopDisk.** A GPT with two partitions: an NTFS data partition (Microsoft Basic
   Data) sized to fit the contents, and a small FAT partition that holds the UEFI:NTFS boot loader.
   The rest of the disk is left unpartitioned. The order, position and type of the FAT partition are
   to be decided.
3. **Build the NTFS volume with NTFS3G.**
    - A separate, partition-sized image file is formatted with mkntfs, and the ISO contents are copied
      into it in user space through libntfs-3g. Nothing is mounted for writing.
    - The ISO itself is the copy source. How it is read (a read-only `hdiutil` mount or a built-in UDF
      reader) is to be decided.
    - Files of 4 GiB or larger, such as `sources/install.wim`, are copied as they are. Nothing is split.
    - File timestamps are preserved. Names that Windows cannot use are rejected.
4. **Add the UEFI:NTFS partition.** It contains the Secure Boot signed UEFI:NTFS loader and its NTFS
   driver. Whether it is written from a prebuilt FAT image or assembled from the signed binaries is
   to be decided.
5. **Assemble the disk image.** The NTFS partition image is copied into the disk image at the
   partition's offset, keeping the file sparse. `build` stops here.
6. **Write it to the target disk** (`make`, `write`).
    - Only this step needs elevated privileges.
    - The target is unmounted, and automatic mounting is blocked while writing.
    - Only the regions that matter are written: from the start of the image to the end of the last
      partition, and the backup GPT at the end of the disk.
    - For `write`, the protective MBR, the primary GPT header and the backup GPT are regenerated in
      memory to match the target disk's size.
    - The written data is read back and verified.

# DESIGN NOTES

- **Why image-first.** SlopDisk is written by an LLM coding agent. SnakeStick only uses it on image
  files and in-memory buffers, never on the target disk, even though SlopDisk has a raw device backend.
  The component that writes to the target
  disk copies byte ranges and knows nothing about partition tables. This also lets `make` and `build`
  share one code path, and confines elevated privileges to the final copy.
- **UEFI only.** Legacy BIOS boot is not supported. Windows 11 requires UEFI, and BIOS boot would need
  an MBR plus partition boot code.
- **NTFS plus UEFI:NTFS instead of FAT32.** FAT32 cannot hold files of 4 GiB or larger, and
  `sources/install.wim` often exceeds that. Instead of splitting the WIM, the installation files live on
  an NTFS partition. Most UEFI firmware only reads FAT, so a small FAT partition carries
  [UEFI:NTFS](https://github.com/pbatard/uefi-ntfs), a boot loader that loads an NTFS driver and then
  starts `\EFI\BOOT\BOOTX64.EFI` from the NTFS partition. Rufus uses the same arrangement.
- **NTFS in user space.** NTFS volumes are created by NTFS3G, a Swift package in this repository that
  wraps libntfs-3g, vendored as an unmodified submodule. Because nothing is mounted for writing, no
  macOS metadata (`.fseventsd`, `.Spotlight-V100`, `._*`, `.DS_Store`) ends up on the stick.

# KNOWN LIMITATIONS

These are accepted trade-offs, not design goals.

- **Images are not bit-for-bit reproducible.** mkntfs assigns a random volume serial number, and NTFS
  records creation and MFT change times that cannot be preset, so images differ between runs.
- **The NTFS partition is built as a separate file.** mkntfs can only format a whole file or device,
  not a region at an offset inside a larger image. NTFS3G therefore formats a partition-sized image,
  which is then copied into the disk image. This costs one extra copy.
- **Booting depends on UEFI:NTFS.** The loader and its NTFS driver are third-party code. Some PCs only
  boot it with Secure Boot enabled after the "3rd party UEFI CA" is allowed in the firmware settings.
  Microsoft's 2011 Secure Boot certificates expire in 2026; how SnakeStick handles the 2023
  certificates is to be decided.
- **Windows compatibility of NTFS3G volumes is not yet verified.** libntfs-3g creates file names in the
  POSIX namespace and does not generate DOS 8.3 names. Windows is expected to handle this, but it has
  not been tested on real hardware yet.
- **Plain `dd` leaves the backup GPT in the wrong place.** If a `build` image is written with `dd` to a
  larger stick, the backup GPT header ends up at the end of the image rather than the end of the disk.
  Firmware and partitioning tools may warn about or reject this. Use `SnakeStick write` instead.

# LICENSE

GPLv3

Bundled packages keep their own licenses: SlopDisk is under the Artistic License 2.0, and NTFS3G and
libntfs-3g are under the GNU GPL version 2 or later.
