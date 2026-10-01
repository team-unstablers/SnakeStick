# 20-osascript-ipc 보고서

`Prompts/20-osascript-ipc.xml`(루트 데몬 제거, 번들 CLI를 osascript로 관리자 권한 실행, 배포 타깃 14.0)의 실행 결과다. 작업일 2026-10-01, 머신은 macOS 26 (Darwin 25.6.0, arm64), Xcode 27.0 (27A266a). 기준 커밋 `46b2175`(지시서의 `397b263` 뒤에 README 커밋 하나가 더 있었다).

## 요약

- `snakestick ipc --socket PATH`를 추가했다. 요청은 소켓의 첫 줄, 이벤트는 줄 단위 JSON으로 돌려보낸다. 메시지 타입과 Unix 소켓 코드(`IPC`)는 `SnakeStickCore/Sources/SnakeStickCore/IPC.swift`에 두고 CLI·앱·테스트가 함께 쓴다.
- 앱은 `HelperClient`·`AdminAuthorization` 대신 `InstallerRunner`(`SnakeStick/SnakeStick/Model/InstallerRunner.swift`)로 쓴다. 0700 임시 디렉토리에서 listen하고 `/usr/bin/osascript`로 `do shell script … with administrator privileges`를 실행한다.
- 데몬 타깃·launchd plist·XPC·Authorization Services·로그인 항목 안내를 모두 지웠다. CLI는 `Contents/Helpers/snakestick`에 들어간다(U2 해결).
- 배포 타깃을 14.0으로 내렸다. 그 과정에서 멈춤 규칙 두 건(macOS 15 API, CLI rpath)을 사용자에게 물어 정했다.
- 작업 뒤 사용자 요청으로 `worktree-moar-i18n`을 `--no-ff` 머지하고, 새로 들어온 8개 언어의 문자열과 README를 이번 변경에 맞췄다.
- 실제 USB 스틱 쓰기는 하지 않았다(`<manual-check>`). U1(TCC)은 그대로 열려 있다.

## 커밋

| 커밋 | 내용 |
|---|---|
| e43803e | Add the ipc subcommand and its socket messages (§1, §2) |
| 6c81427 | Run the bundled CLI through osascript instead of the root daemon (§3, §4, §5) |
| 5d57ce5 | Lower the deployment target to macOS 14 (§6) |
| dbddc6b | Check the bundled CLI instead of the daemon in the DMG script (§7) |
| 8ba4c03 | Describe the osascript write path and macOS 14 in the docs (§8) |
| af1d9e3 | Merge branch 'worktree-moar-i18n' (사용자 요청. 문자열 카탈로그 충돌 해결 포함) |
| eb5356f | Update the README translations for the osascript write path and macOS 14 |
| (이 커밋) | 지시서와 이 보고서 |

## 확인한 것

저장소 루트에서 실행했다. 아래는 머지 뒤 HEAD(eb5356f)에서 마지막으로 돌린 결과다.

| acceptance | 명령 | 결과 |
|---|---|---|
| 1 | `cd SnakeStickCore && swift test` (180초 kill-after 루프) | `Test run with 99 tests in 21 suites passed after 3.553 seconds`. |
| 2 | `cd SnakeStickCore && SNAKESTICK_TEST_INTEGRATION=1 swift test` (300초 루프) | `Test run with 99 tests in 21 suites passed after 45.308 seconds`. 출력에 `Suite IPCMode passed after 13.954 seconds`(imageRequestFinishes, cancelMessage, appGoesAway). |
| 3 | `xcodebuild -workspace SnakeStick.xcworkspace -scheme SnakeStick -configuration Debug clean build` | `** BUILD SUCCEEDED **`. 앱 소스(`.swift`) 경고 0, 배포 타깃 관련 경고 없음. 남은 경고는 패키지 의존성 스캔 경고 3줄뿐이다(아래 "그 밖에 본 것"). |
| 4 | `grep -n MACOSX_DEPLOYMENT_TARGET SnakeStick/SnakeStick.xcodeproj/project.pbxproj` | 8줄 모두 `14.0`(프로젝트 레벨 2, 앱 2, 단위 테스트 2, UI 테스트 2). 빌드된 앱·CLI·`SnakeStickCore.framework`의 `LC_BUILD_VERSION minos`는 모두 14.0. |
| 5 | 빌드된 `SnakeStick.app/Contents` 조회 | `Helpers/snakestick` 있음. `MacOS`는 `SnakeStick`, `SnakeStick.debug.dylib`, `__preview.dylib`뿐. `Contents/Library` 없음(증분 빌드에서는 예전 `Library/LaunchDaemons`가 남아 있어서 clean build로 확인했다). |
| 6 | `SNAKESTICK_TEST_INTEGRATION=1 SNAKESTICK_TEST_BINARY=<앱>/Contents/Helpers/snakestick swift test --filter "IPCMode\|IPCRefusal"` | 8개 통과. `imageRequestFinishes`가 `finished(verified: true)`까지 받았고 `ImageChecks`가 FAT의 UEFI:NTFS 파일 4개를 확인했다(리소스를 못 찾았다는 오류 없음). 이 실행 동안 DerivedData의 `Products/Debug/PackageFrameworks`를 잠시 다른 이름으로 옮겨서, CLI가 번들의 `Contents/Frameworks`로 로드된다는 것도 같이 확인했다. 이 실행은 CLOEXEC 추가(6c81427에 포함) 전의 바이너리였다. |
| 7 | `codesign -dv --verbose=4 <앱>/Contents/Helpers/snakestick` | `Identifier=snakestick`, `flags=0x10000(runtime)`, `Authority=Apple Development: Gyuhwan Park (GY7LYT2WG7)`, `TeamIdentifier=XHA76UVA95`. Debug 빌드에서 `CodeSignOnCopy`로 재서명된 CLI에 hardened runtime 플래그가 붙는다(U3의 Debug 쪽). |
| 8 | §4의 grep | 결과 없음(exit 1). `grep -rn dataLossRisk SnakeStickCore/Sources`는 `Pipeline/Partitioning.swift:34` 한 줄. |
| 9 | `hdiutil info \| grep -c image-path` | 모든 테스트 실행 전후 9 → 9. |
| 10 | `git -C NTFS3G/Vendor/ntfs-3g status --short`, `git -C WIMLib/Vendor/wimlib status --short` | 둘 다 비어 있음. |

### code#ipc-mode의 ensure → 테스트

모두 `SnakeStickCore/Tests/SnakeStickCoreTests/IPCTests.swift`에 있고 위 실행에서 통과했다.

| ensure | 테스트 | 확인 내용 |
|---|---|---|
| `.image` 요청 → progress ≥ 1, 마지막 finished, 종료 코드 0 | `IntegrationTests.IPCMode.imageRequestFinishes` | 종료 코드 0, `terminationReason == .exit`, stdout 비어 있음, 이미지 검사, attach 수 동일, 작업 디렉토리 삭제. ISO·이미지·소켓 경로에 공백, 작은따옴표, 한글이 들어간다. |
| 진행 중 cancel → 마지막 failed(.cancelled), make의 SIGINT와 같은 종료 코드 | `IPCMode.cancelMessage` | `prepareTarget` 진행 이벤트에서 cancel을 두 번 보낸다. 종료 코드 130, 마지막 이벤트 `failed(kind: .cancelled)`, attach 수 동일. |
| 앱 쪽 소켓을 닫음 → 정리 후 종료, SIGPIPE로 죽지 않음 | `IPCMode.appGoesAway` | `terminationReason == .exit`, 종료 코드 130, attach 수 동일, 스크래치 이미지가 attach로 남지 않음. |
| 첫 메시지가 start가 아님 → failed 또는 usage, 대상 안 건드림 | `IPCRefusalTests.firstMessageMustBeStart`, `malformedFirstLine`, `closedBeforeStart` | `failed(kind: .usage)` 한 개, 종료 코드 64. start 전에 닫으면 64. |
| root 아님 + `.device` → failed(.rootRequired), 장치 안 열림 | `IPCRefusalTests.deviceNeedsRoot` | `failed(kind: .rootRequired)` 한 개, 종료 코드 77. 디스크 이름은 존재하지 않는 `disk999`이고, root 검사가 디스크 조회보다 먼저다(기존 `makeNeedsRoot`와 같은 방식). |
| 존재하지 않는 소켓 → 0이 아닌 종료 코드 | `IPCRefusalTests.missingSocket` | 종료 코드 74, stdout 비어 있음. |

§1 단위 테스트(`IPCMessageTests`, `IPCSocketTests`): 각 메시지 왕복, 와이어 형식(`{"cancel":{}}`, `{"start":{…}}`, `{"event":{…}}`), 개행·CR·U+2028이 든 로그도 한 줄, 잘못된 메시지 거부, `ipc` 인자 파싱과 usage 미노출, 0700 디렉토리와 정리, 104바이트를 넘는 경로 거부(디렉토리도 남지 않음), accept 중단, 소켓 버퍼보다 큰 양방향 전송, 닫힌 상대에 쓰면 SIGPIPE 대신 예외.

### 그 밖에 확인한 것

- osascript 인자 전달: `osascript -e 'on run argv' … -- "-x y" "한글 'q'"`가 두 인자를 그대로 받고(`--`는 소비된다), `quoted form of`로 만든 명령이 `a 'b' 한글`을 그대로 넘긴다. `error number -128`의 stderr는 `execution error: 사용자가 취소함. (-128)`(현지화됨)이라 앱은 `(-128)`로 판정한다.
- ipc 모드의 stderr: `imageRequestFinishes`에서 툴의 stderr가 `""`였다. libntfs-3g·wimlib이 직접 찍는 출력은 보이지 않았다.
- 빌드된 앱의 `ko.lproj`·`ja.lproj`·`fr.lproj/Localizable.strings`에 새 문자열 3개가 번역되어 들어가 있다.
- `distutil/build_dmg.sh`: `bash -n` 통과. 새로 넣은 rpath·링크 검사 부분만 Debug 앱 번들에 따로 돌려서 `@executable_path/../Frameworks`와 프레임워크 4개를 찾는 것을 확인했다. 스크립트 전체는 돌리지 않았다(아래).

## 확인하지 못한 것

- **U1 (TCC).** osascript로 띄운 루트 CLI가 이동식 디스크의 raw 노드와 `~/Downloads`의 ISO를 열 수 있는지 모른다. FDA 안내는 `failed` 이벤트의 `errno == EPERM`일 때 뜨도록 남겼다(P6).
- **U3 (Release).** Developer ID export에서 CLI에 hardened runtime이 붙는지, 서명 식별자가 `snakestick`인지(`build_dmg.sh`의 `CLI_IDENTIFIER`)는 확인하지 못했다. 사용자가 `build_dmg.sh --skip-notarize` 실행을 원하지 않았다. 공증도 하지 않았다.
- **Release 빌드의 커버리지 계측.** Debug 빌드는 `-profile-generate`로 계측되어, 번들 CLI가 종료할 때 작업 디렉토리에 `default.profraw`를 쓴다(이 작업 중 저장소 루트와 `SnakeStickCore/`에 생긴 것을 지웠다). `xcodebuild -showBuildSettings`로는 Release에도 `ENABLE_CODE_COVERAGE = YES`가 나온다. 이전 Release export(`dist/build/export`, 데몬 시절)의 앱·데몬에는 `__llvm_prf_cnts`가 없었다. 새 구조의 Release export는 확인하지 못했다. 계측된 CLI가 `do shell script`(root)로 돌면 `/default.profraw`를 쓸 수 있다.
- **앱에서 실제로 쓰기.** 앱 GUI로 관리자 대화상자 → 쓰기를 돌려 보지 않았다. `InstallerRunner`는 빌드만 확인했고, 그 소켓·이벤트 처리는 Core의 `IPC`를 같이 쓰는 테스트 하네스로만 검증됐다.
- **인증 대기 중 Stop.** 연결 전에 취소하면 osascript에 SIGTERM을 보낸다. 그러면 관리자 대화상자가 닫히는지는 확인하지 않았다.
- **About 창 복원.** `.restorationBehavior(.disabled)` 대신 `NSWindow.isRestorable = false`로 바꿨다. About 창을 연 채 종료하고 다시 실행했을 때 창이 다시 뜨지 않는지는 확인하지 않았다.

### manual-check 절차 (사람이 할 일)

1. 앱에 FDA를 주지 않은 상태로 `~/Downloads`의 ISO와 실제 USB 스틱을 고르고 쓴다. 관리자 대화상자 → (TCC 프롬프트가 뜨는지) → 결과를 기록한다. U1의 세 가능성(그냥 열린다 / 앱 이름으로 TCC 프롬프트 / EPERM) 중 무엇인지. EPERM이면 FDA 안내가 뜨는지도 본다. 로그는 `/usr/bin/log show --predicate 'subsystem == "pl.unstabler.aislop.SnakeStick"' --last 10m`.
2. 쓰는 도중 "Stop" → 정리 후 대기 화면으로 가는지.
3. 쓰는 도중 앱을 `kill -9` → `ps ax | grep 'snakestick ipc'`로 CLI가 정리 후 사라지는지, `diskutil list`로 스틱이 마운트 가드에 묶여 있지 않은지(자동 마운트가 다시 되는지).
4. 관리자 대화상자에서 취소 → 조용히 대기 화면으로 가는지.
5. (추가) "Waiting for authorization…" 상태에서 Stop → 대화상자가 닫히고 대기 화면으로 가는지.
6. (추가) About 창을 연 채 종료 → 재실행 시 About 창이 다시 뜨지 않는지.
7. 결과에 따라 FDA 안내와 README의 FDA 문구를 지울지 정한다.

Debug 빌드로 할 때는 `/default.profraw`(root 소유)가 생길 수 있다.

## 지시서와 다르게 한 것

1. **macOS 15 API (§6 멈춤 규칙).** `SnakeStickApp.swift`의 About 창 `.restorationBehavior(.disabled)`가 macOS 15 전용이라 14.0에서 빌드되지 않았다. 사용자가 "AppKit `isRestorable`로 대체"를 골랐다. 기존 `WindowAccessor`로 `NSWindow.isRestorable = false`를 건다. 동작이 같은지는 확인하지 못했다(위).
2. **CLI rpath (U2의 후속 문제).** Xcode는 패키지 executable 제품을 빌드해 복사 단계에 넣을 수 있었다(U2 해결). 그런데 앱과 CLI가 둘 다 Core를 링크하자 Xcode가 SnakeStickCore·NTFS3G·WIMLib·SlopDisk를 동적 프레임워크로 바꿔 `Contents/Frameworks`에 넣었고, CLI의 rpath는 `@loader_path`와 DerivedData 절대 경로뿐이었다. 배포한 앱에서는 CLI가 뜨지 않는다. 사용자가 "Package.swift에 rpath 추가"를 골랐다. `snakestick` 타깃에 `.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])`를 넣었다. 대가: `swift build` 바이너리에도 쓰이지 않는 rpath가 하나 붙고, 앱 번들에 프레임워크 4개가 생겼다(전에는 정적 링크). `build_dmg.sh`가 이 rpath와 프레임워크 존재를 검사한다.
3. **커밋 전부터 있던 pbxproj·xcscheme 변경.** 작업 시작 시 워킹트리에 모든 타깃의 `MACOSX_DEPLOYMENT_TARGET = 14.0` 추가와 xcscheme의 `BlueprintName` 두 줄이 커밋되지 않은 채 있었다. 사용자가 "내 작업에 흡수"를 골라 5d57ce5에 넣었다. 그래서 `MACOSX_DEPLOYMENT_TARGET`는 F2의 4곳이 아니라 8곳이다(타깃 레벨 6곳 + 프로젝트 레벨 2곳, 모두 14.0).
4. **ipc 모드의 stdout.** 지시서는 라이브러리의 직접 출력은 막을 수 없다고 봤지만, ipc 모드 시작 시 `dup2(STDERR_FILENO, STDOUT_FILENO)`로 fd 1을 stderr로 돌렸다. 그래서 테스트의 "stdout이 비어 있다"는 사실상 항상 참이고, 실제 판단은 stderr를 출력해 본 것(`""`)으로 했다.
5. **연결 전 취소.** 의사코드의 `cancel()`은 "이미 끝난 연결이면 아무것도 하지 않는다"까지만 정했다. 인증 대화상자가 떠 있는 동안(연결 전) Stop을 누르면 osascript를 terminate하고 `.authCancelled`로 끝낸다. 그 사이 CLI가 이미 연결했으면 start를 보내지 않고 소켓을 닫는다(CLI는 64로 끝나고 아무것도 열지 않는다).
6. **FDA 안내 화면.** 예전에는 거절이면 대기 화면 + 안내였지만, 이제 EPERM은 파이프라인 실패로 오므로 실패 화면(07)을 띄우고 그 위에 안내를 띄운다.
7. **`.device` 거절의 kind.** `make`의 검사를 `SnakeStickCLI.checkDevice`로 옮겨 make와 ipc가 같이 쓴다. ipc에서는 없음·부적격 → `.targetIneligible`, 크기 부족 → `.insufficientSpace`, root 아님 → `.rootRequired`로 보내고, 종료 코드는 `report(_:)`가 kind에서 정한다(make와 같은 77·69). 문구는 make와 같다("See snakestick disks." 포함).
8. **존재하지 않는 소켓의 종료 코드.** 74(`EX_IOERR`)로 했다. 지시서는 "0이 아닌 코드"만 정했다.
9. **소켓에 FD_CLOEXEC.** osascript·hdiutil·diskutil 같은 자식 프로세스가 소켓을 물고 있으면 상대가 EOF를 늦게 받으므로 두 소켓 모두 close-on-exec로 했다.
10. **`HelperConstants.appBundleIdentifier`의 자리.** P7대로 남기되 `SnakeStickCore/Sources/SnakeStickCore/Constants.swift`의 `SnakeStickConstants.appBundleIdentifier`로 옮겼다. 앱 로그 subsystem은 그대로 `pl.unstabler.aislop.SnakeStick`이다.
11. **`SNAKESTICK_TEST_BINARY`.** acceptance 6을 위해 테스트가 쓰는 CLI 경로를 이 환경 변수로 바꿀 수 있게 했다(`CLITests.swift`).
12. **커밋 6c81427의 스테이징.** pbxproj에서 배포 타깃 줄만 빼고 커밋하려고, 그 줄을 뺀 내용을 `git hash-object -w` + `git update-index --cacheinfo`로 인덱스에 올리고 경로 없이 `git commit`했다. `git commit -- <paths>`는 워킹트리 내용을 다시 스테이징하기 때문이다. 커밋 직전 인덱스에 이 작업의 파일만 있는 것을 `git diff --cached --name-status`로 확인했다.
13. **DerivedData 정리.** 첫 Xcode 빌드가 `Products/Debug`에 남아 있던 예전 정적 `SnakeStickCore.swiftmodule`(데몬 시절 빌드)을 집어 `IPC`를 못 찾았다. 그 낡은 산출물(`SnakeStickCore.swiftmodule`, `SnakeStickCore.o`, `SnakeStickHelper`, `SnakeStickHelper.swiftmodule`)을 지우고 다시 빌드했다. 공유 DerivedData를 쓰는 다른 작업에는 영향이 없을 것으로 보지만, Xcode GUI에서 같은 오류가 나면 Clean Build Folder가 필요할 수 있다.

## 그 밖에 본 것

- **Xcode가 자동으로 넣은 빌드 파일.** 작업 중 Xcode GUI가 열려 있었고, pbxproj를 고치자 `snakestick in Frameworks`(실행 파일 제품을 앱의 Frameworks 단계에 넣는 `PBXBuildFile`)를 스스로 추가했다. 앱 바이너리는 `snakestick`을 링크하지 않는다(`otool -L`로 확인). Xcode가 다시 넣을 것이라 그대로 두었다.
- **패키지 의존성 경고.** 빌드마다 `'SnakeStickCore' is missing a dependency on 'NTFS3G' / 'SlopDisk' / 'WIMLib' because dependency scan … discovered a dependency` 경고 3줄이 나온다. 이번 변경(동적 프레임워크 전환) 전에도 있었는지는 확인하지 못했다. 동작에는 문제가 없었다.
- **P6: EPERM이 `InstallerError.errno`에 실리는 경로.** 실리는 곳: ISO의 `stat`·볼륨 레이블 읽기(`ISOInfo.swift`의 `ISOSession.init`·`inspectISO`), SlopDisk의 raw 장치 열기(`SDError.io`), NTFS3G의 POSIX 오류, 밑에 `POSIXError`가 있는 `CocoaError`. 실리지 않는 곳: 외부 도구 실패(`DiskToolError`). 특히 `hdiutil attach`로 ISO를 붙이는 단계, `diskutil unmountDisk`·`mount`, `newfs_msdos`는 종료 코드와 stderr만 남아서, TCC가 이 도구들을 막으면 FDA 안내가 뜨지 않는다. 그 경로의 Core 수정은 범위 밖이라 하지 않았다.
- **FDA 안내 문구.** 앱의 FDA 알림 본문은 여전히 "디스크를 쓰는 도우미(helper)"라고 말한다. 번들 CLI도 도우미라 틀린 말은 아니어서, 9개 언어 번역이 다 있는 이 문자열은 그대로 두었다. U1 결과에 따라 알림 자체를 지울 수도 있다.
- **Debug 빌드의 `-profile-generate`.** 앱 타깃도 같다. 위 "확인하지 못한 것" 참고. `CLAUDE.md`와 `docs/DESIGN.md`에 적었다.

## i18n 머지 (사용자 추가 요청)

- `git merge --no-ff worktree-moar-i18n`: `Localizable.xcstrings`만 충돌했다. 브랜치 쪽(9개 언어)을 기준으로 받고, 이번 작업에서 지운 키 5개(`Allow the SnakeStick helper`, 로그인 항목 안내, `The connection to the helper was lost.`, `The helper could not be reached: %@`, `The helper refused the write: %@`)를 지우고, 새 키 3개(`The write could not be started: %@`, `The write could not be started as an administrator: %@`, `The write stopped without a result.`)를 ko·ja·zh-Hans·zh-Hant·de·fr·es·pt-BR·ru로 넣었다. 프랑스어는 기존 번역처럼 콜론 앞에 U+00A0을 썼다. 머지 커밋은 af1d9e3.
- README 8개 번역(ja, zh-Hans, zh-Hant, de, fr, es, pt-BR, ru): 배지와 요구 사항을 macOS Sonoma 14로, "처음 실행할 때 권한 두 가지" 절을 "권한" 절(관리자 암호는 쓸 때마다, FDA)로, FDA FAQ의 launchd 데몬 설명을 앱 안의 도구로 바꿨다. 영어·한국어와 같은 내용이다. 번역문은 기존 번역의 용어(예: 독일어 du, 프랑스어 vous, Festplattenvollzugriff, 完全取用磁碟)를 따랐고 원어민 검토는 받지 않았다.
