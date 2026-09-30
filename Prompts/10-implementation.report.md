# 10-implementation 보고서

`Prompts/10-implementation.xml`(SnakeStickCore, CLI, 헬퍼 데몬, GUI)의 실행 결과다. 작업일 2026-09-30, 머신은 macOS 26 (Darwin 25.6.0, arm64), Apple Swift 6.4, Xcode 27.0 (27A266a).

## 요약

- `SnakeStickCore/` 패키지(라이브러리 + `snakestick` CLI), Xcode 앱 `SnakeStick`(GUI, About 창), 헬퍼 데몬 `SnakeStickHelper`(SMAppService + Swift XPC), 테스트, README·CLAUDE.md를 만들었다.
- 선행 조건 보고서 셋(`slopdisk/Prompts/20-raw-device.report.md`, `WIMLib/Prompts/10-swift-api.report.md`, `NTFS3G/Prompts/20-remove.report.md`)이 있음을 확인하고 시작했다.
- 실제 USB 스틱(Sandisk 3.2Gen1, 61,964,550,144 B)에 `sudo snakestick make`로 실제 Windows 11 ISO(`Windows11_Client_x64_ko-kr_26300_9457.iso`, 8.74 GB)를 썼고, 검증까지 통과했다(16분 13초). 사용자가 그 스틱으로 **x64 실물 PC에서 Secure Boot를 켠 채 Windows 설치 프로그램 첫 화면까지 부팅**했다.
- 실기에서 지시서의 전제 여섯 개가 어긋났다. U11(raw 슬라이스), FAT 배치 ensure의 자기모순, P6의 버전 원본, P10의 인증 흐름, 데몬의 TCC 제약(두 번), `Progress` 이름 충돌이다. 모두 멈추고 사용자에게 물어 정했다(아래 "플래너 결정과 다르게 한 것").
- GUI → 헬퍼 경로로 쓰기가 6단계(복사)까지 진행되는 것은 확인했다. 끝까지 쓰는 것은 확인하지 못했다. 사용자가 앱을 다시 띄워 연결이 끊겼고, 데몬은 설계대로 작업을 취소했다.

## 확인한 것

따로 적지 않으면 저장소 루트에서 실행했다.

### 빌드·테스트

| 명령 | 결과 |
|---|---|
| `cd SnakeStickCore && swift package clean && swift build` | `Build complete!`. 경고 281줄은 모두 서브모듈 C 코드(`Vendor/`)에서 나왔다. `SnakeStickCore/Sources`·`Tests`의 경고는 0개. |
| `cd SnakeStickCore && swift test` (마지막 실행: 전체 디스크 접근 변경 뒤, 커밋 5528ecc와 같은 소스) | `Test run with 81 tests in 17 suites passed`. 통합 스위트는 skip. |
| `cd SnakeStickCore && SNAKESTICK_TEST_INTEGRATION=1 swift test` | 커밋 5d8b9af 시점에 `Test run with 81 tests in 17 suites passed`(32초). 실행 전후 `hdiutil info \| grep -c image-path` 8 → 8, `/tmp/snakestick-*` 0 → 0. 커밋 b8d4285 시점(준비된 ISO 테스트 2개 추가)에도 83개 통과, 8 → 8. |
| `swift run snakestick info <test.iso>` (스크래치 픽스처, 레이블 SNAKETEST, 빌드 26200) | exit 0. "SNAKETEST", "26200", "x64", "CA 2023 boot loaders available". |
| `swift run snakestick build -o /tmp/snaketest.img <test.iso>` | exit 0, "The written data matches the ISO." `ls -l` 42,991,616 B, `du -k` 33,056 KB(sparse 유지). 확인 후 삭제. |
| `swift run snakestick make <test.iso> disk0` (비root) | exit 77, "needs root. Run it with sudo". 아무것도 열지 않는다(root 검사가 ISO 검사보다 먼저다). |
| `xcodebuild -workspace SnakeStick.xcworkspace -scheme SnakeStick -configuration Debug build` | `** BUILD SUCCEEDED **`. 앱·헬퍼 소스의 경고 0개. 번들에 `Contents/MacOS/SnakeStickHelper`, `Contents/Library/LaunchDaemons/pl.unstabler.aislop.SnakeStick.helper.plist`, `Contents/Resources/SnakeStickCore_SnakeStickCore.bundle`, `COPYING`, `ko.lproj`가 있다. |
| `codesign -d --entitlements - SnakeStick.app` | `com.apple.security.get-task-allow`(디버그)만 있다. 샌드박스 entitlement 없음. 앱·헬퍼 모두 `flags=0x10000(runtime)`, TeamIdentifier `XHA76UVA95`. |
| `grep -rn "dataLossRisk" SnakeStickCore/Sources` | `Pipeline/Partitioning.swift:34` 한 곳(`writePartitionTable`). |
| String Catalog 대조 (빌드의 `.stringsdata` 키 vs `Localizable.xcstrings`) | 코드가 쓰는 키와 카탈로그 키가 정확히 일치하고, 번역이 필요한 키는 모두 `ko`가 있다. |

### 앱 화면 (눈으로 확인)

- `open -a SnakeStick.app test.iso`(`onOpenURL`)로 ISO를 넘기고 창을 캡처했다. ISO 행에 `test.iso`와 "Windows 11 25H2 · x64 · 31.2MB", 볼륨 레이블 "SNAKETEST", CA 2023 옵션의 활성 설명, 상태 "ISO 파일과 대상 디스크를 선택하세요"가 나왔다. 배치·문구는 Figma 02와 같다.
- 디스크를 골라 02(필요 공간 표시)로 넘어가는 것은 캡처하지 않았다. 그때 대상 USB에 CLI 쓰기가 진행 중이었다. 대상 메뉴 항목은 `listDiskCandidates()`에서 오고, 이 머신에서 `snakestick disks`는 내장 SSD(disk0, 시동 디스크), APFS 합성 디스크, 디스크 이미지 15개를 모두 "Not offered"로 분류하고 USB 스틱만 후보로 냈다.
- About 창(Figma 08)을 앱 메뉴로 열어 캡처했다. 아이콘·버전·고지·크레딧 4개·버튼·저작권이 시안과 같다. "라이선스 전문…" 시트는 UI 스크립팅으로 버튼을 누르지 못해 열어 보지 않았다(번들에 `COPYING`이 있음은 확인).

### 실제 USB (사용자가 `sudo`로 실행)

1. 대상 식별: 꽂기 전후 `/dev/disk*` 목록 차이에서 disk7 하나만 나왔고, 모델·크기·프로토콜을 보여 사용자 확인을 받았다. 스크립트는 실행 때마다 `MediaName`·`TotalSize`·`BusProtocol`·`Internal`을 다시 대조했다.
2. 스크래치 프로브(`usb-probe.sh`, 이 저장소 밖):
   - SlopDisk 커밋 뒤 슬라이스 노드가 약 0.1초 안에 생겼다. GPT를 쓴 뒤·NTFS 포맷 뒤·`newfs_msdos` 뒤에 자동 마운트가 없었다(마운트 가드 없이 3~5초 관찰).
   - `dd` 1.5 GB 순차 쓰기(`/dev/rdisk7s1`, bs=8m)는 22.5 MB/s.
   - raw `/dev/rdisk7s1`의 mkntfs는 `Error writing to /dev/rdisk7s1: Invalid argument`로 실패했다(U11).
   - 버퍼드 `/dev/disk7s1`에서는 포맷이 5.7초 걸렸고, `copyTree` 1.62 GB가 12.9 MB/s(작은 파일 구간 6 MB/s, 큰 파일 구간 약 16 MB/s)로 끝났다. NTFS3G 읽기는 65 MB/s였다. NTFS3G 읽기 전용 열기도 raw에서는 `$Bitmap` 읽기가 EINVAL이었다.
   - FSKit 읽기 전용 마운트가 되고 `install.wim`이 `cmp`로 일치했다.
   - 1 MiB `newfs_msdos`는 FAT12, 2003 클러스터, 여유 1001 KiB였고 `fsck_msdos -n`이 깨끗했다.
3. `sudo snakestick make --verbose Windows11_Client_x64_ko-kr_26300_9457.iso disk7`: 파일 1,065개·디렉터리 102개·8,738,709,179 B를 복사했고, NTFS 전체 비교와 FAT 해시 검증을 통과했다. 16분 13초 걸렸다. 마운트 가드는 FAT 마운트 두 번만 허용하고 나머지는 거부 0건이었다. `.fseventsd`가 생겼다가 언마운트 전에 지워졌다. 정리 후 attach와 작업 디렉터리가 남지 않았다.
4. 사용자 보고: 그 스틱으로 x64 실물 PC에서 Secure Boot를 켠 채 부팅해 Windows 설치 프로그램 첫 화면까지 갔다.
5. 앱 → 헬퍼(unified log로 확인):
   - DerivedData 개발 빌드에서 SMAppService 등록 → 로그인 항목 승인 → launchd가 헬퍼를 root로 띄웠다(`Successfully spawned SnakeStickHelper because ipc (mach)`, `uid 0`).
   - `XPCListener(service:requirement:)` 리스너가 앱 세션을 받아 응답했다.
   - 권한 부여와 TCC 문제를 해결한 뒤(아래) 전체 디스크 접근을 앱에 주자 1~5단계를 지나 6단계(복사)까지 진행했다. 5단계 중 이전 FAT가 남은 disk7s2에 대한 자동 마운트를 가드가 거부했다(`mount guard: refused a mount of disk7s2`).
   - 그 뒤 앱이 다시 띄워지면서 연결이 끊겼고, 데몬은 작업을 취소하고 정리한 뒤 종료했다(`the app disconnected; cancelling its job`).

## 확인하지 못한 것 (`<unverified>`)

| 항목 | 결과 |
|---|---|
| U1 Touch ID | 확인하지 못함. 인증 다이얼로그가 뜨는 것은 로그로 확인했지만(사용자가 두 번 취소), Touch ID 옵션이 보였는지는 확인하지 못했다. |
| U2 개발 빌드의 SMAppService | 확인. DerivedData 경로에서 등록·승인·실행이 됐다. 다시 빌드한 뒤 재등록 없이 새 바이너리가 떴다("version 1.0 (1), protocol 2"). |
| U3 unix_io on `/dev/rdiskNs1` | 실패 확인(hdiutil 디바이스와 실제 USB 모두 EINVAL). 결정 14의 폴백 중 버퍼드 `/dev/diskNs1`을 사용자가 골랐다. |
| U4 `O_EXCL`·`fcntl` 잠금 | 문자 디바이스 열기와 버퍼드 블록 디바이스 열기 모두 오류 없이 통과했다(실패는 이후의 쓰기에서 났다). |
| U5 실제 USB의 슬라이스·자동 마운트 | 슬라이스 약 0.1초. 가드 없는 프로브에서 자동 마운트 없음. GUI 실행에서 가드가 s2 마운트 시도를 거부함. |
| U6 USB 처리량 | 버퍼드 `copyTree` 12.9 MB/s, raw 순차 22.5 MB/s. 8.74 GB ISO의 전체 작업이 16분 13초. |
| U7 Rufus의 UEFI:NTFS GPT 타입 GUID | 확인하지 않았다(`src/drive.c`를 읽지 않음). 구현에는 영향이 없다. |
| U8 1 MiB FAT | 확인. FAT12, 여유 1001 KiB, 네 파일(417,472 B)이 들어가고 해시가 일치한다. |
| U9 macOS 메타데이터 | 쓰기 마운트에서 `.fseventsd`가 생겼고, 지운 뒤 읽기 전용으로 다시 열었을 때 없었다(통합 테스트·실제 USB 모두). `.Spotlight-V100`·`.Trashes`는 관찰되지 않았다. |
| U10 sparse | 유지된다. 83,886,080 B 이미지가 7,077,888 B를 차지했다(통합 테스트). CLI `build`는 42,991,616 B / 33,056 KB. |
| U11 mkntfs `-F`와 크기, FSKit | raw 슬라이스에서는 실패. 버퍼드 슬라이스에서는 크기(61,961,400,320 B = 파티션 크기)를 올바르게 읽었고, FSKit 읽기 전용 마운트와 파일 일치를 확인했다. |
| U12 실제 부팅 | 부분 확인. x64 PC, Secure Boot 켬, Windows 설치 프로그램 첫 화면까지(사용자 보고). 설치 완료·`chkdsk`·ARM64 PC·CA 2023 옵션으로 만든 스틱의 부팅은 확인하지 않았다. |
| U13 `makehybrid -udf -iso` | 확인. 한글 이름·빈 파일·빈 디렉터리를 포함한 트리가 attach 뒤 그대로다(`makehybridPreservesTheTree`). |
| U14 Swift XPC의 MachServices·피어 요구 | 확인. macOS 26 SDK의 `XPCListener(service:requirement:)`와 `XPCPeerRequirement.isFromSameTeam(andMatchesSigningIdentifier:)`로 됐다. P9의 `NSXPCConnection` 폴백은 필요 없었다. |

그 밖에 확인하지 못한 것:

- 마지막 revert(ebbded5)와 전체 디스크 접근 안내(5528ecc) 뒤에 통합 스위트를 다시 돌리지 못했다(사용자가 여기서 마무리를 요청). 파이프라인 코드는 통합 스위트가 81개 모두 통과한 5d8b9af와 같고, 이후 바뀐 것은 `HelperProtocol.swift`와 앱·헬퍼 코드다. 단위 테스트 81개와 앱 빌드는 그 뒤에 통과했다.
- GUI로 끝까지 쓰는 것, 06 완료·07 오류·05 취소 시트의 실기 화면, "추출".
- 4Kn 디바이스, x86_64 빌드, Release 구성의 Xcode 빌드.

## ensure·§15 항목별

| 항목 | 테스트 | 결과 |
|---|---|---|
| inspectISO: 테스트 ISO → "SNAKETEST", 26200, x64, CA 2023 | `IntegrationTests.InspectISO.fixtureISO` | 통과 |
| inspectISO: 빈 파일 → "not a Windows ISO" | `InspectISOErrorTests.emptyFileIsNotAWindowsISO` | 통과 |
| listDiskCandidates: 시동 디스크 없음 | `LiveDiskTests.candidatesNeverIncludeTheStartupDisk` | 통과 |
| classify(description:)가 내장·시동·이미지 디스크를 거름 | `DiskClassificationTests` (11개, 실제 DA 덤프로 만든 픽스처) | 통과 |
| runInstaller `.image` 끝까지, GPT healthy·NTFS 트리·FAT 네 파일 | `IntegrationTests.Pipeline.buildsAnImage` | 통과 |
| copyTree 중 취소 → CancellationError, 마운트·attach 없음 | `…Pipeline.cancelDuringCopy` | 통과 |
| code#partition: 64 MiB에서 ntfs 0/2048, fat 1, fat.end 131038, fat 1 MiB, `gpt -r show` 일치 | `…Pipeline.partitionLayoutOn64MiB` | 통과(fat.begin은 정렬 대신 끝에 붙인 값, 아래 2) |
| code#partition: fat.end == LastUsableLBA | 같은 테스트 | 통과 |
| code#partition: "2 MiB + GPT"보다 작으면 트랜잭션 전 오류 | `…Pipeline.tooSmallDeviceIsRejectedBeforeTheTransaction` (이미지 바이트가 전부 0) | 통과 |
| §15 항상: classify, 빌드 → 이름 표, SI 파싱, requiredBytes, CLI 파싱·64, 로더 SHA-256, PVD | `DiskClassificationTests`, `WindowsVersionTests`, `SISizeTests`, `ArgumentTests`, `PayloadTests`, `PrimaryVolumeDescriptorTests` | 통과 |
| §15 (a) 픽스처 ISO | `FixtureISO.make` (boot.wim 이미지 2개, `WIMFile.create(images:)`) | 사용됨 |
| §15 (b) | 위 inspectISO | 통과 |
| §15 (c) | `buildsAnImage` (NTFS는 버퍼드 슬라이스로 읽음, 아래 1) | 통과 |
| §15 (d) | `cancelDuringCopy` | 통과 |
| §15 (e) CA 2023 | `…Pipeline.replacesBootLoadersWithCA2023Ones` (bootx64·bootmgr·폰트 교체, 없는 폰트는 새로 씀) + `ca2023NeedsLoadersInBootWIM`, `ca2023NeedsBuild26200` | 통과 |
| §15 (f) CLI | `IntegrationTests.CommandLine` (build → 이미지 검사, `--imgsize 1M` → 64, 비root make → 77, info·disks → 0) | 통과 |
| install 이미지 우선(아래 4) | `…InspectISO.installImageDecidesTheRelease` | 통과 |

## 플래너 결정과 다르게 한 것

사용자에게 물어 정한 것:

1. **U11 폴백(결정 14): NTFS3G에는 버퍼드 `/dev/diskNs1`을 준다.** SlopDisk와 `newfs_msdos`는 raw를 그대로 쓴다(C8). 코드 주석과 README KNOWN LIMITATIONS에 타협으로 적었다.
2. **FAT 배치.** `code#partition`의 ensure(시작 1 MiB 정렬 + 크기 1 MiB + `fat.end == LastUsableLBA`)와 `code#layout`이 서로 모순이었다. 사용자가 "끝에 붙이고 정확히 1 MiB"를 골랐다(결정 2·23 우선). 그래서 FAT 시작은 정렬되지 않는다.
3. **`Progress` → `InstallerProgress`.** Foundation의 `Progress`와 이름이 충돌했다.
4. **P6·P7의 버전 원본.** 실제 ISO에서 boot.wim은 26100, install.wim은 26300이었다. Rufus(`PopulateWindowsVersion`)처럼 `install.wim`/`install.esd`/`install.swm` 이미지 1을 읽고, 없으면 boot.wim 이미지 2로 폴백한다. CA 2023 추출은 boot.wim 이미지 2 그대로다.
5. **P10 인증 흐름.** `authenticate-admin` 규칙이 `timeout 0`이라 앱이 받은 자격을 데몬이 재사용할 수 없었다. Apple 샘플 방식으로 바꿨다. 앱은 빈 AuthorizationRef를 넘기고, 데몬이 `interactionAllowed`로 right를 얻으며, 다이얼로그는 사용자 세션에 뜬다. `HelperRequest.start`에 `prompt`가 추가됐고 프로토콜 버전이 2가 됐다.
6. **데몬의 TCC.** root 데몬도 `~/Downloads`(파일 읽기)와 이동식 디스크 raw 디바이스(`kTCCServiceSystemPolicyRemovableVolumes`)에 접근하지 못했다. 앱이 ISO를 붙여 넘기는 방식(b8d4285)을 구현했다가, 디스크 접근도 막히는 것을 보고 사용자가 되돌리고(ebbded5) **전체 디스크 접근 권한**으로 정했다. 앱에 주면 번들 안의 데몬에도 적용된다(tccd 로그로 확인). 데몬은 관리자 인증 전에 `TCC.db` 열기로 권한을 확인하고, 없으면 `fullDiskAccessRequired`로 거절한다. 그러면 앱이 안내 시트와 설정 열기 버튼을 보여 준다.
7. SPDX `GPL-3.0-or-later` 헤더, 루트 `COPYING`(GPLv3 원문, gnu.org, SHA-256 `3972dc97…`). 루트 `COPYING`은 `<acceptance>`의 커밋 경로 목록 밖이지만 사용자가 골랐다.
8. **About 창**(Figma 08, 지시서에 없던 요청). 소스 URL `https://github.com/team-unstablers/SnakeStick`, 저작권 "© 2026 team unstablers Inc."(`NSHumanReadableCopyright`).

실행자가 정한 것:

- 데몬이 버전을 "? (?)"로 보고하는 버그가 있었다(`argv[0]`으로 Info.plist를 읽음). 앱은 불일치 때마다 unregister/register를 했고, 이게 막 뜬 데몬을 bootout시켰다. 데몬은 `_NSGetExecutablePath`로 버전을 읽게 했다. 불일치면 앱이 세션을 끊고 다시 확인하고, 데몬은 연결과 작업이 없으면 종료한다. 재등록은 조회가 실패할 때만 한 번 한다.
- 데몬은 앱 연결이 끊기면 작업을 취소한다. 앱 세션마다 코드서명 피어 요구를 양방향으로 건다(`isFromSameTeam` + 상대 식별자).
- Xcode 프로젝트는 로컬 패키지를 프로젝트 수준 `XCLocalSwiftPackageReference`가 아니라 워크스페이스 폴더 참조로 받는다. 둘을 함께 두면 Xcode가 패키지를 못 읽고 pbxproj에서 링크를 지웠다.
- `DiskCandidate`:
  - `volumes`를 튜플 대신 `Volume` 구조체로 뒀다(Codable).
  - `isVirtual`·`ineligibleReason`을 추가하고 `listWholeDisks()`를 더했다(CLI `disks`의 "Not offered").
  - `classify(description:bootWholeDisks:isSynthesized:)`: 디스크 이미지는 `DADeviceInternal`이 없고 `DAMediaRemovable = 1`이라 P8 규칙만으로는 후보가 된다. 그래서 `Virtual Interface`·`Disk Image`·APFS 합성 콘텐츠로도 거른다.
  - 나열과 시동 디스크 판정(APFS 물리 저장소까지)은 IOKit으로 한다. 설명은 DA로 읽는다("DA만 쓴다"와 다름).
  - 파일시스템 표기는 `DAVolumeKind`를 기준으로 한다. DA가 NTFS 볼륨을 `DAVolumeType = MS-DOS (FAT12)`로 보고했다.
- `InstallerError`에 `kind`·`targetModified`·`path`·`errno`를 더했다(GUI의 한국어 문구와 CLI 종료 코드용). `targetState`는 영어 문장이다.
- 종료 코드에 1(확인 거절), 70(내부 오류), 73(이미지 파일이 이미 있음)을 더했다.
- 볼륨 레이블 규칙을 코어에 옮겨 두고(NTFS3G의 `validateLabel`이 internal) 1단계 전에 검사한다. 파티션 테이블을 지운 뒤에 mkntfs가 거부하는 일을 막으려는 것이다.
- `MountGuard`를 `unmountDisk`보다 먼저 건다. 콜백 컨텍스트는 retain하고 `release()`에서 푼다.
- `.image` 대상의 파일은 실패·취소 뒤에도 지우지 않는다(P16을 이미지에도 적용).
- 번들 로더는 `Bundle.module` 대신 직접 찾는다. `Bundle.module`은 못 찾으면 `fatalError`이고, 헬퍼는 `Contents/MacOS`에 있다.
- 작업 디렉터리는 `realpath`로 `/private/tmp/…`를 쓴다(마운트 테이블과 비교해야 한다).
- CA 2023: 추출 결과는 `tmp/wim/EFI_EX/…`(WIMLib 보고서). ISO에 없는 폰트는 새로 쓴다. x64·ARM64 밖은 오류다.
- §15 (c)의 NTFS 읽기는 버퍼드 슬라이스로 한다(1과 같은 이유).
- 앱은 `.iso`를 `open -a`/다음으로 열기로도 받는다(`onOpenURL`).
- 통합 스위트는 부모 스위트 `IntegrationTests` 아래로 묶어 직렬화했다. attach 수 비교가 다른 스위트의 병렬 실행에 흔들리지 않게 하려는 것이다.

## 세 패키지에서 발견한 것 (수정하지 않음)

- **NTFS3G**: libntfs-3g(unix_io)와 mkntfs는 섹터 배수가 아닌 I/O를 해서 macOS raw 노드(`/dev/rdiskN…`)에서 `EINVAL`로 실패한다. README의 "Images hold one partition … image file"은 디바이스 경로를 다루지 않는다. 바운스 버퍼를 가진 `ntfs_device_operations`가 있으면 raw로 돌아갈 수 있다(mkntfs는 기본 I/O라 별도 처리가 필요하다).
- **NTFS3G**: `NTFSVolume.validateLabel`이 internal이라 호출자가 쓰기 전에 레이블을 검사할 수 없다.
- **WIMLib**: 새 문제 없음. 보고서의 "추출은 `tmp/EFI_EX/…`" 등을 실제 Windows ISO의 boot.wim에서 확인했다(`EFI_EX/bootmgfw_EX.efi`, `Fonts_EX/*_EX.ttf` 16개).
- **SlopDisk**: 새 문제 없음.

그 밖에 Xcode 문제가 하나 있었다. 커맨드라인 `xcodebuild`가 Xcode에서 열어 본 적 없는 패키지에 빈 `.swiftpm/xcode`를 남기고, Xcode GUI가 그 패키지를 "Couldn't load project “xcode”"로 못 읽었다. CLAUDE.md에 적었다.

## 커밋

| 커밋 | 제목 |
|---|---|
| 11cc432 | Add the SnakeStickCore package scaffold with the bundled UEFI:NTFS binaries |
| e5c5460 | Mark SnakeStickCore sources as GPL-3.0-or-later |
| c44c834 | Add target disk candidates and ISO inspection |
| f9a682d | Implement the installer pipeline with cleanup and integration tests |
| b113b02 | Name volume file systems by DiskArbitration's volume kind |
| 664f3fa | Add the snakestick command line tool |
| 74e7274 | Add the root helper daemon, its XPC protocol and the Xcode targets |
| 560a329 | Add the SnakeStick window and its String Catalog |
| 58dbe02 | Add the About window and the GPLv3 license text |
| 5d8b9af | Read the Windows release from the install image as Rufus does |
| 44ad818 | Take SnakeStickCore from the workspace instead of a project package reference |
| cfd04e7 | Update CLAUDE.md for SnakeStickCore, the app and the helper |
| 13a00cd | Read the helper's version from its executable and stop re-registering on a mismatch |
| e1023a9 | Let the helper ask for the administrator through the app's authorization |
| b8d4285 / ebbded5 | Mount the ISO in the app … / 그 revert |
| 5528ecc | Ask for Full Disk Access when the helper lacks it |
| 8e8afba | Update the README and CLAUDE.md for the implemented app, CLI and helper |
| (이 보고서) | Add the stage 10 implementation report |

`<closing>`의 7단위보다 많아졌다. 실기에서 나온 수정을 따로 커밋했기 때문이다. 모든 커밋은 경로를 지정해서 만들었고, Co-author 트레일러는 없다. 이 작업의 커밋이 건드린 최상위 경로는 `SnakeStickCore/`, `SnakeStick/`, `SnakeStick.xcworkspace/`, `README.md`, `CLAUDE.md`, `Prompts/`, `COPYING`이다(`COPYING`은 위 7).

작업 트리에 커밋하지 않은 변경이 하나 남아 있다. `SnakeStick/SnakeStick.xcodeproj/project.pbxproj`의 헬퍼 타깃 `CODE_SIGN_IDENTITY[sdk=macosx*] = "Apple Development"`이다. Xcode에서 생긴 변경이라 사용자 판단에 맡겼다.
