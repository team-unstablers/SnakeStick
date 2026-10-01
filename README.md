<p align="center">
  <img src="docs/images/icon.png" width="160" height="160" alt="SnakeStick app icon: a snake-kin woman holding out a red apple">
</p>

<h1 align="center">SnakeStick</h1>

<p align="center">
  <b>Make a bootable Windows 10 / 11 USB installer on your Mac.</b><br>
  Pick an ISO, pick a stick, press Start. No Terminal, no Boot Camp, no splitting <code>install.wim</code>.
</p>

<p align="center">
  <a href="https://github.com/team-unstablers/SnakeStick/releases/latest"><img alt="Download the latest release" src="https://img.shields.io/badge/Download-Latest%20release-B3122E?style=for-the-badge&logo=github&logoColor=white"></a>
  <img alt="macOS 26.6 or later" src="https://img.shields.io/badge/macOS-26.6%2B-0E0B10?style=for-the-badge&logo=apple&logoColor=white">
  <img alt="Windows 10 and 11" src="https://img.shields.io/badge/Windows-10%20%7C%2011-0E0B10?style=for-the-badge">
  <a href="COPYING"><img alt="License: GPL-3.0" src="https://img.shields.io/badge/License-GPL--3.0-0E0B10?style=for-the-badge"></a>
</p>

<p align="center">
  <b>English</b> · <a href="README.ko.md">한국어</a> · <a href="README.ja.md">日本語</a> · <a href="README.zh-Hans.md">简体中文</a> · <a href="README.zh-Hant.md">繁體中文</a> · <a href="README.de.md">Deutsch</a> · <a href="README.fr.md">Français</a> · <a href="README.es.md">Español</a> · <a href="README.pt-BR.md">Português (Brasil)</a> · <a href="README.ru.md">Русский</a>
</p>

<p align="center">
  <img src="docs/images/screenshot.png" width="592" alt="SnakeStick copying a Windows 11 ISO to a USB stick, step 6 of 8">
</p>

---

## ✨ Why SnakeStick

- 🪟 **Just the app.** Choose a Windows 10 or 11 ISO (or drop it on the window), choose a USB stick, press **Start Writing**.
- 📦 **Big install files are fine.** Recent Windows ISOs carry an `install.wim` larger than 4 GB, which a FAT32 stick
  cannot hold. SnakeStick puts Windows on an NTFS partition and adds a small boot partition with the
  [UEFI:NTFS](https://github.com/pbatard/uefi-ntfs) loader, the same layout [Rufus](https://rufus.ie) uses. Nothing gets split.
- 🔐 **Works with Secure Boot.** The bundled boot loader is signed by Microsoft. For PCs that have revoked Microsoft's
  2011 certificate, SnakeStick can use the Windows UEFI CA 2023 signed boot loaders from Windows 11 25H2 or later ISOs.
- ✅ **Checks its own work.** After writing, it reads the whole stick back and compares it with the ISO, file by file.
- 🛡️ **Keeps away from your Mac's disks.** Only external and removable disks are listed. Internal disks and the startup
  disk never show up, the target is checked again right before writing, and nothing is erased until you confirm.
- 🧹 **No Mac leftovers.** The Windows partition is written without ever being mounted, so no `.DS_Store`, `._` or
  `.fseventsd` files end up on the stick.
- 🍎 **A native Mac app.** Written in Swift and SwiftUI, in English, Korean, Japanese, Chinese (Simplified and
  Traditional), German, French, Spanish, Brazilian Portuguese and Russian. Free and open source under the GPLv3.

## 📥 Download

Download the latest version from the **[Releases](https://github.com/team-unstablers/SnakeStick/releases/latest)** tab,
then move **SnakeStick** to your **Applications** folder. The app is signed and notarized by Apple.

## 🧰 What you need

| | |
|---|---|
| **Mac** | macOS Tahoe 26.6 or later, and an administrator password |
| **Windows ISO** | A Windows 10 or 11 installation ISO, for example from Microsoft's [Windows 11](https://www.microsoft.com/software-download/windows11) or [Windows 10](https://www.microsoft.com/software-download/windows10) download page |
| **USB stick** | Large enough for the ISO; sticks that are too small are greyed out. 16 GB is a safe size for current Windows 11 ISOs. |
| **Target PC** | A PC that boots in UEFI mode. Legacy BIOS (CSM) boot is not supported. |

> [!CAUTION]
> Writing **erases everything** on the selected USB stick. Copy anything you want to keep off it first.

## 🔑 First launch: two one-time permissions

SnakeStick writes the stick through a small helper that runs in the background with administrator rights, so the app
itself never has to run as root. macOS asks you to approve that helper once:

1. **Allow the helper.** The first time you press **Start Writing**, macOS asks you to allow SnakeStick's helper.
   Turn on **SnakeStick** in **System Settings › General › Login Items & Extensions**, then try again.
2. **Grant Full Disk Access.** macOS keeps background helpers away from removable disks and from folders such as
   **Downloads** unless the app has Full Disk Access. Add **SnakeStick** in **System Settings › Privacy & Security ›
   Full Disk Access**. SnakeStick tells you when this is missing and has a button that opens the right page.

After that, SnakeStick asks for your administrator password once each time you write a stick.

## 🚀 Making a stick

1. **Choose the ISO.** Click **Choose…** under **Source ISO**, or drop the ISO onto the window. SnakeStick shows the
   Windows version, the architecture and the size.
2. **Choose the stick.** Plug it in and pick it under **Target Disk**.
3. **Check the options.**
   - **Volume Label**: the name of the stick. It defaults to the ISO's own label.
   - **Verify after writing**: on by default. It adds a few minutes, and it is worth them.
   - **Use Windows UEFI CA 2023 signed boot loaders**: only needed for PCs that have revoked Microsoft's 2011 Secure
     Boot certificate, and only available with Windows 11 25H2 or later ISOs. If you are not sure, leave it off.
4. **Press Start Writing**, confirm with **Erase and Write**, and enter your administrator password.
5. **Wait.** The progress bar shows the current step (8 in all) and the time left. On the USB 3 stick we tested, an
   8.7 GB Windows 11 ISO took about 16 minutes including verification.
6. **Eject** the stick when SnakeStick says it's finished.

You can **Stop** at any time. The stick is then left unbootable, and writing it again starts over from the beginning.

## 💻 Booting the PC from the stick

1. Plug the stick into the PC and turn it on while pressing the boot menu key. It is usually **F12**, **F11**, **F8**
   or **Esc**; check your PC's manual.
2. Pick the **UEFI** entry for the USB stick.
3. Windows Setup starts.

If the PC refuses to start from the stick with Secure Boot on, look in its firmware settings for an option such as
**"Allow Microsoft 3rd Party UEFI CA"** and turn it on. Some PCs, Secured-core PCs in particular, ship with it off,
and the UEFI:NTFS boot loader needs it. Turning Secure Boot off for the installation works too; turn it back on
afterwards.

## ❓ FAQ

<details>
<summary><b>Why does it need Full Disk Access?</b></summary>
<br>

The part of SnakeStick that writes the stick is a background helper (a launchd daemon). macOS does not let such
helpers open removable disks, or read an ISO in folders such as Downloads, unless the app they belong to has Full
Disk Access, and there is no narrower permission a helper can ask for. You grant it to the SnakeStick app, and it
reaches the helper inside the app.

</details>

<details>
<summary><b>Why not just format the stick as FAT32, like Boot Camp Assistant did?</b></summary>
<br>

FAT32 cannot hold a file of 4 GB or more, and `sources/install.wim` in current Windows ISOs is usually larger than
that. The usual workaround is to split the file. SnakeStick keeps it whole on an NTFS partition instead, and a tiny
FAT partition next to it holds the UEFI:NTFS loader, which teaches the PC's firmware to read NTFS.

</details>

<details>
<summary><b>Can it skip Windows 11's TPM or Secure Boot requirements?</b></summary>
<br>

No. SnakeStick copies the ISO as it is. It does not bypass the hardware requirements, add answer files for unattended
installs, or inject drivers.

</details>

<details>
<summary><b>What happens if I pull the stick out or stop halfway?</b></summary>
<br>

SnakeStick cleans up after itself, and the stick is left unbootable. Write it again and it will be fine. Your Mac's
own disks are never touched.

</details>

<details>
<summary><b>Can I make a disk image instead of writing to a stick?</b></summary>
<br>

Not from the app. SnakeStick writes to USB sticks only.

</details>

> [!NOTE]
> SnakeStick is young. Sticks made with it have booted into Windows Setup on an x64 PC with Secure Boot on, but a
> complete Windows installation from one has not been tested yet. If something goes wrong, please
> [open an issue](https://github.com/team-unstablers/SnakeStick/issues) and attach the log (**Show Log…** in the app).

## 🙏 Built on

SnakeStick would not exist without this free software. Thank you!

- [ntfs-3g](https://github.com/tuxera/ntfs-3g): creates and writes the NTFS partition
- [UEFI:NTFS](https://github.com/pbatard/uefi-ntfs): the boot loader that lets UEFI firmware start Windows from NTFS
- [wimlib](https://github.com/ebiggers/wimlib): reads the Windows boot image
- [Rufus](https://github.com/pbatard/rufus): its source code was used as a reference

SnakeStick was written by an LLM-based coding agent under human supervision.

## 🐍 About the icon

The serpent of Eden, holding out an apple to your Mac. The apple is whole: nobody has taken a bite yet.

## 🛠️ For developers

How SnakeStick works, building it from source and running the tests: see [docs/DESIGN.md](docs/DESIGN.md).

## 📄 License

SnakeStick is free software under the [GNU General Public License v3.0 or later](COPYING). It comes with no warranty.
The bundled components keep their own licenses; see [docs/DESIGN.md](docs/DESIGN.md#license).
