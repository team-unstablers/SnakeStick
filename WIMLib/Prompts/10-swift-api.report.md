# 10-swift-api 보고서

`Prompts/10-swift-api.xml`(WIMLib: wimlib 위의 Swift API)의 실행 결과다. 작업일 2026-09-30, 머신은 macOS 26.6.2(25G83, arm64), Apple Swift 6.4(swiftlang-6.4.0.34.1), MacOSX27.0 SDK.

## 요약

- 서브모듈(`Vendor/wimlib`, `v1.14.5`), 생성한 `config.h`, C 타깃 `CWIMLib`, Swift 타깃 `WIMLib`, 테스트 두 타깃, README·CLAUDE.md·LICENSE를 만들었다. 공개 API는 `code#api`를 따르되 아래 "지시서와 다르게 구현한 것"의 여섯 군데가 다르다.
- 작업 중 멈추고 사용자에게 여섯 번 물었다(AskUserQuestion). 그중 네 개는 지시서의 전제가 wimlib의 실제 코드·문서와 어긋난 것이다(경로 대소문자, 디렉터리 추출 방식, 라이선스, `WIMImage.property`). 모두 사용자가 고른 대로 구현했다.
- 서브모듈은 수정하지 않았다. 빌드 우회는 `Package.swift`의 컴파일 플래그 하나(`-fno-modules`)다.
- **본편(`Prompts/10-implementation.xml`)에 영향을 주는 것이 있다.** 특히 §9가 전제한 추출 결과 경로(`tmp/wim/bootmgfw_EX.efi`)가 실제와 다르고(`tmp/wim/EFI_EX/bootmgfw_EX.efi`), 결정 22·README의 라이선스 표기(LGPLv3+)가 틀렸다. 맨 아래 "SnakeStick 본편에 영향을 주는 발견"에 정리했다.

## 확인한 것

아래는 모두 실제로 실행해서 결과를 본 명령이다. 따로 적지 않으면 `WIMLib/`에서 실행했다.

| 명령 | 결과 |
|---|---|
| `swift package clean && swift build` | `Build complete!` (종료 코드 0). 경고 168줄(고유 151개)은 모두 서브모듈 C 코드 29개 파일에서 나온 `-Wshorten-64-to-32`다(SwiftPM이 켜는 경고). WIMLib이 소유한 파일(`Sources/`, `Vendor/CWIMLib/`, `Tests/`)의 경고는 0개다. |
| `swift test` | 종료 코드 0. `Test run with 34 tests in 4 suites passed` (WIMLibTests, 매개변수 테스트는 1개로 센다) + `Test run with 1 test in 0 suites passed` (CWIMLibTests 스모크 테스트). 건너뛴 테스트 없음. |
| `swift test -c release` | 종료 코드 0. 34개 + 1개 통과. WIMLib 소유 파일 경고 0개. |
| 위 실행 전후 `find $TMPDIR -maxdepth 1 -name 'WIMLibTests-*'` | 전후 모두 0개. 스크래치 디렉터리가 남지 않았다. |
| 위 실행 전후 `hdiutil info \| grep -c image-path` | 전후 모두 8 (사용자가 원래 붙여 둔 이미지). 이 패키지의 테스트는 hdiutil을 쓰지 않는다. |
| `git -C Vendor/wimlib status --short` | 출력 없음 |
| `git -C Vendor/wimlib describe --tags` | `v1.14.5` (커밋 `cd5e231c`) |
| `nm -gU .build/out/Products/{Debug,Release}/libWIMLib.a`에서 `_wimlib_`·`_$s`·`_swift_` 접두어 밖의 전역 심볼 | 두 구성 모두 0개 (C3). |
| `nm -gU .build/out/Products/{Debug,Release}/CWIMLib.o` | 두 구성 모두 전역 심볼 72개, 전부 `_wimlib_*`. `nm -m`에서 `non-external (was a private external)` 1039개(debug)·1056개(release). |
| 저장소 루트에서 이 작업의 각 커밋에 `git show --stat --format= <커밋>` | 모든 커밋이 `WIMLib/`와 `.gitmodules`만 건드린다. `Co-Authored-By` 트레일러 없음. |
| C 컴파일 인자 파일(`.build/out/Intermediates.noindex/WIMLib.build/{Debug,Release}/CWIMLib-t.build/Objects-normal/arm64/*-common-args.resp`) | debug: `-O0 -DDEBUG=1`, release: `-Os`, 나머지(`-DHAVE_CONFIG_H -DBUILDING_WIMLIB -D_LARGEFILE_SOURCE -D_FILE_OFFSET_BITS=64 -D_GNU_SOURCE -fvisibility=hidden -fno-common -fno-modules`)는 같다. 두 구성 모두 `NDEBUG`가 없다. |

그 밖에 검증 목적으로 실행한 것:

- **P4 (DEBUG 매크로).** `grep -rn "ifdef DEBUG\|if DEBUG\|ifndef NDEBUG" Vendor/wimlib/src Vendor/wimlib/include`와 `grep -rnw DEBUG src include` 모두 결과가 없다. wimlib은 `DEBUG`에 반응하지 않으므로 `override/config.h`를 만들지 않았다. wimlib의 `wimlib_assert`는 `assert()`이고(`include/wimlib/assert.h`), SwiftPM은 두 구성 모두 `NDEBUG`를 정의하지 않으므로 debug와 release 모두 assert가 켜져 있다(upstream autotools 빌드와 같다). C2의 대조군인 release 테스트도 통과했다.
- **대소문자 테스트가 헛돌지 않는지.** `WIMLibGlobal`의 init 플래그를 잠시 `0`으로 바꾸면 `ExtractTests/pathSpellings(path:)`의 `"/DIR/A.BIN"`, `"Dir\A.bin"` 두 경우가 `wimlib error 49: The path does not exist in the WIM image`로 실패했고, 되돌리면 통과했다.
- **`-fno-common`이 실제로 이기는지.** SwiftPM은 cc1에 `-fcommon`을 넘긴다(첫 빌드 실패 로그의 cc1 명령줄). `-fno-common`을 넣은 뒤 오브젝트 파일 64개에서 `nm`의 `C`(common) 심볼이 0개였다.
- **로컬 패키지 의존으로 쓸 수 있는지.** 스크래치 디렉터리에 `.package(path: "…/WIMLib")`에 의존하는 실행 파일 패키지를 만들어 `swift run`했다. `unsafeFlags`를 거부하지 않고 빌드됐고 `1.14.5`를 출력했다. 링크된 실행 파일의 전역 심볼은 `_main`, `__mh_execute_header`, `_wimlib_*` 72개, Swift 심볼뿐이었다. 스크래치 패키지는 지웠다.
- **NTFS3G와의 심볼 충돌.** `NTFS3G/.build/out/Products/Debug/CNTFS3G.o`(기존 빌드 산출물, 읽기만 했다)의 전역 심볼 376개와 wimlib의 내부 심볼(지금은 local) 1039개의 교집합은 0개였다.

## 확인하지 못한 것

- **실제 Windows ISO의 `boot.wim`.** 모든 테스트는 wimlib이 쓴 WIM으로만 했다. Microsoft 도구가 만든 WIM(LZX 32 KiB 청크, 실제 XML)을 읽는 것은 wimlib의 일상적인 쓰임이지만 여기서 확인하지 않았다. `Windows/Boot/Fonts_EX` 안의 실제 파일 이름도 확인하지 않았다(README 예시는 `Fonts_EX/...`로만 적었다).
- **Xcode 빌드.** SnakeStick 워크스페이스에서 Xcode로 빌드하지 않았다. Xcode가 패키지의 C 타깃을 SwiftPM처럼 한 오브젝트로 prelink하는지(C3의 근거), `unsafeFlags`를 받아들이는지는 SwiftPM(swiftbuild 백엔드)에서만 확인했다.
- **x86_64·유니버설 빌드.** arm64에서만 빌드했다. `config.h`의 `HAVE_*`는 아키텍처와 무관해 보이지만 확인하지 않았다.
- **솔리드(LZMS) 리소스, 분할 WIM, 4 GiB 초과 파일.** 테스트하지 않았다. `create`는 LZMS·솔리드를 쓰지 않는다.
- **여러 `WIMFile`을 여러 스레드에서 동시에 쓰는 경우.** wimlib 문서가 허용하는 사용이지만 테스트하지 않았다. Swift Testing의 병렬 실행으로 여러 인스턴스가 동시에 돈 것이 전부다.
- **SPDX 교체 전후의 법적 판단.** 라이선스는 wimlib의 `COPYING`을 읽고 사용자가 고른 대로 적었다. 법률 검토는 하지 않았다.

## 멈추고 보고한 지점

작업 중 사용자에게 여섯 번 물었다(AskUserQuestion). 모두 추천안이 선택됐다. 여섯 번째 질문은 사용자의 요청으로 한 번 더 물었고 답은 같았다.

1. **경로 대소문자.** objective는 "wimlib의 규칙(`/` 구분, 대소문자 무시)"이라고 했지만, wimlib은 UNIX에서 기본이 대소문자 구분이다(`src/dentry.c:600` `default_ignore_case = false`, `include/wimlib.h`의 `WIMLIB_INIT_FLAG_DEFAULT_CASE_SENSITIVE` 설명 "default on UNIX-like systems"). P5가 적은 `WIMLIB_INIT_FLAG_DEFAULT`라는 상수는 없다.
   - **선택: 대소문자 무시.** `wimlib_global_init(WIMLIB_INIT_FLAG_DEFAULT_CASE_INSENSITIVE)`.
2. **디렉터리 추출.** P6와 ensure는 `extract(paths: ["/dir"])`가 dir 안의 파일을 대상에 "평평하게" 놓는다고 했지만, wimlib 문서(`WIMLIB_EXTRACT_FLAG_NO_PRESERVE_DIR_STRUCTURE`: "place each extracted file or directory tree directly in the target directory")와 코드(`src/extract.c`의 `build_dentry_list(..., !NO_PRESERVE_DIR_STRUCTURE)`)는 디렉터리를 트리째 `target/dir/…`로 놓는다. Rufus도 추출 뒤 `tmp\EFI_EX\bootmgfw_EX.efi`를 읽는다(pbatard/rufus `src/wue.c` 1374·1391·1404행, 2026-09-30 `gh api`로 확인).
   - **선택: wimlib 동작을 따른다.** ensure를 "`tmp/dir/` 아래에 트리가 놓인다"로 바꿔 테스트했다.
3. **`WIMImage.property(_:)`.** 의사코드는 임의 XML 경로를 `wimlib_get_image_property`로 읽는 메서드를 `WIMImage`에 두었지만, C5는 `WIMImage`를 값을 복사한 `Sendable` 구조체로 만들라고 한다. 복사본에는 `WIMStruct`가 없어 나중에 임의 경로를 물을 수 없다.
   - **선택: `WIMFile`로 옮긴다.** `WIMFile.property(_ name: String, ofImage index: Int) throws -> String?`. `WIMImage`는 고정 필드만 갖는다.
4. **빌드 한계.** SwiftPM(swiftbuild)은 C 타깃을 clang 모듈(`-fmodules`)로 컴파일한다. 그래서 `wim.c`가 `<errno.h>`를 include하는 순간 `Darwin` 모듈 전체가 보이고, `mach/task.h`의 `thread_create()`가 wimlib 내부의 `thread_create()`(`include/wimlib/threads.h:32`)와 충돌해 `conflicting types for 'thread_create'`로 빌드가 실패했다. autotools 빌드에서는 `mach/task.h`가 보이지 않는다.
   - 제시한 선택지: `-fno-modules` / 매크로로 이름 변경 / 서브모듈 포크.
   - **선택: `-fno-modules` 유지.** `Package.swift`에 우회라는 사실과 이유를 주석으로 남겼다.
5. **라이선스.** D1과 P10은 wimlib이 LGPL-3.0-or-later이고 `COPYING.LGPL`이 그 전문이라고 전제했다. 실제 v1.14.5의 `COPYING`은 "wimlib 전체는 GPL-3.0-or-later, libwim은 libntfs-3g 없이 빌드하면 LGPL-2.1-or-later도 선택할 수 있다(듀얼)"이고, `COPYING.LGPL`은 LGPL 2.1 전문이다. 라이브러리 소스 66개가 LGPL-2.1-or-later 헤더, 20개가 MIT 형식 헤더(`divsufsort.c` 등)다. LGPL-3.0 헤더는 없다.
   - 제시한 선택지: LGPL-2.1-or-later / LGPL-3.0-or-later(or-later로 3.0 선택) / wimlib과 같은 듀얼 / GPL-3.0-or-later.
   - **선택: LGPL-2.1-or-later.** 이미 커밋한 11개 파일의 SPDX를 일괄 교체했고, `LICENSE`는 `COPYING.LGPL`을 그대로 복사했다(`cmp`로 동일 확인).
6. **다중 이미지 생성.** 본편 §15(e)는 "WIMLib이 만든 작은 WIM, 이미지 2"를 픽스처로 쓰고 §9는 `extract(…, fromImage: 2, …)`를 부르는데, P8의 `create`는 이미지를 하나만 만든다. 본편은 WIMLib을 수정할 수 없다(결정 22).
   - **선택: 다중 이미지 `create` 추가.** `WIMFile.create(images: [WIMImageSource], to:, compression:)`를 추가하고 P8의 단일 이미지 `create`는 그 위에 얹었다.

## 지시서와 다르게 구현한 것

| 지시서 | 구현 | 이유 |
|---|---|---|
| P5 `wimlib_global_init(WIMLIB_INIT_FLAG_DEFAULT)` | `wimlib_global_init(WIMLIB_INIT_FLAG_DEFAULT_CASE_INSENSITIVE)` | 멈추고 보고한 지점 1 |
| P6, ensure "dir 안의 파일들을 tmp에 평평하게" | `/dir` → `tmp/dir/…` (wimlib·Rufus와 같다) | 멈추고 보고한 지점 2 |
| code#api `WIMImage.property(_:)` | `WIMFile.property(_:ofImage:) throws -> String?` | 멈추고 보고한 지점 3 |
| code#api `public var images: [WIMImage] { get }` | `{ get throws }` | ensure "close() 뒤 images → WIMLibError.closed"를 만족하려면 getter가 던져야 한다. 호출은 `try wim.images`. |
| P8 단일 이미지 `create` | 그대로 두고 `create(images:to:compression:)`와 `WIMImageSource`를 추가 | 멈추고 보고한 지점 6 |
| D1·P10 LGPL-3.0-or-later, `LICENSE` = `COPYING.LGPL`(LGPLv3로 전제) | LGPL-2.1-or-later, `LICENSE` = `COPYING.LGPL`(LGPL 2.1 전문) | 멈추고 보고한 지점 5 |
| P3 cSettings: `HAVE_CONFIG_H`, 헤더 경로, `-std=gnu99 -fno-common -fvisibility=hidden` | 추가로 `.define`: `BUILDING_WIMLIB`, `_LARGEFILE_SOURCE`, `_FILE_OFFSET_BITS=64`, `_GNU_SOURCE`. `-std=gnu99`는 `cLanguageStandard: .gnu99`로. `unsafeFlags`: `-fvisibility=hidden -fno-common -Wno-pointer-sign -fno-modules` | `Makefile.am`의 `AM_CPPFLAGS`·`libwim_la_CFLAGS`·`AM_CFLAGS`에 있는 것이다. `BUILDING_WIMLIB`이 없으면 `WIMLIBAPI`가 비어(`include/wimlib.h` 403~423행) `-fvisibility=hidden` 아래에서 공개 함수까지 숨겨진다(헤더에서 읽은 것이며 빼고 빌드해 보지는 않았다). `-fno-common`은 SwiftPM이 `-fcommon`을 넘기므로 필요하다. `-fno-modules`는 지점 4. |
| P2 서브모듈 안에서 `bootstrap`·`configure` 후 `git clean -fdx` | 서브모듈을 스크래치 디렉터리에 `git clone`해 `v1.14.5`에서 `LIBTOOLIZE=glibtoolize ./bootstrap` + `./configure …`, `config.h`만 복사 | 결과물은 같고 서브모듈이 한 번도 dirty가 되지 않는다. NTFS3G README의 재생성 절차와도 같다. |
| §2 "`WIMLibGlobal.swift`(init 한 번, 직렬화용 락)" | 별도 락 없이 `static let`의 지연 초기화(swift_once)가 `wimlib_global_init`과 `wimlib_set_print_errors`를 한 번 부른다 | wimlib이 "단일 스레드일 때만"이라고 한 전역 함수는 이 둘뿐이고, 둘 다 이 초기화 안에서만 불린다. 다른 호출은 모두 초기화가 끝날 때까지 swift_once에서 기다린다. |
| requirements "(wimlib이 대상 디렉터리를 만들지 않는다)" | 계약(`posix(ENOENT)`)은 그대로 지키고, 그 수단으로 `stat` 사전 검사를 넣었다 | wimlib은 `NO_PRESERVE_DIR_STRUCTURE`일 때 대상을 한 단계 `mkdir`한다(`src/extract.c` `mkdir_if_needed`, 헤더 문서 "The target directory will still be created if it does not already exist"). 전제는 틀렸지만 계약은 명확했으므로 묻지 않았다. |

지시서가 정하지 않았던 동작을 추가로 정한 것:

- `extract`의 대상이 디렉터리가 아니면 `.posix(operation: "extract", path:, errno: ENOTDIR)`, file URL이 아니면 `EINVAL`. `create`의 원본 URL도 file URL이 아니면 `EINVAL`.
- `extract`의 경로는 `\`를 `/`로 바꾸고, 앞의 구분자는 없어도 된다(wimlib이 허용한다). 여러 경로를 한 번에 줄 수 있고, 하나라도 없으면 아무것도 추출하지 않는다(wimlib 동작).
- 이미지 인덱스가 범위 밖(0, 음수, `Int.max` 포함)이면 wimlib에 넘기기 전에 `WIMLIB_ERR_INVALID_IMAGE`로 던진다. `Int32`로 바꿀 때 트랩이 나지 않게 하고, `WIMLIB_ALL_IMAGES`(-1) 같은 특수 값이 해석되지 않게 하려는 것이다. `property(_:ofImage:)`도 같다(wimlib은 범위 밖이면 조용히 NULL을 돌려준다).
- wimlib에 넘기는 문자열(경로, 이미지 이름, 속성 이름·값)에 NUL이 있으면 `WIMLIB_ERR_INVALID_PARAM`. C 문자열로 바꾸면 NUL에서 잘려, 예를 들어 `"/dir\0/a.bin"`이 `/dir` 추출이 된다.
- `create`는 기존 파일을 덮어쓴다(wimlib 동작). 속성은 키 이름순으로 설정한다.
- `WIMImage`는 `Equatable`이고, `WIMArchitecture`에 `init(code:)`와 `code`를 두었다.
- `wimlib_set_print_errors(false)`는 wimlib 기본값도 false지만(`src/error.c:49`) P5대로 부른다.

## SnakeStick 본편에 영향을 주는 발견

본편 `Prompts/10-implementation.xml`이 이 패키지에 대해 전제한 것과 실제를 대조했다. 본편은 WIMLib을 수정하지 않으므로 아래를 그대로 따라야 한다.

### 실제 공개 API

```swift
public final class WIMFile {                                  // non-Sendable
    public let path: String
    public init(path: String) throws
    public func close()                                       // 여러 번 불러도 된다. deinit도 부른다.
    public var images: [WIMImage] { get throws }              // try wim.images
    public func property(_ name: String, ofImage index: Int) throws -> String?
    public func extract(paths: [String], fromImage index: Int, to directory: URL) throws
    public static func create(from directory: URL, to path: String, compression: WIMCompression = .lzx,
                              imageName: String, properties: [String: String] = [:]) throws
    public static func create(images: [WIMImageSource], to path: String,
                              compression: WIMCompression = .lzx) throws
    public static var wimlibVersion: String { get }            // "1.14.5"
}
public struct WIMImage: Sendable, Equatable {
    public let index: Int                                      // 1부터
    public let name: String?, description: String?, displayName: String?
    public let architecture: WIMArchitecture?                  // WINDOWS/ARCH
    public let major: Int?, minor: Int?, build: Int?           // WINDOWS/VERSION/MAJOR|MINOR|BUILD
}
public enum WIMArchitecture: Sendable, Equatable { case x86, arm, x64, arm64, other(Int) }  // init(code:), code
public struct WIMImageSource: Sendable { directory: URL; name: String; properties: [String: String] }
public enum WIMCompression: Sendable { case none, xpress, lzx }
public enum WIMLibError: Error, Equatable, CustomStringConvertible {
    case wimlib(code: Int32, message: String)
    case posix(operation: String, path: String?, errno: Int32)
    case closed
}
```

### 본편 문구와 다른 점

1. **§9의 추출 결과 경로.** 본편은 `extract(paths: ["/Windows/Boot/EFI_EX", "/Windows/Boot/Fonts_EX"], fromImage: 2, to: tmp/wim)` 뒤에 `tmp/wim/bootmgfw_EX.efi`, `bootmgr_EX.efi`를 읽는다고 적었다. 실제 위치는 `tmp/wim/EFI_EX/bootmgfw_EX.efi`, `tmp/wim/EFI_EX/bootmgr_EX.efi`, `tmp/wim/Fonts_EX/<name>_EX.<ext>`다(Rufus와 같다). `ReadmeTests/readmeSynopsis()`와 `CreateTests/twoImages()`가 이 배치를 확인한다.
2. **`images`는 던진다.** `try wim.images`.
3. **대상 디렉터리는 호출자가 만든다.** 없으면 `.posix(operation: "stat", path:, errno: ENOENT)`.
4. **"이미지 2가 없거나 경로가 없으면" 판정(§9).** `WIMLibError.wimlib(code:)`의 코드로 구분한다. 본편은 `CWIMLib`을 import할 수 없으므로 숫자로 비교해야 한다: `WIMLIB_ERR_INVALID_IMAGE` = 18, `WIMLIB_ERR_PATH_DOES_NOT_EXIST` = 49 (`include/wimlib.h`의 `enum wimlib_error_code`). 그 밖에 `WIMLIB_ERR_OPEN` = 47, `WIMLIB_ERR_NOT_A_WIM_FILE` = 43.
5. **§15(e)의 픽스처.** `WIMFile.create(images:to:compression:)`로 이미지 두 개짜리 `boot.wim`을 만들 수 있다. 예: 이미지 1 = 아무 트리, 이미지 2 = `Windows/Boot/EFI_EX/bootmgfw_EX.efi`가 든 트리와 `["WINDOWS/ARCH": "9", "WINDOWS/VERSION/BUILD": "26200"]`. 이미지 이름은 서로 달라야 한다(`WIMLIB_ERR_IMAGE_NAME_COLLISION` = 11).
6. **경로 대소문자.** 대소문자를 무시하므로 `/Windows/Boot/EFI_EX`, `\windows\boot\efi_ex` 모두 된다. 이 설정은 프로세스 전역이며, 프로세스 안에서 WIMLib보다 먼저 wimlib을 부르는 코드가 없어야 한다(있으면 대소문자 구분으로 조용히 바뀐다).
7. **라이선스.** 본편 결정 22의 "wimlib(LGPL-3.0-or-later)"과 README LICENSE 절의 "WIMLib·wimlib LGPLv3+"는 틀렸다. WIMLib은 LGPL-2.1-or-later이고, wimlib은 전체가 GPL-3.0-or-later, libwim은 LGPL-2.1-or-later를 선택할 수 있다(libntfs-3g 없이 빌드할 때). 둘 다 GPLv3인 SnakeStick과 결합할 수 있다.
8. **P6의 다른 속성.** `WINDOWS/EDITIONID`, `WINDOWS/LANGUAGES/DEFAULT` 같은 것은 `property(_:ofImage:)`로 읽는다. 값은 문자열이고, 없으면 nil이다.

### 저장소 루트 문서 (이 작업의 범위 밖이라 고치지 않았다)

- 루트 `CLAUDE.md`의 레이아웃 표가 `WIMLib/`를 "planned", 문서를 `WIMLib/Prompts/10-swift-api.xml`로 적고 있다. 이제 `WIMLib/README.md`, `WIMLib/CLAUDE.md`가 있다.
- 같은 표가 `NTFS3G/CLAUDE.md`를 가리키지만 그 파일은 없다(`ls NTFS3G/CLAUDE.md` → No such file).

## 발견한 것 (다음 작업에 참고)

- SwiftPM(swiftbuild 백엔드)의 C 타깃 컴파일: `-fmodules`, `-fcommon`, 그리고 `-Wshorten-64-to-32` 등 Xcode 기본 경고가 켜진다. debug는 `-O0 -DDEBUG=1`, release는 `-Os`이고 어느 쪽도 `NDEBUG`를 정의하지 않는다.
- SwiftPM은 C 타깃의 오브젝트를 `ld -r`로 한 파일(`Products/<구성>/CWIMLib.o`)로 합친다. 이때 `-fvisibility=hidden`으로 숨긴 심볼이 local이 된다(`nm -m`의 `non-external (was a private external)`). 그래서 정적 링크에서도 내부 심볼이 다른 라이브러리와 충돌하지 않는다. 이 prelink 단계가 없는 보통의 정적 라이브러리(.a 안의 개별 .o)라면 hidden 심볼도 정적 링크 때는 서로 보이므로 `-fvisibility=hidden`만으로는 충돌을 막지 못한다(일반적인 링커 동작이며, 여기서 실험하지는 않았다).
- 지시서 `<acceptance>`의 `grep -v " _wimlib_\| _\$s\| _swift_"`는 큰따옴표 안에서 `\$s`가 `$s`(줄 끝 뒤의 s)가 되어 Swift 심볼을 걸러내지 못한다. 작은따옴표로 쓴다.
- `wimlib_get_image_property`가 돌려주는 문자열은 다음 wimlib 호출까지만 유효하다(헤더 문서). `WIMImage`를 만들 때 속성마다 바로 복사한다.
- wimlib 함수 다수가 내부에서 `wimlib_global_init(0)`을 부른다(`src/wim.c:163,791`, `compress.c:127`, `decompress.c:61`). 한 번 초기화되면 뒤의 `wimlib_global_init(플래그)`는 플래그를 무시하고 0을 돌려준다.
- Swift Testing의 `#expect(throws: E.self) { … }`는 잡은 에러를 돌려준다. `WIMLibError.wimlib`의 코드만 비교할 때 썼다.

## ensure → 테스트 대응표

테스트 이름은 `WIMLibTests` 타깃 기준이다. 픽스처(`TestSupport.swift`의 `Fixture`)는 `/dir/a.bin`(1 MiB + 17 B, SplitMix64 시드 1), `/dir/b.bin`(100 B, 시드 2), `/dir/empty.bin`(0 B)이다.

| code#api의 ensure / 지시서 항목 | 테스트 |
|---|---|
| create(LZX, 파일 3개) → images.count == 1, images[0].name == imageName | `ImageTests/createdWIMHasOneNamedImage()` |
| properties ARCH "9", BUILD "26200" → .x64, 26200 | `ImageTests/propertiesMapToFields()` (MAJOR·MINOR·DESCRIPTION·DISPLAYNAME·EDITIONID도), `ImageTests/architectureCodes(code:architecture:)` (0·5·9·12·6) |
| extract(["/dir/a.bin"]) → tmp/a.bin 바이트 동일, dir/ 없음 | `ExtractTests/extractFile(name:)` (a.bin·b.bin·empty.bin 세 파일 모두) |
| extract(["/dir"]) → (지점 2에 따라 변경) tmp/dir/ 아래에 트리 | `ExtractTests/extractDirectory()`, `ImageTests/compressionFormats(compression:)`에서도 확인 |
| 없는 경로 → WIMLIB_ERR_PATH_DOES_NOT_EXIST | `ExtractTests/missingPathThrowsAndExtractsNothing()` (함께 준 다른 경로도 추출되지 않음) |
| fromImage: 2 (이미지 하나) → WIMLIB_ERR_INVALID_IMAGE | `ExtractTests/missingImageThrows(index:)` (2·0·-1·Int.max) |
| 빈 파일을 열면 throws | `LifecycleTests/openEmptyFileThrows()` |
| close() 두 번 → 두 번째는 아무 일도 하지 않음 | `LifecycleTests/closeTwiceDoesNothing()` |
| close() 뒤 images → WIMLibError.closed | `LifecycleTests/useAfterCloseThrows()` (property·extract도) |
| create → open → extract 20번 반복 | `LifecycleTests/repeatedCreateOpenExtract()` |
| requirements: 열기 실패는 WIMLibError | `LifecycleTests/openMissingFileThrows()` (WIMLIB_ERR_OPEN), `LifecycleTests/openGarbageThrowsNotAWIMFile()` |
| requirements: 대상 디렉터리 없음 → posix(ENOENT) | `ExtractTests/missingTargetDirectoryThrowsENOENT()` (디렉터리가 생기지 않았는지도 확인) |
| §1 스모크: `wimlib_get_version_string()` == "1.14.5" | `CWIMLibTests/versionString()`, `ImageTests/wimlibVersion()` |
| §2 `\` → `/` | `ExtractTests/pathSpellings(path:)` (`/DIR/A.BIN`, `\dir\a.bin`, `Dir\A.bin`, `dir/a.bin`) |
| C5 WIMImage는 값 복사 | `LifecycleTests/imagesOutliveTheFile()` |
| C8 속성 이름 대소문자 구분, 정수 변환 실패는 nil | `ImageTests/propertyNamesAreCaseSensitive()`, `ImageTests/nonIntegerNumbersAreNil()`, `ImageTests/missingPropertiesAreNil()` |
| 지점 3 `property(_:ofImage:)` | `ImageTests/propertiesMapToFields()`, `ImageTests/propertyOfMissingImageThrows()` |
| 지점 6 다중 이미지 create | `CreateTests/twoImages()`, `CreateTests/duplicateImageNamesThrow()`, `CreateTests/noImages()` |

ensure에 없는 테스트도 있다. 압축 형식별 왕복(`ImageTests/compressionFormats(compression:)`: none·xpress·lzx), 여러 경로 추출(`extractSeveralPaths`), 기존 파일 덮어쓰기(`extractReplacesExistingFiles`), 파일을 대상으로 준 경우(`fileAsTargetThrowsENOTDIR`), file URL이 아닌 대상(`nonFileURLThrowsEINVAL`), NUL이 든 경로(`pathWithNULThrows`), 없는 원본으로 create(`createFromMissingDirectoryThrows`), 기존 WIM 덮어쓰기(`CreateTests/existingFileIsReplaced`), 에러 설명(`errorsDescribeThemselves`), README SYNOPSIS(`readmeSynopsis`).

## 커밋

| 커밋 | 제목 |
|---|---|
| `c82ddfe` | Add the WIMLib package scaffold with wimlib v1.14.5 |
| `19cb7a6` | Add the WIMLib Swift API and tests |
| `bd5a3d9` | Add multi-image WIM creation and relicense WIMLib as LGPL-2.1-or-later |
| `3b23299` | Add the WIMLib README, CLAUDE.md and license |
| (이 보고서가 든 커밋) | Add the WIMLib stage 10 report |

`<closing>`은 커밋 세 개(스캐폴드 / API·테스트 / 문서·보고서)를 적었지만, 작업 중간에 사용자 질문으로 생긴 변경(다중 이미지 create, 라이선스 교체)을 따로 커밋해 다섯 개가 됐다. 모두 `git add -- <WIMLib 아래 경로 또는 .gitmodules>` 뒤 `git commit -- <같은 경로>`로 pathspec을 붙여 커밋했다.
