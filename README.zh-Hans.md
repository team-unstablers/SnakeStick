<p align="center">
  <img src="docs/images/icon.png" width="160" height="160" alt="SnakeStick 应用图标：一位递出红苹果的蛇人女性">
</p>

<h1 align="center">SnakeStick</h1>

<p align="center">
  <b>在 Mac 上制作可启动的 Windows 10 / 11 安装 U 盘。</b><br>
  选择 ISO，选择 U 盘，点按“开始”。无需终端，无需 Boot Camp，也无需拆分 <code>install.wim</code>。
</p>

<p align="center">
  <a href="https://github.com/team-unstablers/SnakeStick/releases/latest"><img alt="下载最新版本" src="https://img.shields.io/badge/Download-Latest%20release-B3122E?style=for-the-badge&logo=github&logoColor=white"></a>
  <img alt="macOS 14 或更高版本" src="https://img.shields.io/badge/macOS-14%2B-0E0B10?style=for-the-badge&logo=apple&logoColor=white">
  <img alt="Windows 10 和 11" src="https://img.shields.io/badge/Windows-10%20%7C%2011-0E0B10?style=for-the-badge">
  <a href="COPYING"><img alt="许可证：GPL-3.0" src="https://img.shields.io/badge/License-GPL--3.0-0E0B10?style=for-the-badge"></a>
</p>

<p align="center">
  <a href="README.md">English</a> · <a href="README.ko.md">한국어</a> · <a href="README.ja.md">日本語</a> · <b>简体中文</b> · <a href="README.zh-Hant.md">繁體中文</a> · <a href="README.de.md">Deutsch</a> · <a href="README.fr.md">Français</a> · <a href="README.es.md">Español</a> · <a href="README.pt-BR.md">Português (Brasil)</a> · <a href="README.ru.md">Русский</a>
</p>

<p align="center">
  <img src="docs/images/screenshot.png" width="592" alt="SnakeStick 正在将 Windows 11 ISO 拷贝到 U 盘（第 6 步，共 8 步）">
</p>

---

## ✨ 为什么选择 SnakeStick

- 🪟 **只需这一个 App**。选择 Windows 10 或 11 的 ISO（也可以直接拖放到窗口中），选择 U 盘，然后点按**开始写入**。
- 📦 **大型安装文件也没问题**。较新的 Windows ISO 中的 `install.wim` 超过 4 GB，FAT32 格式的 U 盘放不下。SnakeStick 将 Windows 放在 NTFS 分区上，并另外添加一个装有 [UEFI:NTFS](https://github.com/pbatard/uefi-ntfs) 引导加载程序的小型启动分区，与 [Rufus](https://rufus.ie) 采用的布局相同。不会拆分任何文件。
- 🔐 **支持 Secure Boot**。随附的引导加载程序由 Microsoft 签名。对于已吊销 Microsoft 2011 证书的 PC，SnakeStick 可以使用 Windows 11 25H2 或更高版本 ISO 中的 Windows UEFI CA 2023 签名引导加载程序。
- ✅ **自行检查写入结果**。写入完成后，它会重新读取整个 U 盘，并与 ISO 逐个文件进行比较。
- 🛡️ **不碰你 Mac 上的磁盘**。列表中只显示外置磁盘和可移除磁盘。内置磁盘和启动磁盘根本不会出现，写入前会再次检查目标磁盘，并且在你确认之前不会抹掉任何内容。
- 🧹 **不留 Mac 痕迹**。Windows 分区在写入过程中从不装载，因此 U 盘上不会出现 `.DS_Store`、`._` 或 `.fseventsd` 文件。
- 🍎 **原生 Mac App**。使用 Swift 和 SwiftUI 编写，支持英语、韩语、日语、简体中文、繁体中文、德语、法语、西班牙语、巴西葡萄牙语和俄语。依据 GPLv3 免费开源。

## 📥 下载

从 **[Releases](https://github.com/team-unstablers/SnakeStick/releases/latest)** 标签页下载最新版本，然后将 **SnakeStick** 移到“**应用程序**”文件夹。此 App 已由 Apple 签名并公证。

## 🧰 你需要准备什么

| | |
|---|---|
| **Mac** | macOS Sonoma 14 或更高版本，以及管理员密码 |
| **Windows ISO** | Windows 10 或 11 安装 ISO，例如可从 Microsoft 的 [Windows 11](https://www.microsoft.com/zh-cn/software-download/windows11) 或 [Windows 10](https://www.microsoft.com/zh-cn/software-download/windows10) 下载页面获取 |
| **U 盘** | 容量需足以容纳 ISO；容量太小的 U 盘会显示为灰色。对于当前的 Windows 11 ISO，16 GB 是稳妥的容量。 |
| **目标 PC** | 以 UEFI 模式启动的 PC。不支持传统 BIOS (CSM) 启动。 |

> [!CAUTION]
> 写入会**抹掉所选 U 盘上的所有内容**。请先将需要保留的内容拷贝出来。

## 🔑 权限

SnakeStick 通过 App 内的一个小型工具来写入 U 盘。这个工具只在写入期间以管理员权限运行，因此 App 本身无需以 root 身份运行。每次写入 U 盘时，macOS 都会要求你输入管理员密码。

**完全磁盘访问权限**。除非 App 拥有完全磁盘访问权限，否则 macOS 会阻止写入工具访问可移除磁盘以及“**下载**”等文件夹。在**系统设置 › 隐私与安全性 › 完全磁盘访问权限**中添加 **SnakeStick**。缺少此权限时，SnakeStick 会提示你，并提供一个用于打开相应设置页面的按钮。

## 🚀 制作 U 盘

1. **选择 ISO**。点按**源 ISO** 下方的**选取…**，或将 ISO 拖放到窗口中。SnakeStick 会显示 Windows 版本、架构和大小。
2. **选择 U 盘**。插入 U 盘，然后在**目标磁盘**下选择它。
3. **检查选项**。
   - **卷标**：U 盘的名称。默认使用 ISO 自身的卷标。
   - **写入后验证**：默认开启。会多花几分钟，但很值得。
   - **使用 Windows UEFI CA 2023 签名的引导加载程序**：仅在已吊销 Microsoft 2011 Secure Boot 证书的 PC 上需要，并且仅在使用 Windows 11 25H2 或更高版本的 ISO 时可用。如果不确定，请保持关闭。
4. 点按**开始写入**，选择**抹掉并写入**进行确认，然后输入管理员密码。
5. **等待**。进度条会显示当前步骤（共 8 步）和剩余时间。在我们测试的 USB 3 U 盘上，一个 8.7 GB 的 Windows 11 ISO 包括验证在内大约用时 16 分钟。
6. SnakeStick 提示完成后，**推出** U 盘。

你可以随时**停止**。停止后 U 盘将无法启动，再次写入时会从头开始。

## 💻 从 U 盘启动 PC

1. 将 U 盘插入 PC，按住启动菜单键的同时开机。通常是 **F12**、**F11**、**F8** 或 **Esc**；请查看 PC 的使用手册。
2. 选择 U 盘的 **UEFI** 启动项。
3. Windows 安装程序随即启动。

如果在开启 Secure Boot 的情况下 PC 拒绝从 U 盘启动，请在其固件设置中查找类似 **“Allow Microsoft 3rd Party UEFI CA”** 的选项并将其打开。部分 PC（尤其是 Secured-core PC）出厂时关闭了此选项，而 UEFI:NTFS 引导加载程序需要它。也可以在安装期间关闭 Secure Boot，安装完成后再重新打开。

## ❓ 常见问题

<details>
<summary><b>为什么需要完全磁盘访问权限？</b></summary>
<br>

SnakeStick 中负责写入 U 盘的部分是 App 内的一个独立工具，每次写入时都会以管理员权限启动。除非其所属的 App 拥有完全磁盘访问权限，否则 macOS 不允许这个工具打开可移除磁盘，也不允许其读取“下载”等文件夹中的 ISO，而且该工具也无法申请范围更小的权限。你只需将此权限授予 SnakeStick App，它就会作用到 App 内的工具。

</details>

<details>
<summary><b>为什么不像 Boot Camp 助理那样，直接把 U 盘格式化为 FAT32？</b></summary>
<br>

FAT32 无法存放 4 GB 或更大的文件，而当前 Windows ISO 中的 `sources/install.wim` 通常比这更大。常见的变通方法是拆分该文件。SnakeStick 则将它完整地保留在 NTFS 分区上，并在旁边放一个很小的 FAT 分区来存放 UEFI:NTFS 引导加载程序，让 PC 的固件能够读取 NTFS。

</details>

<details>
<summary><b>能绕过 Windows 11 的 TPM 或 Secure Boot 要求吗？</b></summary>
<br>

不能。SnakeStick 按原样拷贝 ISO。它不会绕过硬件要求，不会为无人值守安装添加应答文件，也不会注入驱动程序。

</details>

<details>
<summary><b>如果中途拔出 U 盘或停止写入，会怎样？</b></summary>
<br>

SnakeStick 会自行完成清理，U 盘将处于无法启动的状态。重新写入一次即可恢复正常。你 Mac 自身的磁盘永远不会受到影响。

</details>

<details>
<summary><b>可以制作磁盘映像，而不是写入 U 盘吗？</b></summary>
<br>

App 中不支持。SnakeStick 只能写入 U 盘。

</details>

> [!NOTE]
> SnakeStick 还很年轻。用它制作的 U 盘已在开启 Secure Boot 的 x64 PC 上成功启动到 Windows 安装程序，但尚未测试过用它完整安装 Windows。如果遇到问题，请[提交 Issue](https://github.com/team-unstablers/SnakeStick/issues) 并附上日志（App 中的**显示日志…**）。

## 🙏 基于以下软件构建

没有这些自由软件，就没有 SnakeStick。谢谢！

- [ntfs-3g](https://github.com/tuxera/ntfs-3g)：创建并写入 NTFS 分区
- [UEFI:NTFS](https://github.com/pbatard/uefi-ntfs)：让 UEFI 固件能够从 NTFS 启动 Windows 的引导加载程序
- [wimlib](https://github.com/ebiggers/wimlib)：读取 Windows 启动映像
- [Rufus](https://github.com/pbatard/rufus)：参考了其源代码

SnakeStick 由基于 LLM 的编程代理在人类监督下编写。

## 🐍 关于图标

伊甸园的蛇，正向你的 Mac 递出一个苹果。苹果完好无损：还没有人咬过一口。

## 🛠️ 面向开发者

SnakeStick 的工作原理、如何从源代码构建以及如何运行测试，请参阅 [docs/DESIGN.md](docs/DESIGN.md)（英文）。

## 📄 许可证

SnakeStick 是依据 [GNU General Public License v3.0 或更高版本](COPYING)发布的自由软件，不提供任何担保。随附的组件各自沿用其自身的许可证，请参阅 [docs/DESIGN.md](docs/DESIGN.md#license)。
