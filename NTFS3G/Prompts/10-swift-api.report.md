# 10-swift-api 보고서

`Prompts/10-swift-api.xml`(NTFS3G v1: libntfs-3g 위의 Swift API)의 실행 결과다. 작업일 2026-09-30, 머신은 macOS 26.6.2(25G83), Apple Swift 6.4(swiftlang-6.4.0.34.1), MacOSX27.0 SDK.

## 요약

- 공개 API(code#api) 전체를 구현했다. 파일 구성은 `Sources/NTFS3G/` 11개, C 헬퍼 1개(`Vendor/CNTFS3G/cntfs3g_helpers.c`), 설정 헤더 1개(`Vendor/CNTFS3G/override/config.h`), `Tests/NTFS3GTests/` 8개다. 스캐폴드의 `mkntfs_entry.c`와 `CNTFS3G.h`도 고쳤다.
- 작업 중 멈추고 사용자에게 네 번 물었다. 그 결과 지시서와 다르게 구현한 곳이 있다. mkntfs 재진입 버그 우회, DEBUG 매크로 제거, 로케일 처리 방식(P7), 이름 NFC 정규화(P3/C5)다. 아래 "멈추고 보고한 지점"과 "지시서와 다르게 구현한 것"에 모두 적었다.
- 서브모듈은 수정하지 않았다.

## 확인한 것

아래는 모두 실제로 실행해서 결과를 본 명령이다. 저장소 루트에서 실행했다.

| 명령 | 결과 |
|---|---|
| `cd NTFS3G && swift package clean && swift build` | `Build complete!` (종료 코드 0). 경고 113개는 모두 서브모듈 C 코드에서 나왔다(`ntfs-3g/libntfs-3g/*`, 그리고 `mkntfs_entry.c`가 include한 `ntfsprogs/mkntfs.c` 18개). NTFS3G가 소유한 파일에서는 경고가 없다. |
| `cd NTFS3G && swift test` | 종료 코드 0. `Test run with 64 tests in 6 suites passed` (NTFS3GTests) + `Test run with 1 test in 0 suites passed` (CNTFS3GTests 스모크 테스트). `Suite IntegrationTests skipped: "set NTFS3G_INTEGRATION=1"`, `fskitReadsCopiedTree()`·`fileLargerThan4GiB()` skipped. |
| `cd NTFS3G && NTFS3G_INTEGRATION=1 swift test` | 종료 코드 0. 64개 + 1개 통과. `fskitReadsCopiedTree()` 4.5초, `fileLargerThan4GiB()` 5.2초. |
| 위 실행 전후 `hdiutil info \| grep image-path` 비교 | 차이 없음. 실행 후 `hdiutil info`에 `NTFS3GTests` 문자열 0건. 사용자가 원래 붙여 둔 이미지 8개는 그대로다. |
| `git -C NTFS3G/Vendor/ntfs-3g status --short` | 출력 없음 |
| `git -C NTFS3G/Vendor/ntfs-3g describe --tags` | `2026.9.28` |
| 이 작업의 커밋마다 `git show --stat --format= <커밋>` | 5개 커밋 모두 `NTFS3G/` 밖의 경로가 없다. `Co-Authored-By` 트레일러도 없다. 보고서가 들어간 마지막 커밋은 아래 "커밋"을 본다. |
| `$TMPDIR` 확인 | 테스트가 끝난 뒤 `NTFS3GTests-*` 스크래치 디렉터리가 남지 않았다. |

그 밖에 검증 목적으로 실행한 것:

- 로케일 테스트가 헛돌지 않는지 확인했다. `mkntfs_entry.c`의 `#define utils_set_locale keep_process_locale`을 잠시 주석 처리하면 `formatLeavesLocaleUnchanged`와 `formatIgnoresEnvironmentLocale`이 둘 다 실패했고(`before == after` 실패, exit test는 `EXIT_FAILURE`), 되돌리면 통과했다.
- FSKit 드라이버의 이름 처리를 임시 진단 테스트로 확인했다(결과는 "발견한 것" 참조). 진단 테스트는 삭제했다.

## 확인하지 못한 것

- **U1.** Windows와 Windows 설치 프로그램이 POSIX 네임스페이스 이름(F6)만 있고 DOS 8.3 이름이 없는 볼륨을 문제없이 읽는지. Windows 기기가 없어 확인하지 못했다.
- **U2.** Windows `chkdsk`가 이 볼륨을 깨끗하다고 판정하는지. 역시 확인하지 못했다.
- **release 구성의 테스트.** `swift test -c release`는 mkntfs 재진입 버그를 고치기 전에 한 번 돌렸다(두 번째 포맷에서 무한 루프에 빠져 사용자가 중단시켰다). 수정 후에는 release 구성으로 테스트를 돌리지 않았다.
- **Xcode에서의 빌드.** SnakeStick 워크스페이스를 Xcode로 빌드하지 않았다. `override/config.h`는 Xcode도 debug 구성에서 `DEBUG=1`을 정의한다는 전제로 넣은 것이다. 이 전제는 SwiftPM(swiftbuild 백엔드)에서만 확인했다(`-DDEBUG=1`이 C 컴파일 인자 파일에 있었다).
- **실제 Windows ISO.** 크기 추정과 copyTree를 실제 Windows ISO로 돌려 보지 않았다. 픽스처로만 검증했다.
- **공간 부족(ENOSPC) 경로.** 볼륨이 가득 찼을 때의 에러 처리를 테스트하지 않았다.
- **FSKit에서의 생성 시각.** FSKit 교차 검증은 이름·종류·크기·내용·수정 시각만 비교했다(§10(a)의 범위). 생성 시각은 NTFSVolume으로 다시 읽어서만 확인했다(`copyTreeMapsHostTimes`).

## 멈추고 보고한 지점

작업 중 사용자에게 네 번 물었다(AskUserQuestion). 모두 사용자가 고른 대로 구현했다.

1. **mkntfs는 한 프로세스에서 두 번 돌 수 없다.** `ntfsprogs/mkntfs.c`의 `mkntfs_cleanup()`(3425행~)은 `g_allocation` 리스트의 노드를 free하지만 포인터를 NULL로 되돌리지 않는다(3455-3460행). 그래서 두 번째 `ntfs3g_mkntfs()` 호출은 해제된 메모리를 따라간다. debug 빌드에서는 SIGSEGV, release 빌드에서는 무한 루프가 났다. 스모크 테스트는 프로세스당 한 번만 포맷하므로 F1에서 드러나지 않았다. `g_upcaseinfo`는 아예 해제되지 않는다(누수).
   - 제시한 선택지: 유니티 빌드 래퍼 / fork()로 자식 프로세스에서 실행 / 별도 헬퍼 실행 파일 / 서브모듈 포크.
   - **사용자 선택: 유니티 빌드 래퍼.** `mkntfs.c`를 sources 목록에서 빼고 `mkntfs_entry.c`가 `#include`한다. 매 실행 뒤 `reset_mkntfs_globals()`가 `g_*` static 24개를 초기값으로 되돌리고 `g_upcaseinfo`를 해제한다.
2. **SwiftPM은 debug 빌드에서 C 타깃에 `-DDEBUG=1`을 넣는다.** ntfs-3g는 이 매크로를 자기 디버그 스위치로 쓴다. 그래서 모든 함수가 트레이스 로그를 stderr에 쏟아내고, 기본 로그 핸들러가 `outerr`가 되고, 일부 검사가 `exit()`를 부른다(예: `unistr.c`의 `ntfs_names_full_collate`).
   - 제시한 선택지: config.h 래퍼 헤더 / `.unsafeFlags(["-UDEBUG"])` / 그대로 둔다.
   - **사용자 선택: config.h 래퍼 헤더.** `Vendor/CNTFS3G/override/config.h`가 생성된 `../config.h`를 include한 뒤 `#undef DEBUG`를 한다. 이 경로를 헤더 검색 경로 맨 앞에 둔다. DEBUG 여부로 구조체 레이아웃이 달라지는 헤더는 없다(`include/ntfs-3g/`에서 `DEBUG`를 쓰는 곳은 `debug.h`의 `ntfs_debug_runlist_dump` 선언과 `logging.h`의 로그 매크로뿐이다).
3. **P7의 로케일 저장·복원으로는 부족하다.** 복원은 호출이 끝난 뒤에만 이루어진다. mkntfs가 도는 동안에는 프로세스의 모든 스레드가 환경 로케일을 본다. 병렬 테스트에서 실제로 다른 테스트가 `before = "ko_KR.UTF-8"`, `after = "C"`를 관찰했다. mkntfs가 로케일을 바꾸는 곳은 `mkntfs.c:5194`의 `utils_set_locale()` 호출 하나다(`utils.c:133-146`).
   - 제시한 선택지: `utils_set_locale` 무력화 / 무력화 + P7 복원도 유지 / P7 그대로.
   - **사용자 선택: 무력화.** 유니티 래퍼에서 `#define utils_set_locale keep_process_locale`로 이름을 바꿔 아무것도 하지 않는 static 함수를 부르게 했다(D3가 허용하는 심볼 이름 변경). P7의 저장·복원 코드는 없앴다. 복원 코드가 남아 있으면, 그 사이에 앱의 다른 스레드가 바꾼 로케일을 되돌려 버리기 때문이다. mkntfs는 레이블을 `ntfs_mbstoucs`(use_utf8 경로, F14)로 바꾸므로 로케일과 무관하다.
4. **macOS의 FSKit NTFS 드라이버는 NFD로 저장된 이름을 열지 못한다.** 진단 결과는 다음과 같다.

   | NTFS에 저장된 형태 | FSKit readdir가 돌려주는 이름 | lstat/open (목록의 이름, NFC, NFD 모두 시도) |
   |---|---|---|
   | NFC (`한글.txt`) | NFD로 바꿔서 돌려줌 | 모두 성공 |
   | NFD (`분해.txt`, 디렉터리 `폴더`) | NFD | 모두 ENOENT |

   Foundation은 파일 경로를 NFD로 바꿔서(`fileSystemRepresentation`) 파일을 만든다. 따라서 바이트를 그대로 옮기는 P3/C5 방식이면 macOS에서 만든 한글 이름이 NTFS에 NFD로 들어가고, macOS에서는 그 항목을 열 수 없게 된다.
   - 제시한 선택지: P3 유지하고 테스트만 맞춤 / copyTree만 NFC로 정규화 / API 전체에서 NFC로 정규화 / NFC가 아닌 이름 거부.
   - **사용자 선택: API 전체에서 NFC로 정규화.** `NTFSPath`가 모든 경로 구성 요소를 `precomposedStringWithCanonicalMapping`으로 정규화한다. 저장과 조회가 모두 NFC로 이루어지고, 목록은 디스크에 저장된 그대로 돌려준다. 볼륨 레이블도 NFC로 정규화한다.

## 지시서와 다르게 구현한 것

| 지시서 | 구현 | 이유 |
|---|---|---|
| §1 "C 타깃 설정(sources 목록, 헤더 검색 경로)은 스캐폴드 그대로" | sources에서 `ntfsprogs/mkntfs.c`를 뺐다(`mkntfs_entry.c`가 include한다). 헤더 검색 경로 맨 앞에 `CNTFS3G/override`를 추가했다. 헬퍼 소스 `CNTFS3G/cntfs3g_helpers.c`도 추가했다. | 멈추고 보고한 지점 1, 2 |
| P7 로케일 저장·복원 | 저장·복원을 하지 않는다. mkntfs가 로케일을 아예 바꾸지 않게 했다. | 멈추고 보고한 지점 3 |
| P7 (범위 밖) | mkntfs가 `-q`로 지우는 libntfs-3g 로그 레벨도 저장했다가 복원한다. | 핸들러 복원과 같은 종류의 부작용이다. |
| P3 "유니코드 정규화는 하지 않는다", C5 "정규화하지 않고 바이트 그대로" | 모든 이름과 레이블을 NFC로 정규화한다. 목록은 저장된 그대로 돌려준다. | 멈추고 보고한 지점 4 |
| P10 "`ntfs_names_are_equal`에 IGNORE_CASE를 넘기는 방식을 쓸 수 있다" | `cntfs3g_lookup_ignoring_case()`가 볼륨의 `NV_CaseSensitive` 플래그를 한 번의 `ntfs_inode_lookup_by_name()` 호출 동안만 끈다. | 대소문자 무시 비교(`ntfs_names_full_collate`의 IGNORE_CASE)는 $I30 정렬 순서(대문자로 바꾼 이름 우선)를 거칠게 만든 것이다. 그래서 B+트리 탐색 결과가 그대로 유효하고 O(log n)이다. readdir 전체를 훑으면 항목 5000개짜리 디렉터리에서 O(n²)가 된다. `ntfs_set_ignore_case()`는 C6 때문에 쓰지 않았다. |
| P6 `-L <label>` | 레이블이 빈 문자열이면 `-L`을 넘기지 않는다. | 빈 레이블은 "레이블 없음"이다. |
| P8 progress | 빈 파일이면 `progress(0)`을 한 번 부른다. copyTree도 빈 파일마다 한 번 부른다. | "마지막 값 == 원본 크기"가 빈 파일에서도 성립하게 하고, copyTree의 `currentPath`가 모든 파일을 거치게 하려는 것이다. |

지시서가 정하지 않았던 동작을 추가로 정한 것:

- 루트(`/`)에 `createDirectory`/`writeFile`을 하면 `alreadyExists("/")`.
- 이름에 NUL이 들어 있으면 `invalidName`(`ntfs_mbstoucs`가 C 문자열로 받으므로 NUL에서 잘린다).
- `writeFile(from:)`의 원본이 디렉터리이면 `.posix(operation: "open", errno: EISDIR)`, FIFO나 소켓 같은 특수 파일이면 `unsupportedFileType`. 원본은 `O_NONBLOCK`으로 열어서 FIFO에서 멈추지 않게 했다.
- file URL이 아닌 URL은 `.posix(operation: "open", errno: EINVAL)`로 거부한다. `https://host/a`의 fileSystemRepresentation이 `/a`가 되어 로컬 파일을 열 뻔했다.
- copyTree는 쓰기 전에 원본 트리 전체의 이름(D12)과 시각 범위도 미리 검사한다. 심볼릭 링크와 특수 파일도 스캔 단계에서 잡으므로, 이런 에러가 나면 아무것도 쓰지 않은 상태로 끝난다.
- copyTree는 `destination` 자체의 시각을 바꾸지 않는다.
- copyTree는 원본 파일을 URL이 아니라 readdir로 얻은 이름 바이트로 만든 경로로 연다. URL을 거치면 이름이 NFD로 바뀐다.
- `freeBytes`는 호출할 때 비트맵을 센다(`ntfs_volume_get_free_space`). `close()` 뒤에는 마지막으로 관찰한 값을 돌려준다(getter가 throw할 수 없기 때문).
- `Date` → NTFS 시각 변환은 `timeIntervalSinceReferenceDate` 기준으로 반올림한다. 호스트 `timespec` → NTFS 시각 변환(copyTree)은 정수 연산으로 100 ns 미만을 버린다. 2020년대 날짜는 `Double`이 100 ns 단위를 모두 구분하지 못한다. 그래서 `Date`를 거치면 1틱 오차가 날 수 있고, 테스트의 고정 시각은 2001년으로 잡았다.

## 발견한 것 (다음 작업에 참고)

- Foundation(`URL`, `FileManager`, `Data.write(to:)`)으로 만든 파일은 한글 이름이 NFD로 저장된다. 테스트 픽스처는 `mkdir(2)`/`open(2)`에 Swift `String`을 직접 넘겨 만든다.
- APFS의 이름 한도는 UTF-8 255바이트다. NFD 한글은 음절당 6~9바이트라 40음절 안팎에서 한도에 걸린다.
- Swift Testing: 클로저 안의 `try`가 `#expect(...)` 매크로 안에만 있으면 클로저가 throwing으로 추론되지 않아 "errors thrown from here are not handled"가 난다. 클로저에 `throws`를 명시해야 한다.
- `-DDEBUG=1`은 SwiftPM(swiftbuild 백엔드)의 debug 구성에서 C 컴파일 인자 파일(`*-common-args.resp`)로 들어간다.

## ensure → 테스트 대응표

테스트 이름은 `NTFS3GTests` 타깃 기준이다.

| code#api의 ensure | 테스트 |
|---|---|
| format: 64 MiB, label "SNAKESTICK" → readOnly 마운트 label == "SNAKESTICK" | `FormatTests/formatSetsLabel()` |
| format: sectorSize 4096 → readOnly 마운트 성공 | `FormatTests/formatWith4KSectors()` |
| format: 존재하지 않는 경로 → throws | `FormatTests/formatMissingFileThrows()` |
| format: label "A:B" → invalidName | `FormatTests/formatRejectsInvalidLabel(label:)` ("A:B" 외 4개) |
| format 전후 setlocale(LC_ALL, nil) 같음 | `FormatTests/formatLeavesLocaleUnchanged()`, `FormatTests/formatIgnoresEnvironmentLocale()` (exit test. 환경 로케일 de_DE.UTF-8, 실행 중에도 감시) |
| estimatedVolumeSize: 각 픽스처에서 추정 크기로 format → copyTree 성공 | `EstimateTests/estimatedSizeIsSufficientAndTight(fixture:)` (빈 디렉터리 / 4 KiB 미만 5000개 / 1~64 MiB 4개 / 깊이 20 / 한글 이름), 추가로 `EstimateTests/estimatedSizeHoldsForOtherGeometries(sectorSize:clusterSize:)` |
| estimatedVolumeSize % 1 MiB == 0 | `EstimateTests/estimatedSizeIsSufficientAndTight(fixture:)` |
| estimate − content ≤ content/33 + 96 MiB | `EstimateTests/estimatedSizeIsSufficientAndTight(fixture:)` |
| init: 0으로 채운 파일 → throws | `FormatTests/mountUnformattedThrows()` |
| createDirectory("/a") → contentsOfDirectory("/") == [a dir] | `DirectoryTests/createDirectoryAppearsInListing()` |
| createDirectory("/a/b") (부모 없음) → notFound("/a") | `DirectoryTests/createDirectoryWithoutParentThrowsNotFound()` |
| "/Sources" 후 "/sources" → alreadyExists | `DirectoryTests/createDirectoryCaseCollision()` |
| "/CON" → invalidName | `DirectoryTests/createDirectoryRejectsWindowsNames(name:)` |
| "/a." → invalidName | 같음 |
| "/a " → invalidName | 같음 |
| "a" → invalidPath | `DirectoryTests/createDirectoryRejectsInvalidPaths(path:)` |
| "/a//b" → invalidPath | 같음 |
| readOnly 볼륨에서 createDirectory → readOnlyVolume | `DirectoryTests/createDirectoryOnReadOnlyVolume()` |
| writeFile: 20 MiB + 12345 바이트, 재마운트 후 readFile로 바이트 단위 비교 | `FileTests/writeFileRoundTrip()` |
| progress 마지막 값 == 크기, 단조 증가 | `FileTests/writeFileProgress()` |
| progress가 CancellationError → writeFile이 CancellationError | `FileTests/writeFileProgressCancellation()` |
| times → 재마운트 후 100 ns 정밀도로 같음 | `FileTests/writeFileTimes()` |
| 같은 경로 두 번 → alreadyExists | `FileTests/writeFileTwiceThrows()` |
| "한글 파일.txt" → 재마운트 후 같은 문자열 | `FileTests/writeFileKoreanName()` (바이트 비교), NFC 정규화는 `FileTests/namesAreStoredInNFC()` |
| writeFile(contents: []) → size 0 | `FileTests/writeEmptyContents()` |
| copyTree: 픽스처 복사, 재마운트 후 전체 트리(이름·종류·크기·내용·수정 시각) 같음 | `CopyTreeTests/copyTreeRoundTrip()` |
| summary가 원본 집계와 같음 | `CopyTreeTests/copyTreeSummaryMatchesSource()`, `CopyTreeTests/copyTreeRoundTrip()` |
| 심볼릭 링크 → unsupportedFileType | `CopyTreeTests/copyTreeRejectsSymlink()` |
| FIFO → unsupportedFileType | `CopyTreeTests/copyTreeRejectsFIFO()` |
| 방금 포맷한 볼륨의 contentsOfDirectory("/") == [] | `DirectoryTests/freshVolumeRootIsEmpty()` |
| 파일 경로에 contentsOfDirectory → notADirectory | `DirectoryTests/contentsOfFileThrows()` |
| 크기 N 파일에서 readFile(at: N) == 0 | `FileTests/readFileAtEndReturnsZero()` |
| 디렉터리에 readFile → isADirectory | `FileTests/readFileOnDirectoryThrows()` |
| close() 두 번 → 두 번째는 아무 일도 하지 않음 | `DirectoryTests/closeTwice()` |
| close() 후 contentsOfDirectory("/") → volumeClosed | `DirectoryTests/useAfterClose()` |
| §10 opt-in (a) FSKit 교차 검증 | `IntegrationTests/fskitReadsCopiedTree()` |
| §10 opt-in (b) 4 GiB 초과 | `IntegrationTests/fileLargerThan4GiB()` (NTFSVolume와 FSKit 양쪽에서 크기와 4 GiB 경계 앞뒤 표식 확인) |

ensure에 없는 테스트도 있다. 반복 포맷(`formatManyTimesInOneProcess`), 부트 섹터 필드(`formatWritesBootSectorGeometry`), B+트리가 된 디렉터리에서의 대소문자 충돌(`caseCollisionInLargeDirectory`), 시각 매핑(`copyTreeMapsHostTimes`), README SYNOPSIS(`readmeSynopsis`) 등이다.

## 크기 추정

### 공식

C = 클러스터 크기, R = 4096(MFT 레코드 상한), B = 4096(인덱스 블록 상한)이다. mkntfs는 MFT 레코드를 max(1024, 섹터), 인덱스 블록을 max(4096, 섹터)로 잡는다. 추정 함수는 섹터 크기를 모르므로 둘 다 4096으로 잡았다.

```
fixed = Σ_파일 roundUp(size, C)                       // 데이터. MFT 안에 들어가는 작은 파일도 1클러스터로 센다
      + (파일 수 + 디렉터리 수) × R + 16 × R            // MFT. ntfs-3g는 MFT를 16레코드씩 늘린다
      + Σ_비어 있지 않은 디렉터리 roundUp(3 × Σ entry + B, max(C, B))
                                                        // entry = roundUp(16 + 66 + 2 × NFC 이름 UTF-16 길이, 8)
      + 1 MiB + 8 × C                                   // 빈 볼륨 메타데이터 ($LogFile·$Bitmap 제외)
      + C                                               // 백업 부트 섹터
      + 4 MiB + 데이터 / 512                            // 여유분
V = roundUp(fixed, 1 MiB)
반복: V' = roundUp(fixed + logFile(V) + bitmap(V), 1 MiB); V' <= V이면 V가 답
logFile(V) = V ≥ 12 GiB ? 64 MiB : max(2 MiB, ceil(V / 200))   // mkntfs_initialize_rl_logfile의 상한. V에 대해 단조 증가
bitmap(V)  = roundUp(roundUp(ceil(V / C / 8), 8), C)
```

### 실측 1: 빈 볼륨 (섹터 512 B, 클러스터 4 KiB)

`used = totalBytes − freeBytes`, `residual = used − $LogFile − $Bitmap 할당량`이다.

| 이미지 크기 | totalBytes | used | residual |
|---|---|---|---|
| 16 MiB | 16,773,120 | 2,560,000 | 458,752 |
| 64 MiB | 67,104,768 | 2,560,000 | 458,752 |
| 200 MiB | 209,711,104 | 2,564,096 | 458,752 |
| 256 MiB | 268,431,360 | 1,806,336 | 458,752 |
| 1 GiB | 1,073,737,728 | 5,857,280 | 458,752 |
| 4 GiB | 4,294,963,200 | 22,061,056 | |
| 8 GiB | 8,589,930,496 | 43,667,456 | |
| 12 GiB | 12,884,897,792 | 65,273,856 | |
| 16 GiB | 17,179,865,088 | 68,091,904 | |
| 64 GiB | 68,719,472,640 | 69,664,768 | 458,752 |

어느 크기에서든 이미지 크기 − totalBytes = 1클러스터였다(백업 부트 섹터).

### 실측 2: 기하 구조별 고정분과 작은 파일 비용 (1 GiB 볼륨, 3바이트 파일 2000개)

| 섹터 / 클러스터 | residual | 파일당 사용량 |
|---|---|---|
| 512 / 512 | 435 KiB | 1290.2 B |
| 512 / 1 KiB | 437 KiB | 1290.2 B |
| 512 / 2 KiB | 442 KiB | 1290.2 B |
| 512 / 4 KiB | 448 KiB | 1290.2 B |
| 512 / 8 KiB | 472 KiB | 1290.2 B |
| 512 / 16 KiB | 528 KiB | 1294.3 B |
| 512 / 32 KiB | 640 KiB | 1294.3 B |
| 512 / 64 KiB | 896 KiB | 1310.7 B |
| 4096 / 4 KiB | 536 KiB | 4433.9 B |
| 4096 / 8 KiB | 552 KiB | 4436.0 B |
| 4096 / 16 KiB | 592 KiB | 4440.1 B |
| 4096 / 32 KiB | 704 KiB | 4440.1 B |
| 4096 / 64 KiB | 896 KiB | 4456.4 B |

공식의 `1 MiB + 8 × C`는 모든 행의 residual보다 크다.

### 실측 3: 항목당 비용 (섹터 512 B, 클러스터 4 KiB, 256 MiB 볼륨, 한 디렉터리에 5000개, 이름 `file-NNNNN.bin`)

| 항목 | 항목당 사용량 |
|---|---|
| 크기 0 / 1 / 100 B 파일 (MFT 레코드 안에 상주) | 1263.2 B |
| 700 B ~ 4096 B 파일 | 5360.8 B |
| 5000 B 파일 | 9456.8 B |
| 빈 디렉터리 (루트에 2000개) | 1263.6 B |
| 디렉터리마다 1바이트 파일 하나 | 1024.0 B |
| 이름 246 UTF-16 유닛, 빈 파일 3000개 | 2383.9 B (인덱스 항목 576 B의 약 2.4배) |
| 1 MiB / 7 MiB+5 / 33 MiB+4097 / 64 MiB 파일 (내용 110,104,582 B) | 전체 오버헤드 57,338 B |

인덱스 항목 비용은 항목 크기의 2.1~2.4배였다. 공식에서는 3배로 잡았다.

### 실측 4: 추정치 대 실제 (테스트 픽스처)

`used`는 copyTree 직후의 totalBytes − freeBytes, `bound`는 content/33 + 96 MiB다.

| 픽스처 | 섹터 | 클러스터 | content | 추정치 | 빈 볼륨 used | 복사 후 used | 남은 공간 | 추정 − content | bound |
|---|---|---|---|---|---|---|---|---|---|
| 빈 디렉터리 | 512 | 4096 | 0 | 8,388,608 | 2,560,000 | 2,560,000 | 5,824,512 | 8,388,608 | 100,663,296 |
| 4 KiB 미만 5000개 | 512 | 4096 | 10,144,740 | 50,331,648 | 2,560,000 | 26,025,984 | 24,301,568 | 40,186,908 | 100,970,712 |
| 1~64 MiB 4개 | 512 | 4096 | 110,104,582 | 118,489,088 | 2,560,000 | 112,721,920 | 5,763,072 | 8,384,506 | 103,999,798 |
| 깊이 20 | 512 | 4096 | 19,000 | 8,388,608 | 2,560,000 | 2,695,168 | 5,689,344 | 8,369,608 | 100,663,871 |
| 한글 이름 | 512 | 4096 | 2,208,900 | 14,680,064 | 2,560,000 | 6,930,432 | 7,745,536 | 12,471,164 | 100,730,232 |
| 4 KiB 미만 5000개 | 512 | 512 | 10,144,740 | 41,943,040 | 2,552,832 | 19,809,792 | 22,132,736 | 31,798,300 | 100,970,712 |
| 4 KiB 미만 5000개 | 4096 | 4096 | 10,144,740 | 50,331,648 | 2,650,112 | 26,394,624 | 23,932,928 | 40,186,908 | 100,970,712 |
| 4 KiB 미만 5000개 | 512 | 65536 | 10,144,740 | 359,661,568 | 2,752,512 | 282,984,448 | 76,611,584 | 349,516,828 | 100,970,712 |

마지막 행(64 KiB 클러스터)은 bound를 넘는다. 작은 파일 5000개가 각각 64 KiB씩 차지하므로 실제 사용량부터 bound보다 크다. 그래서 테스트는 bound 검사를 기본 클러스터(4096)에만 적용하고, 다른 기하 구조에서는 "추정 크기로 성공한다"만 검사한다(`estimatedSizeHoldsForOtherGeometries`). 4 GiB + 1 MiB 파일 하나의 추정도 통합 테스트(`fileLargerThan4GiB`)에서 성공했다.

## 커밋

| 커밋 | 제목 |
|---|---|
| `1e12706` | Add the NTFS3G Swift API core |
| `7840d9a` | Add the volume size estimate and copyTree tests |
| `982e90c` | Store names in Unicode NFC |
| `8aed6c3` | Add opt-in integration tests |
| `cbf1378` | Store the volume label in NFC and reject non-file URLs |
| (이 보고서가 든 커밋) | Add the NTFS3G README, license and report |

모두 `git add -- <NTFS3G 아래 경로>` 뒤 `git commit -- <같은 경로>`로 pathspec을 붙여 커밋했다.
