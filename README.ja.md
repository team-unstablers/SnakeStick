<p align="center">
  <img src="docs/images/icon.png" width="160" height="160" alt="SnakeStick のアプリアイコン: 赤いリンゴを差し出す蛇の獣人の女性">
</p>

<h1 align="center">SnakeStick</h1>

<p align="center">
  <b>Mac で、起動可能な Windows 10 / 11 のインストール USB メモリを作成できます。</b><br>
  ISO を選び、USB メモリを選び、開始を押すだけ。ターミナルも Boot Camp も、<code>install.wim</code> の分割も必要ありません。
</p>

<p align="center">
  <a href="https://github.com/team-unstablers/SnakeStick/releases/latest"><img alt="最新リリースをダウンロード" src="https://img.shields.io/badge/Download-Latest%20release-B3122E?style=for-the-badge&logo=github&logoColor=white"></a>
  <img alt="macOS 26.6 以降" src="https://img.shields.io/badge/macOS-26.6%2B-0E0B10?style=for-the-badge&logo=apple&logoColor=white">
  <img alt="Windows 10・11" src="https://img.shields.io/badge/Windows-10%20%7C%2011-0E0B10?style=for-the-badge">
  <a href="COPYING"><img alt="ライセンス: GPL-3.0" src="https://img.shields.io/badge/License-GPL--3.0-0E0B10?style=for-the-badge"></a>
</p>

<p align="center">
  <a href="README.md">English</a> · <a href="README.ko.md">한국어</a> · <b>日本語</b> · <a href="README.zh-Hans.md">简体中文</a> · <a href="README.zh-Hant.md">繁體中文</a> · <a href="README.de.md">Deutsch</a> · <a href="README.fr.md">Français</a> · <a href="README.es.md">Español</a> · <a href="README.pt-BR.md">Português (Brasil)</a> · <a href="README.ru.md">Русский</a>
</p>

<p align="center">
  <img src="docs/images/screenshot.png" width="592" alt="Windows 11 の ISO を USB メモリにコピーしている SnakeStick（全 8 ステップ中ステップ 6）">
</p>

---

## ✨ SnakeStick を選ぶ理由

- 🪟 **アプリだけで完結。** Windows 10・11 の ISO を選び（ウインドウにドロップしても構いません）、USB メモリを選んで、**書き込み開始**を押すだけです。
- 📦 **大きなインストールファイルも大丈夫。** 最近の Windows ISO には 4 GB を超える `install.wim` が含まれており、FAT32 の USB メモリには収まりません。SnakeStick は Windows を NTFS パーティションに置き、[UEFI:NTFS](https://github.com/pbatard/uefi-ntfs) ローダを入れた小さなブートパーティションを追加します。[Rufus](https://rufus.ie) と同じ構成です。何も分割しません。
- 🔐 **Secure Boot に対応。** 同梱のブートローダは Microsoft の署名を受けています。Microsoft の 2011 年の証明書を失効させた PC 向けに、Windows 11 25H2 以降の ISO に含まれる Windows UEFI CA 2023 署名のブートローダを使うこともできます。
- ✅ **書き込み結果を自分で確認。** 書き込みが終わると USB メモリ全体を読み戻し、ISO とファイル単位で比較します。
- 🛡️ **Mac のディスクには近づきません。** 一覧に表示されるのは外部ディスクとリムーバブルディスクだけです。内蔵ディスクと起動ディスクは表示されず、書き込み直前に書き込み先をもう一度確認し、あなたが確定するまで何も消去しません。
- 🧹 **Mac のゴミファイルを残しません。** Windows パーティションは一度もマウントせずに書き込むので、`.DS_Store`、`._`、`.fseventsd` といったファイルが USB メモリに残りません。
- 🍎 **ネイティブの Mac アプリ。** Swift と SwiftUI で作られており、日本語、英語、韓国語、中国語（簡体字・繁体字）、ドイツ語、フランス語、スペイン語、ポルトガル語（ブラジル）、ロシア語に対応しています。GPLv3 のもとで公開されている無料のオープンソースソフトウェアです。

## 📥 ダウンロード

**[Releases](https://github.com/team-unstablers/SnakeStick/releases/latest)** タブから最新版をダウンロードし、**SnakeStick** を**アプリケーション**フォルダに移動してください。アプリは Apple による署名と公証を受けています。

## 🧰 必要なもの

| | |
|---|---|
| **Mac** | macOS Tahoe 26.6 以降と、管理者パスワード |
| **Windows ISO** | Windows 10 または 11 のインストール ISO。Microsoft の [Windows 11](https://www.microsoft.com/ja-jp/software-download/windows11)・[Windows 10](https://www.microsoft.com/ja-jp/software-download/windows10) ダウンロードページなどから入手できます。 |
| **USB メモリ** | ISO が収まる容量が必要です。容量が足りない USB メモリはグレー表示になります。現在の Windows 11 ISO なら 16 GB あれば安心です。 |
| **インストール先の PC** | UEFI モードで起動する PC。レガシー BIOS（CSM）での起動には対応していません。 |

> [!CAUTION]
> 書き込むと、選択した USB メモリの**内容はすべて消去されます**。残しておきたいファイルは、先に別の場所へコピーしておいてください。

## 🔑 初回起動時: 一度だけ必要な 2 つの許可

SnakeStick は、管理者権限でバックグラウンド動作する小さなヘルパーを通じて USB メモリに書き込みます。そのため、アプリ本体を root で実行する必要はありません。このヘルパーを macOS で一度だけ許可してください。

1. **ヘルパーを許可する。** 初めて**書き込み開始**を押すと、SnakeStick のヘルパーを許可するよう macOS から求められます。**システム設定 › 一般 › ログイン項目と機能拡張**で **SnakeStick** をオンにしてから、もう一度お試しください。
2. **フルディスクアクセスを許可する。** アプリにフルディスクアクセスがないと、macOS はバックグラウンドのヘルパーがリムーバブルディスクや**ダウンロード**などのフォルダにアクセスすることを禁止します。**システム設定 › プライバシーとセキュリティ › フルディスクアクセス**に **SnakeStick** を追加してください。許可されていない場合は SnakeStick が知らせてくれ、該当する設定画面を開くボタンも表示されます。

以降は、USB メモリに書き込むたびに管理者パスワードを 1 回だけ入力します。

## 🚀 USB メモリを作成する

1. **ISO を選ぶ。** **ソース ISO** の **選択…** をクリックするか、ISO をウインドウにドロップします。Windows のバージョン、アーキテクチャ、サイズが表示されます。
2. **USB メモリを選ぶ。** USB メモリを接続し、**書き込み先ディスク**で選択します。
3. **オプションを確認する。**
   - **ボリュームラベル**: USB メモリの名前です。初期値は ISO 自体のラベルです。
   - **書き込み後に検証**: 初期設定でオンになっています。数分余計にかかりますが、それだけの価値はあります。
   - **Windows UEFI CA 2023 署名のブートローダを使用**: Microsoft の 2011 年の Secure Boot 証明書を失効させた PC でのみ必要で、Windows 11 25H2 以降の ISO でのみ使用できます。よくわからない場合はオフのままにしてください。
4. **書き込み開始**を押し、**消去して書き込む**で確定して、管理者パスワードを入力します。
5. **待つ。** 進行状況バーに現在のステップ（全 8 ステップ）と残り時間が表示されます。テストに使った USB 3 の USB メモリでは、8.7 GB の Windows 11 ISO で検証を含めて約 16 分かかりました。
6. SnakeStick に完了と表示されたら、**取り出す**を押して USB メモリを取り外します。

書き込みはいつでも**中止**できます。中止すると USB メモリは起動できない状態のまま残り、もう一度書き込むときは最初からやり直しになります。

## 💻 PC を USB メモリから起動する

1. USB メモリを PC に挿し、ブートメニューのキーを押しながら電源を入れます。通常は **F12**、**F11**、**F8**、**Esc** のいずれかです。詳しくは PC のマニュアルで確認してください。
2. USB メモリの **UEFI** 項目を選びます。
3. Windows セットアップが始まります。

Secure Boot を有効にした状態で USB メモリから起動できない場合は、ファームウェア設定で **"Allow Microsoft 3rd Party UEFI CA"** のような項目を探してオンにしてください。一部の PC、特に Secured-core PC は出荷時にこの設定がオフになっていますが、UEFI:NTFS ブートローダにはこの設定が必要です。インストールの間だけ Secure Boot をオフにしても構いません。その場合は、インストール後に元に戻してください。

## ❓ よくある質問

<details>
<summary><b>なぜフルディスクアクセスが必要なのですか？</b></summary>
<br>

SnakeStick で USB メモリに書き込む部分は、バックグラウンドのヘルパー（launchd デーモン）です。macOS では、ヘルパーが属するアプリにフルディスクアクセスがないと、ヘルパーはリムーバブルディスクを開くことも、ダウンロードなどのフォルダにある ISO を読み込むこともできません。また、ヘルパーが要求できる、これより範囲の狭い権限はありません。権限は SnakeStick アプリに付与し、それがアプリ内のヘルパーにも適用されます。

</details>

<details>
<summary><b>Boot Camp アシスタントのように、USB メモリを FAT32 でフォーマットするだけではだめなのですか？</b></summary>
<br>

FAT32 には 4 GB 以上のファイルを保存できませんが、現在の Windows ISO に含まれる `sources/install.wim` はたいていそれより大きくなっています。よくある回避策はファイルの分割です。SnakeStick は代わりにファイルを分割せずに NTFS パーティションに置き、その隣の小さな FAT パーティションに UEFI:NTFS ローダを入れます。このローダのおかげで、PC のファームウェアが NTFS を読めるようになります。

</details>

<details>
<summary><b>Windows 11 の TPM や Secure Boot の要件を回避できますか？</b></summary>
<br>

いいえ。SnakeStick は ISO をそのままコピーします。ハードウェア要件の回避、無人インストール用の応答ファイルの追加、ドライバの組み込みは行いません。

</details>

<details>
<summary><b>途中で USB メモリを抜いたり、中止したりするとどうなりますか？</b></summary>
<br>

SnakeStick が後片付けを行い、USB メモリは起動できない状態で残ります。もう一度書き込めば問題ありません。Mac 本体のディスクには一切触れません。

</details>

<details>
<summary><b>USB メモリに書き込む代わりに、ディスクイメージを作成できますか？</b></summary>
<br>

アプリからはできません。SnakeStick は USB メモリにのみ書き込みます。

</details>

> [!NOTE]
> SnakeStick はまだ新しいソフトウェアです。SnakeStick で作った USB メモリで、Secure Boot を有効にした x64 PC が Windows セットアップまで起動することは確認していますが、その USB メモリを使って Windows のインストールを最後まで行うテストはまだ済んでいません。問題が起きた場合は [Issue を作成](https://github.com/team-unstablers/SnakeStick/issues)し、ログ（アプリの **ログを表示…**）を添付してください。

## 🙏 SnakeStick を支えるソフトウェア

SnakeStick は、以下のフリーソフトウェアなしには実現しませんでした。ありがとうございます！

- [ntfs-3g](https://github.com/tuxera/ntfs-3g): NTFS パーティションを作成し、書き込みます
- [UEFI:NTFS](https://github.com/pbatard/uefi-ntfs): UEFI ファームウェアが NTFS から Windows を起動できるようにするブートローダ
- [wimlib](https://github.com/ebiggers/wimlib): Windows のブートイメージを読み込みます
- [Rufus](https://github.com/pbatard/rufus): ソースコードを参考にしました

SnakeStick は、人間の監督のもとで LLM ベースのコーディングエージェントが作成しました。

## 🐍 アイコンについて

エデンの蛇が、あなたの Mac にリンゴを差し出しています。リンゴはまだ欠けていません。誰もひと口もかじっていないのです。

## 🛠️ 開発者向け

SnakeStick の仕組み、ソースからのビルド方法、テストの実行方法については [docs/DESIGN.md](docs/DESIGN.md)（英語）を参照してください。

## 📄 ライセンス

SnakeStick は [GNU General Public License v3.0 以降](COPYING)で配布されるフリーソフトウェアで、一切の保証はありません。同梱のコンポーネントはそれぞれのライセンスに従います。[docs/DESIGN.md](docs/DESIGN.md#license) を参照してください。
