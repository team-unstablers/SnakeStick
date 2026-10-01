<p align="center">
  <img src="docs/images/icon.png" width="160" height="160" alt="SnakeStick App 圖像：遞出紅蘋果的蛇族女性">
</p>

<h1 align="center">SnakeStick</h1>

<p align="center">
  <b>在 Mac 上製作可開機的 Windows 10 / 11 USB 安裝隨身碟。</b><br>
  選擇 ISO、選擇隨身碟、按下開始，就完成了。不需要「終端機」、不需要 Boot Camp，也不必分割 <code>install.wim</code>。
</p>

<p align="center">
  <a href="https://github.com/team-unstablers/SnakeStick/releases/latest"><img alt="下載最新版本" src="https://img.shields.io/badge/Download-Latest%20release-B3122E?style=for-the-badge&logo=github&logoColor=white"></a>
  <img alt="macOS 14 或以上版本" src="https://img.shields.io/badge/macOS-14%2B-0E0B10?style=for-the-badge&logo=apple&logoColor=white">
  <img alt="Windows 10 與 11" src="https://img.shields.io/badge/Windows-10%20%7C%2011-0E0B10?style=for-the-badge">
  <a href="COPYING"><img alt="授權：GPL-3.0" src="https://img.shields.io/badge/License-GPL--3.0-0E0B10?style=for-the-badge"></a>
</p>

<p align="center">
  <a href="README.md">English</a> · <a href="README.ko.md">한국어</a> · <a href="README.ja.md">日本語</a> · <a href="README.zh-Hans.md">简体中文</a> · <b>繁體中文</b> · <a href="README.de.md">Deutsch</a> · <a href="README.fr.md">Français</a> · <a href="README.es.md">Español</a> · <a href="README.pt-BR.md">Português (Brasil)</a> · <a href="README.ru.md">Русский</a>
</p>

<p align="center">
  <img src="docs/images/screenshot.png" width="592" alt="SnakeStick 正在將 Windows 11 ISO 拷貝到 USB 隨身碟（8 個步驟中的第 6 步）">
</p>

---

## ✨ 為什麼選擇 SnakeStick

- 🪟 **只要一個 App。** 選擇 Windows 10 或 11 的 ISO（也可以直接拖到視窗上），選擇 USB 隨身碟，然後按下 **開始寫入**。
- 📦 **大型安裝檔案也沒問題。** 近期 Windows ISO 內的 `install.wim` 超過 4 GB，FAT32 格式的隨身碟放不下。SnakeStick 會將 Windows 放在 NTFS 分割區，並加上一個內含 [UEFI:NTFS](https://github.com/pbatard/uefi-ntfs) 載入程式的小型開機分割區，與 [Rufus](https://rufus.ie) 採用相同的配置。任何檔案都不會被分割。
- 🔐 **支援 Secure Boot。** 內附的開機載入程式由 Microsoft 簽署。對於已撤銷 Microsoft 2011 憑證的 PC，SnakeStick 可以改用 Windows 11 25H2 或以上版本 ISO 內的 Windows UEFI CA 2023 簽署開機載入程式。
- ✅ **自行檢查寫入結果。** 寫入完成後，會把整支隨身碟重新讀取一遍，並逐一檔案與 ISO 比對。
- 🛡️ **不會碰到 Mac 的磁碟。** 只會列出外接和可移除式磁碟。內建磁碟與啟動磁碟完全不會出現，寫入前一刻會再次檢查目標，而且在你確認之前不會清除任何資料。
- 🧹 **不留下 Mac 的痕跡。** Windows 分割區在寫入過程中完全不會被掛載，因此隨身碟上不會出現 `.DS_Store`、`._` 或 `.fseventsd` 等檔案。
- 🍎 **原生 Mac App。** 以 Swift 與 SwiftUI 撰寫，支援英文、韓文、日文、中文（簡體與繁體）、德文、法文、西班牙文、葡萄牙文（巴西）及俄文。依 GPLv3 授權，為免費的開放原始碼軟體。

## 📥 下載

從 **[Releases](https://github.com/team-unstablers/SnakeStick/releases/latest)** 標籤頁下載最新版本，然後將 **SnakeStick** 移到 **應用程式** 檔案夾。此 App 已經過 Apple 簽署與公證。

## 🧰 你需要準備的東西

| | |
|---|---|
| **Mac** | macOS Sonoma 14 或以上版本，以及管理者密碼 |
| **Windows ISO** | Windows 10 或 11 安裝 ISO，例如從 Microsoft 的 [Windows 11](https://www.microsoft.com/zh-tw/software-download/windows11) 或 [Windows 10](https://www.microsoft.com/zh-tw/software-download/windows10) 下載頁面取得 |
| **USB 隨身碟** | 容量需足以放下 ISO；容量太小的隨身碟會以灰色顯示。以目前的 Windows 11 ISO 來說，16 GB 就足夠。 |
| **目標 PC** | 以 UEFI 模式開機的 PC。不支援傳統 BIOS（CSM）開機。 |

> [!CAUTION]
> 寫入會**清除所選 USB 隨身碟上的所有內容**。請先將想保留的資料拷貝出來。

## 🔑 權限

SnakeStick 透過 App 內的一個小型工具寫入隨身碟。這個工具只在寫入期間以管理者權限執行，因此 App 本身永遠不需要以 root 身分執行。每次寫入隨身碟時，macOS 都會詢問你的管理者密碼。

**「完全取用磁碟」權限。** 除非 App 擁有「完全取用磁碟」權限，否則 macOS 不允許寫入工具存取可移除式磁碟，以及 **下載項目** 等檔案夾。請在 **系統設定 › 隱私權與安全性 › 完全取用磁碟** 中加入 **SnakeStick**。缺少此權限時 SnakeStick 會提醒你，並提供可直接打開該設定頁面的按鈕。

## 🚀 製作隨身碟

1. **選擇 ISO。** 在 **來源 ISO** 下方按一下 **選擇…**，或將 ISO 拖到視窗上。SnakeStick 會顯示 Windows 版本、架構與大小。
2. **選擇隨身碟。** 插入隨身碟，然後在 **目標磁碟** 下方選取它。
3. **檢查選項。**
   - **卷宗標籤**：隨身碟的名稱。預設為 ISO 本身的標籤。
   - **寫入後驗證**：預設為開啟。會多花幾分鐘，但很值得。
   - **使用 Windows UEFI CA 2023 簽署的開機載入程式**：只有已撤銷 Microsoft 2011 Secure Boot 憑證的 PC 才需要，而且只能搭配 Windows 11 25H2 或以上版本的 ISO 使用。若不確定，請保持關閉。
4. 按下 **開始寫入**，以 **清除並寫入** 確認，然後輸入管理者密碼。
5. **等待。** 進度列會顯示目前的步驟（共 8 步）與剩餘時間。在我們測試的 USB 3 隨身碟上，8.7 GB 的 Windows 11 ISO 含驗證約花了 16 分鐘。
6. SnakeStick 顯示完成後，將隨身碟**退出**。

你可以隨時按 **停止**。停止後隨身碟將無法開機，再次寫入時會從頭開始。

## 💻 從隨身碟啟動 PC

1. 將隨身碟插入 PC，按住開機選單鍵並開啟電源。通常是 **F12**、**F11**、**F8** 或 **Esc**；請參閱 PC 的使用手冊。
2. 選擇該 USB 隨身碟的 **UEFI** 項目。
3. Windows 安裝程式隨即啟動。

如果在開啟 Secure Boot 的狀態下，PC 拒絕從隨身碟啟動，請在韌體設定中尋找類似 **「Allow Microsoft 3rd Party UEFI CA」** 的選項並將它開啟。有些 PC（特別是 Secured-core PC）出廠時會將它關閉，而 UEFI:NTFS 開機載入程式需要這個選項。也可以在安裝期間暫時關閉 Secure Boot；安裝完成後請記得重新開啟。

## ❓ 常見問題

<details>
<summary><b>為什麼需要「完全取用磁碟」權限？</b></summary>
<br>

SnakeStick 負責寫入隨身碟的部分是 App 內的一個獨立工具，每次寫入時都會以管理者權限啟動。除非這個工具所屬的 App 擁有「完全取用磁碟」權限，否則 macOS 不允許它打開可移除式磁碟，也不允許讀取「下載項目」等檔案夾中的 ISO，而且這個工具也沒有範圍更小的權限可以申請。你只需將權限授予 SnakeStick App，App 內的工具就能取得此權限。

</details>

<details>
<summary><b>為什麼不像「Boot Camp 輔助程式」那樣，直接把隨身碟格式化為 FAT32？</b></summary>
<br>

FAT32 無法存放 4 GB 或更大的檔案，而目前 Windows ISO 內的 `sources/install.wim` 通常都超過這個大小。常見的解決方法是將檔案分割。SnakeStick 則是將它完整地放在 NTFS 分割區，並在旁邊放一個很小的 FAT 分割區來存放 UEFI:NTFS 載入程式，讓 PC 的韌體能夠讀取 NTFS。

</details>

<details>
<summary><b>可以略過 Windows 11 的 TPM 或 Secure Boot 需求嗎？</b></summary>
<br>

不行。SnakeStick 會依原樣拷貝 ISO。它不會繞過硬體需求、不會加入自動安裝用的回應檔案，也不會注入驅動程式。

</details>

<details>
<summary><b>如果中途拔出隨身碟或停止寫入，會發生什麼事？</b></summary>
<br>

SnakeStick 會自行完成清理，隨身碟則會處於無法開機的狀態。重新寫入一次即可恢復正常。Mac 本身的磁碟完全不會受到影響。

</details>

<details>
<summary><b>可以製作磁碟映像檔，而不寫入隨身碟嗎？</b></summary>
<br>

App 無法這樣做。SnakeStick 只會寫入 USB 隨身碟。

</details>

> [!NOTE]
> SnakeStick 還很新。用它製作的隨身碟已在開啟 Secure Boot 的 x64 PC 上成功啟動 Windows 安裝程式，但尚未測試過以它完整安裝 Windows。如果遇到問題，請 [提交 issue](https://github.com/team-unstablers/SnakeStick/issues) 並附上記錄（App 中的 **顯示記錄…**）。

## 🙏 建構基礎

沒有這些自由軟體，就不會有 SnakeStick。謝謝！

- [ntfs-3g](https://github.com/tuxera/ntfs-3g)：建立並寫入 NTFS 分割區
- [UEFI:NTFS](https://github.com/pbatard/uefi-ntfs)：讓 UEFI 韌體能從 NTFS 啟動 Windows 的開機載入程式
- [wimlib](https://github.com/ebiggers/wimlib)：讀取 Windows 開機映像檔
- [Rufus](https://github.com/pbatard/rufus)：參考了它的原始碼

SnakeStick 是由 LLM 程式設計代理程式在人類監督下撰寫而成。

## 🐍 關於圖像

伊甸園的那條蛇，正把一顆蘋果遞給你的 Mac。蘋果完好無缺：還沒有人咬過一口。

## 🛠️ 開發者資訊

SnakeStick 的運作方式、從原始碼建置以及執行測試的方法，請參閱 [docs/DESIGN.md](docs/DESIGN.md)。

## 📄 授權

SnakeStick 是依 [GNU 通用公共授權條款第 3 版或更新版本](COPYING) 發佈的自由軟體，不提供任何擔保。內附的元件各自沿用其授權條款；請參閱 [docs/DESIGN.md](docs/DESIGN.md#license)。
