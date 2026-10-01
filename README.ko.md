<p align="center">
  <img src="docs/images/icon.png" width="160" height="160" alt="SnakeStick 앱 아이콘: 빨간 사과를 내민 뱀 수인 여성">
</p>

<h1 align="center">SnakeStick</h1>

<p align="center">
  <b>Mac에서 Windows 10 / 11 설치 USB를 만드세요.</b><br>
  ISO를 고르고, 스틱을 고르고, 시작을 누르면 끝. 터미널도, Boot Camp도, <code>install.wim</code> 분할도 필요 없습니다.
</p>

<p align="center">
  <a href="https://github.com/team-unstablers/SnakeStick/releases/latest"><img alt="최신 릴리스 다운로드" src="https://img.shields.io/badge/Download-Latest%20release-B3122E?style=for-the-badge&logo=github&logoColor=white"></a>
  <img alt="macOS 14 이상" src="https://img.shields.io/badge/macOS-14%2B-0E0B10?style=for-the-badge&logo=apple&logoColor=white">
  <img alt="Windows 10, 11" src="https://img.shields.io/badge/Windows-10%20%7C%2011-0E0B10?style=for-the-badge">
  <a href="COPYING"><img alt="라이선스: GPL-3.0" src="https://img.shields.io/badge/License-GPL--3.0-0E0B10?style=for-the-badge"></a>
</p>

<p align="center">
  <a href="README.md">English</a> · <b>한국어</b> · <a href="README.ja.md">日本語</a> · <a href="README.zh-Hans.md">简体中文</a> · <a href="README.zh-Hant.md">繁體中文</a> · <a href="README.de.md">Deutsch</a> · <a href="README.fr.md">Français</a> · <a href="README.es.md">Español</a> · <a href="README.pt-BR.md">Português (Brasil)</a> · <a href="README.ru.md">Русский</a>
</p>

<p align="center">
  <img src="docs/images/screenshot.png" width="592" alt="SnakeStick이 Windows 11 ISO를 USB 스틱에 복사하는 중 (8단계 중 6단계)">
</p>

---

## ✨ SnakeStick을 쓰는 이유

- 🪟 **앱 하나면 됩니다.** Windows 10·11 ISO를 고르고(창에 끌어다 놓아도 됩니다), USB 스틱을 고르고, **쓰기 시작**을 누르세요.
- 📦 **큰 설치 파일도 문제없습니다.** 요즘 Windows ISO의 `install.wim`은 4GB가 넘어서 FAT32 스틱에는 들어가지 않습니다.
  SnakeStick은 Windows를 NTFS 파티션에 넣고, [UEFI:NTFS](https://github.com/pbatard/uefi-ntfs) 부트로더가 든 작은 부트
  파티션을 옆에 둡니다. [Rufus](https://rufus.ie)와 같은 구성입니다. 아무것도 쪼개지 않습니다.
- 🔐 **Secure Boot를 켠 채로 부팅됩니다.** 함께 들어가는 부트로더는 Microsoft 서명을 받았습니다. Microsoft 2011 인증서를
  폐기한 PC를 위해, Windows 11 25H2 이상 ISO에 든 Windows UEFI CA 2023 서명 부트로더를 쓸 수도 있습니다.
- ✅ **쓴 내용을 스스로 확인합니다.** 기록을 마치면 스틱 전체를 다시 읽어 ISO와 파일 단위로 비교합니다.
- 🛡️ **Mac의 디스크는 건드리지 않습니다.** 외장·이동식 디스크만 목록에 나옵니다. 내장 디스크와 시동 디스크는 아예 보이지
  않고, 쓰기 직전에 대상을 한 번 더 확인하며, 직접 확인하기 전에는 아무것도 지우지 않습니다.
- 🧹 **Mac 부스러기가 남지 않습니다.** Windows 파티션은 마운트하지 않고 쓰기 때문에 `.DS_Store`, `._`, `.fseventsd` 같은
  파일이 스틱에 생기지 않습니다.
- 🍎 **Mac 네이티브 앱입니다.** Swift와 SwiftUI로 만들었고 한국어, 영어, 일본어, 중국어(간체·번체), 독일어,
  프랑스어, 스페인어, 포르투갈어(브라질), 러시아어를 지원합니다. GPLv3 자유 소프트웨어입니다.

## 📥 다운로드

**[Releases](https://github.com/team-unstablers/SnakeStick/releases/latest)** 탭에서 최신 버전을 받은 뒤, **SnakeStick**을
**응용 프로그램** 폴더로 옮기세요. 앱은 Apple의 서명과 공증을 받았습니다.

## 🧰 준비물

| | |
|---|---|
| **Mac** | macOS Sonoma 14 이상, 관리자 암호 |
| **Windows ISO** | Windows 10 또는 11 설치 ISO. Microsoft의 [Windows 11](https://www.microsoft.com/ko-kr/software-download/windows11)·[Windows 10](https://www.microsoft.com/ko-kr/software-download/windows10) 다운로드 페이지에서 받을 수 있습니다. |
| **USB 스틱** | ISO가 들어갈 만큼 커야 합니다. 너무 작은 스틱은 흐리게 표시됩니다. 요즘 Windows 11 ISO라면 16GB가 넉넉합니다. |
| **설치할 PC** | UEFI 모드로 부팅하는 PC. 레거시 BIOS(CSM) 부팅은 지원하지 않습니다. |

> [!CAUTION]
> 쓰기를 시작하면 선택한 USB 스틱의 **모든 내용이 지워집니다.** 남겨야 할 파일은 먼저 옮겨 두세요.

## 🔑 권한

SnakeStick은 앱 안에 든 작은 도구로 스틱을 씁니다. 이 도구는 쓰는 동안에만 관리자 권한으로 실행되므로, 앱 자체는 root로
실행될 일이 없습니다. 스틱을 쓸 때마다 macOS가 관리자 암호를 묻습니다.

**전체 디스크 접근 권한.** 앱에 전체 디스크 접근 권한이 없으면 macOS는 쓰기 도구가 이동식 디스크나 **다운로드** 같은
폴더에 접근하지 못하게 막습니다. **시스템 설정 › 개인정보 보호 및 보안 › 전체 디스크 접근 권한**에 **SnakeStick**을
추가하세요. 권한이 없으면 SnakeStick이 알려 주고, 해당 설정 화면을 여는 버튼도 보여 줍니다.

## 🚀 설치 USB 만들기

1. **ISO 고르기.** **원본 ISO**의 **선택…**을 누르거나 ISO를 창에 끌어다 놓으세요. Windows 버전, 아키텍처, 크기가 표시됩니다.
2. **스틱 고르기.** 스틱을 꽂고 **대상 디스크**에서 고르세요.
3. **옵션 확인.**
   - **볼륨 레이블**: 스틱의 이름입니다. 기본값은 ISO의 레이블입니다.
   - **쓰기 후 내용 검증**: 기본으로 켜져 있습니다. 몇 분 더 걸리지만 그만한 가치가 있습니다.
   - **Windows UEFI CA 2023 서명 부트로더 사용**: Microsoft의 2011 Secure Boot 인증서를 폐기한 PC에서만 필요하고,
     Windows 11 25H2 이상 ISO에서만 켤 수 있습니다. 잘 모르겠다면 꺼 두세요.
4. **쓰기 시작**을 누르고 **지우고 쓰기**로 확인한 뒤 관리자 암호를 입력하세요.
5. **기다리기.** 진행 막대에 현재 단계(전체 8단계)와 남은 시간이 표시됩니다. 테스트에 쓴 USB 3 스틱에서는 8.7GB짜리
   Windows 11 ISO가 검증까지 약 16분 걸렸습니다.
6. 완료되면 **추출**을 눌러 스틱을 빼세요.

언제든 **중단**할 수 있습니다. 중단하면 스틱은 부팅할 수 없는 상태로 남고, 다시 쓸 때는 처음부터 시작합니다.

## 💻 PC에서 스틱으로 부팅하기

1. 스틱을 PC에 꽂고, 부팅 메뉴 키를 누른 채로 전원을 켜세요. 보통 **F12**, **F11**, **F8**, **Esc** 중 하나입니다.
   정확한 키는 PC 설명서를 확인하세요.
2. USB 스틱의 **UEFI** 항목을 고르세요.
3. Windows 설치 화면이 시작됩니다.

Secure Boot를 켠 상태에서 스틱으로 부팅이 안 된다면, 펌웨어 설정에서 **"Allow Microsoft 3rd Party UEFI CA"** 같은
항목을 찾아 켜세요. 일부 PC, 특히 Secured-core PC는 이 항목이 꺼진 채로 출고되는데, UEFI:NTFS 부트로더에는 이 설정이
필요합니다. 설치하는 동안만 Secure Boot를 꺼도 됩니다. 설치가 끝나면 다시 켜 두세요.

## ❓ 자주 묻는 질문

<details>
<summary><b>전체 디스크 접근 권한은 왜 필요한가요?</b></summary>
<br>

SnakeStick에서 스틱을 실제로 쓰는 부분은 앱 안에 든 별도의 도구이고, 쓸 때마다 관리자 권한으로 실행됩니다. macOS는 이
도구가 속한 앱에 전체 디스크 접근 권한이 없으면, 도구가 이동식 디스크를 열거나 다운로드 같은 폴더의 ISO를 읽지 못하게
합니다. 도구가 요청할 수 있는 더 좁은 권한은 없습니다. 권한은 SnakeStick 앱에 주는 것이고, 앱 안에 든 도구에까지
적용됩니다.

</details>

<details>
<summary><b>Boot Camp 지원 앱처럼 그냥 FAT32로 포맷하면 안 되나요?</b></summary>
<br>

FAT32에는 4GB 이상인 파일을 넣을 수 없는데, 요즘 Windows ISO의 `sources/install.wim`은 대개 그보다 큽니다. 흔한
해결책은 파일을 쪼개는 것입니다. SnakeStick은 대신 파일을 그대로 NTFS 파티션에 넣고, 옆의 작은 FAT 파티션에
UEFI:NTFS 부트로더를 둡니다. 이 부트로더가 PC 펌웨어가 NTFS를 읽을 수 있게 해 줍니다.

</details>

<details>
<summary><b>Windows 11의 TPM이나 Secure Boot 요구사항을 우회할 수 있나요?</b></summary>
<br>

아니요. SnakeStick은 ISO를 있는 그대로 복사합니다. 하드웨어 요구사항 우회, 무인 설치 응답 파일 추가, 드라이버 주입은
하지 않습니다.

</details>

<details>
<summary><b>쓰는 도중에 스틱을 뽑거나 중단하면 어떻게 되나요?</b></summary>
<br>

SnakeStick이 뒷정리를 하고, 스틱은 부팅할 수 없는 상태로 남습니다. 다시 쓰면 괜찮습니다. Mac의 디스크는 건드리지
않습니다.

</details>

<details>
<summary><b>스틱 대신 디스크 이미지로 만들 수 있나요?</b></summary>
<br>

앱에서는 안 됩니다. SnakeStick 앱은 USB 스틱에만 씁니다.

</details>

> [!NOTE]
> SnakeStick은 아직 초기 버전입니다. SnakeStick으로 만든 스틱이 Secure Boot를 켠 x64 PC에서 Windows 설치 화면까지
> 부팅되는 것은 확인했지만, 그 스틱으로 Windows를 끝까지 설치해 보지는 않았습니다. 문제가 생기면
> [이슈](https://github.com/team-unstablers/SnakeStick/issues)를 열고 로그(앱의 **로그 보기…**)를 첨부해 주세요.

## 🙏 이런 소프트웨어 위에 만들었습니다

아래 자유 소프트웨어 덕분에 SnakeStick을 만들 수 있었습니다. 감사합니다!

- [ntfs-3g](https://github.com/tuxera/ntfs-3g): NTFS 파티션을 만들고 씁니다
- [UEFI:NTFS](https://github.com/pbatard/uefi-ntfs): UEFI 펌웨어가 NTFS에서 Windows를 시작할 수 있게 하는 부트로더
- [wimlib](https://github.com/ebiggers/wimlib): Windows 부트 이미지를 읽습니다
- [Rufus](https://github.com/pbatard/rufus): 소스 코드를 참고했습니다

SnakeStick은 사람의 감독 하에 LLM 기반 코딩 에이전트가 작성했습니다.

## 🐍 아이콘 이야기

에덴의 뱀이 Mac에게 사과를 내밀고 있습니다. 사과는 아직 온전합니다. 아무도 한 입 베어 물지 않았거든요.

## 🛠️ 개발자라면

SnakeStick의 작동 원리, 소스에서 빌드하는 방법, 테스트는 [docs/DESIGN.md](docs/DESIGN.md)(영문)에 있습니다.

## 📄 라이선스

SnakeStick은 [GNU General Public License v3.0 이상](COPYING)으로 배포되는 자유 소프트웨어이며, 어떠한 보증도 제공하지
않습니다. 함께 들어가는 구성 요소는 각자의 라이선스를 따릅니다. [docs/DESIGN.md](docs/DESIGN.md#license)를 보세요.
