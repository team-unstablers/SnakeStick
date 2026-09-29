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
2. **Partition it with SlopDisk.** A GPT with a single Microsoft Basic Data partition, sized to fit
   the contents. The rest of the disk is left unpartitioned.
3. **Format it.** Attach the image with `hdiutil attach -imagekey diskimage-class=CRawDiskImage -nomount`
   and run `newfs_msdos -F 32` on the partition.
4. **Copy the ISO contents.**
    - The partition is mounted with `nobrowse`, and files are copied without extended attributes or
      quarantine flags.
    - FAT32 cannot hold files of 4 GiB or larger. If `sources/install.wim` (or `install.esd`) exceeds
      that limit, it is split into `install.swm`, `install2.swm`, ... using libwim's `wimlib_split()`.
      libwim is statically linked.
    - macOS metadata (`.fseventsd`, `.Spotlight-V100`, `._*`, `.DS_Store`) is removed before unmounting.
5. **Detach the image.** `build` stops here.
6. **Write it to the target disk** (`make`, `write`).
    - Only this step needs elevated privileges.
    - The target is unmounted, and automatic mounting is blocked while writing.
    - Only the regions that matter are written: from the start of the image to the end of the
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
  an MBR plus FAT32 boot code.
- **A single Basic Data partition, no separate ESP.** UEFI firmware boots removable media from
  `\EFI\BOOT\BOOTX64.EFI` on a FAT partition, so a separate ESP is unnecessary. A single partition keeps
  `bootmgr` and `sources/boot.wim` together. Windows may also not assign a drive letter to an ESP-typed
  partition, which could keep Windows Setup from finding its installation files.

# KNOWN LIMITATIONS

These are accepted trade-offs, not design goals.

- **Images are not bit-for-bit reproducible.** The FAT32 volume is created with `newfs_msdos` and
  populated through a macOS mount, so volume serial numbers, timestamps and cluster placement differ
  between runs. Writing FAT32 directly would fix this, but SnakeStick uses the system tools for now.
- **Plain `dd` leaves the backup GPT in the wrong place.** If a `build` image is written with `dd` to a
  larger stick, the backup GPT header ends up at the end of the image rather than the end of the disk.
  Firmware and partitioning tools may warn about or reject this. Use `SnakeStick write` instead.

# LICENSE

GPLv3
