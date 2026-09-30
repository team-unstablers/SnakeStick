# 20-raw-device 보고서

- 대상 지시서: `Prompts/20-raw-device.xml`
- 수행일: 2026-09-30, macOS 26 (Darwin 25.6.0, arm64), Apple Swift 6.4
- 선행 조건: `Prompts/10-implementation.report.md` 있음. 10의 이름·시그니처(`SDBlockDevice`, `SDOpenMode`, `SDError`, `SDBlockRequest.validate`, `POSIXIO`)는 지시서와 같았다.
- 커밋 (저장소 루트 `SnakeStick/`, `slopdisk/` 경로만 스테이징):
  - `ca42444` Add the SDRawDevice backend for disk device nodes
  - `a20bd9c` Let sdinspect inspect disk devices read-only
  - `c2eb956` Add SDRawDevice tests on attached images
  - `66ed13e` Settle SDRawDevice sync and descriptor ownership edge cases
  - (이 보고서와 README/CLAUDE.md 갱신은 그다음 커밋)

## 0. 수행 중 사용자와 정한 것

| 항목 | 결정 | 이유 |
|---|---|---|
| git 커밋 (D30, closing) | 커밋한다 | 이번 실행에서 사용자가 "작업 중간중간 커밋하라"고 지시했다. `SnakeStick/`은 git 저장소다. 10과 같은 방식이다. |
| `/dev/diskN`의 `synchronize()` | macOS에서 블록 디바이스(`S_ISBLK`)면 `fsync`를 먼저 하고 `DKIOCSYNCHRONIZECACHE`를 부른다. 회귀 테스트로 고정한다. | 실측(§1-3): `/dev/diskN`에 `pwrite` 후 `DKIOCSYNCHRONIZECACHE`만으로는 백킹 이미지에 바이트가 닿지 않았고 `fsync` 뒤에 닿았다. 지시서 절차만 따르면 `/dev/diskN`에서 D11의 "백업 → sync → 주" 순서가 보장되지 않는다. |
| 읽기 전용 디바이스의 `synchronize()` | 아무것도 하지 않는다 | 실측(§1-3): O_RDONLY fd에서 `DKIOCSYNCHRONIZECACHE`가 EACCES다. 그대로 두면 `SDRawDevice(readOnlyPath:)`에 `synchronize()`를 부른 호출자가 `.io`를 받는다. 쓴 것이 없으니 비울 것도 없다. |
| `init(fileDescriptor:closeOnDeinit: true, ...)`가 실패할 때 | fd를 닫는다 | 소유권은 호출 시점에 넘어간 것으로 본다. `closeOnDeinit: false`면 실패해도 fd를 건드리지 않는다(잠그지도 닫지도 않는다). README와 init 문서 주석에 적었다. |

## 1. 확인한 것

실제로 실행한 명령과 결과. 경로는 `slopdisk/` 기준. 아래 1-1, 1-2는 마지막 커밋(`66ed13e`) 소스로 다시 실행한 결과다.

### 1-1. macOS acceptance

| 명령 | 결과 |
|---|---|
| `swift package clean && swift build` | `Build complete!`. 출력에 warning 0줄. |
| `swift build --build-tests` | `Build complete!`. warning 0줄. |
| `swift test` | `Test run with 140 tests in 20 suites passed`. skip은 `HdiutilAttachTests`, `RawDeviceAttachTests` 두 스위트뿐이다(환경변수 없음). 항상 도는 `RawDeviceTests`(7개)와 `SDInspectTests.devicePathsRejectSectorSize`는 실행되어 통과했다. |
| `SLOPDISK_TEST_HDIUTIL_ATTACH=1 swift test --filter RawDevice` | `Test run with 17 tests in 2 suites passed` (`RawDeviceTests` 7, `RawDeviceAttachTests` 10). 작업 중 같은 명령을 여러 번 실행했고 모두 통과했다. |
| `SLOPDISK_TEST_HDIUTIL_ATTACH=1 swift test` | `Test run with 140 tests in 20 suites passed`. skip 없음(10의 `HdiutilAttachTests` 포함). |
| `hdiutil info \| grep -c image-path` (attach 실행 전후) | 전후 모두 8. `hdiutil info \| grep image-path \| grep -c SlopDiskTests` → 0. 8개는 시뮬레이터 런타임 5개, MetalToolchain 2개, 사용자 다운로드 dmg 1개다. 이 문서의 모든 attach 실행과 스크래치 실험 뒤에도 8이었다. |
| `grep -rn "dataLossRisk" Sources/` | `SDRawDevice.swift:19`(타입 문서 주석)과 `SDRawDevice.swift:34`(`case dataLossRisk`) 두 줄뿐. sdinspect에는 없다. 쓰기 가능한 공개 열기는 `init(path:acknowledging:)`와 `init(fileDescriptor:closeOnDeinit:acknowledging:)` 둘이고 둘 다 토큰을 받는다. |

### 1-2. Linux (docker)

지시서의 명령(`docker run --rm -v "$PWD":/w -w /w swift:latest swift build`)은 호스트의 `.build`에 Linux 산출물을 섞는다. 10과 같이 읽기 전용 마운트와 별도 scratch path로 바꿔 실행했다.

```sh
docker run --rm -v "$PWD":/w:ro -w /w swift:latest bash -c \
  'swift build --scratch-path /tmp/build; swift build --scratch-path /tmp/build --build-tests; swift test --scratch-path /tmp/build'
```

- `Swift version 6.4 (swift-6.4-RELEASE)`, `Target: aarch64-unknown-linux-gnu`.
- `CSlopDiskShim` 타깃이 컴파일되었다(빌드 로그 `[28 / 41] CSlopDiskShim`). 즉 Linux 분기의 `<linux/fs.h>`, `BLKSSZGET`, `BLKGETSIZE64`가 컨테이너 헤더에 있고 컴파일된다(F12의 "헤더에 있다"는 부분).
- 빌드·테스트 빌드 exit 0, 로그 전체에 warning 0줄.
- `Test run with 140 tests in 20 suites passed`. skip: `ToolCrossCheckTests`, `HdiutilAttachTests`, `RawDeviceAttachTests`. `RawDeviceTests`(일반 파일·디렉터리·fd 거부 경로)는 Linux에서도 실행되어 통과했다.

### 1-3. 스크래치 이미지로 실측한 사실

세션 스크래치 디렉터리에 `mkfile -n 64m`으로 만든 빈 이미지를 `hdiutil attach -nomount -imagekey diskimage-class=CRawDiskImage`로 붙이고, attach 출력 1행의 경로를 `^/dev/disk[0-9]+$`로 확인한 뒤에만 썼다. 매번 detach했고 이미지를 지웠다.

- flock (python3 `fcntl.flock`): `/dev/rdiskN`, `/dev/diskN` 모두 O_RDWR+`LOCK_EX`, O_RDONLY+`LOCK_SH`가 성공했고, 두 번째 열기의 `LOCK_EX|LOCK_NB`는 EAGAIN이었다. 따라서 §2의 "flock이 디바이스 노드에서 ENOTSUP" 우려는 hdiutil 디바이스에서는 일어나지 않았다. `/dev/rdiskN`에 `LOCK_EX`를 건 채로 `/dev/diskN`에 `LOCK_EX`를 걸면 성공한다. 두 노드의 잠금은 서로 독립이다(README에 적었다).
- 정렬 (python3 `os.pread`, `/dev/rdiskN`과 `/dev/rdiskNs1`): (오프셋 0, 길이 512)와 (512, 1024)는 성공, (1, 512)·(0, 100)·(256, 512)는 EINVAL.
- 버퍼 주소 정렬: 바운스 버퍼를 우회해 호출자 버퍼(1바이트 어긋남)로 직접 `pread`/`pwrite`하도록 임시로 바꾸자 `largeMisalignedTransfers`와 `bufferedBlockDeviceRoundTrip`이 통과했다. hdiutil 디바이스는 버퍼 주소 정렬을 요구하지 않는다. 변경은 되돌렸다. RP4의 바운스 버퍼는 그대로 두었다(§2 참고).
- ioctl (clang으로 빌드한 C 프로브): `DKIOCGETBLOCKSIZE` → 512, `DKIOCGETBLOCKCOUNT` → 131072 (rdisk, disk 둘 다, O_RDONLY/O_RDWR 둘 다). `DKIOCSYNCHRONIZECACHE`는 O_RDWR에서 0(성공), O_RDONLY에서 -1/EACCES. 즉 커밋 경로는 fsync 폴백이 아니라 ioctl로 끝난다.
- 쓰기가 백킹 이미지에 닿는 시점 (C 프로브, 1 MiB 오프셋에 4 KiB 쓰고 이미지 파일을 `pread`로 확인):

  | 노드 | pwrite 직후 | `DKIOCSYNCHRONIZECACHE` 후 | `fsync` 후 | close 후 |
  |---|---|---|---|---|
  | `/dev/disk23` | 없음 | 없음 | 있음 | 있음 |
  | `/dev/rdisk23` | 있음 | 있음 | 있음 | 있음 |

- 슬라이스: 빈 이미지를 붙인 뒤 `/dev/rdiskN`에 GPT를 쓰고 닫으면 `/dev/diskNs1`이 생기고 `hdiutil info -plist`의 `system-entities`에도 나타났다. RT7도 같은 방법(SlopDisk commit → 해제 → `hdiutil info` 폴링)으로 `s2`를 얻었다. RT7 전체 실행 시간은 약 0.6초였다.
- 자동 마운트: `-nomount`로 붙인 이미지에서 GPT를 쓴 뒤, 그리고 `newfs_msdos -F 32`로 슬라이스를 포맷한 뒤 약 6초 동안 `mount` 출력에 해당 디스크가 나타나지 않았다.
- 빈 이미지의 attach 출력은 `/dev/disk23` 한 칸짜리 행 하나다(스킴 칸이 비어 있다). 기존 `HdiutilAttachTests.attach` 파서가 그대로 처리한다.

### 1-4. 테스트가 결함을 잡는지 (의도적 변형)

소스를 임시로 망가뜨려 해당 테스트가 실패하는지 확인하고 되돌렸다. 되돌린 뒤 `git diff`가 비어 있음을 확인했다.

| 변형 | 결과 |
|---|---|
| 빌린 fd(`closeOnDeinit: false`)에도 flock을 건다 | RT3 `writeRoundTripByInjectedDescriptor`가 `Caught error: .locked(path: "/dev/rdisk23")`로 실패 |
| `/dev/diskN`의 fsync 선행을 뺀다 | `bufferedBlockDeviceSynchronizeReachesImage` 실패. `bufferedBlockDeviceRoundTrip`은 통과(close가 버퍼를 비우므로 왕복 테스트로는 구별되지 않는다) |
| 소유 fd의 init 실패 시 close를 뺀다 | `ownedDescriptorIsClosedWhenRejected` 실패 |
| 바운스 버퍼를 우회한다 | 관련 테스트 모두 통과 (1-3의 버퍼 주소 정렬 항목) |

## 2. 확인하지 못한 것

- **Linux 실디바이스.** loop 디바이스는 root가 필요하다. shim의 Linux 분기(`BLKSSZGET`, `BLKGETSIZE64` ÷ 섹터 크기, `fsync`)는 컴파일만 확인했고 실행하지 않았다. `BLKGETSIZE64`가 바이트라는 점은 코드 주석과 나눗셈으로만 반영되어 있다.
- **4Kn 디바이스 (F13).** hdiutil 디바이스는 512만 보고한다. 4096 섹터 디바이스에서의 지오메트리·바운스 버퍼 정렬은 실행하지 않았다.
- **RP6 거부 경로.** 512/4096이 아닌 섹터 크기를 보고하는 디바이스를 만들 방법이 없어 `.invalidArgument`를 실행으로 확인하지 못했다.
- **실제 USB 매체.** ioctl 값, `DKIOCSYNCHRONIZECACHE`가 실제로 드라이브 캐시를 비우는지, 버퍼 주소 정렬 요구(hdiutil 디바이스는 요구하지 않았다), `-nomount` 없이 붙은 실 디스크에서 DiskArbitration의 자동 마운트 여부, 커밋 후 슬라이스가 생기는 시점. 전부 hdiutil 디바이스에서만 확인했다.
- **권한 상승 경로.** `authopen`이나 XPC 헬퍼가 넘긴 fd로 `init(fileDescriptor:...)`를 쓰는 경우. 테스트는 사용자 소유 rdisk를 직접 연 fd로만 했다.
- **ioctl 실패 경로.** `DKIOCGETBLOCKSIZE`/`DKIOCGETBLOCKCOUNT`가 실패하는 디바이스, `flock`이 EWOULDBLOCK 이외의 이유로 실패하는 경우(`.io`), `sd_synchronize_cache`의 ENOTTY/ENOTSUP 폴백, `posix_memalign` 실패, EINTR. 안전 규칙상 attach한 이미지 외의 디바이스 노드를 열 수 없어 재현하지 못했다.
- **소유 fd의 init이 flock 이후 단계에서 실패하는 경우.** 이때 close가 잠금까지 푸는 경로는 코드로만 따라갔다. 일반 파일로 테스트한 경로는 flock 이전(fstat 타입 검사)에서 실패한다.
- **macOS 13 실기, Linux x86_64.** 10과 같다.

## 3. ensure / RT 목록별 통과 여부

모두 1-1의 macOS 실행에서 통과했다. "항상"은 환경변수 없이도 돌고 Linux에서도 통과한 테스트다.

### code#api ensure

| ensure | 테스트 | 결과 |
|---|---|---|
| 일반 파일 경로 → `.invalidArgument` | `RawDeviceTests.regularFileIsRejected` (항상; readOnlyPath·path+토큰 둘 다, 파일 바이트 불변, 이후 read-write 열기 가능), RT5 | 통과 |
| attach한 64 MiB 이미지의 `/dev/rdiskN` → `sectorSize == 512`, `sectorCount == 131072` | RT1 `readOnlyOpen`, RT2, RT3 | 통과 |
| readOnlyPath로 연 디바이스에 write → `.readOnly`, 디바이스 바이트 불변 | RT1: 쓰기 전후 LBA 0~63을 디바이스로 읽어 비교, detach 뒤 이미지 파일 64 MiB가 전부 0 | 통과 |
| 같은 rdiskN을 path init으로 두 번 열면 두 번째가 `.locked` | RT4 `locking` | 통과 |
| `closeOnDeinit: false` 인스턴스 해제 뒤 `fcntl(fd, F_GETFD) != -1` | RT3 | 통과 |

### §7 RT1~RT7 (`RawDeviceAttachTests`, `.serialized`, `SLOPDISK_TEST_HDIUTIL_ATTACH=1`)

| RT | 테스트 | 확인 내용 | 결과 |
|---|---|---|---|
| RT1 | `readOnlyOpen` | path, 512, 131072, `isReadOnly`, write → `.readOnly`, 바이트 불변, `SDDisk` → `.none`, `synchronize()`가 에러 없이 끝남, detach 뒤 이미지가 여전히 전부 0 | 통과 |
| RT2 | `writeRoundTripByPath` | `SDRawDevice(path:acknowledging:)` → `SDDisk`(`.none`) → clear, 16 MiB EFI, `.remaining` Basic Data → commit → `.gpt(.healthy)`. detach 뒤 `SDDiskImage.open(.file, .readOnly)`: healthy, partitions 동일, 라벨 `["EFI", "WIN11ISO"]`. `gpt -r show`의 "GPT part" 행 == 10의 T3 기대값 (2048/32768/1/C12A7328-…, 34816/96223/2/EBD0A0A2-…) | 통과 |
| RT3 | `writeRoundTripByInjectedDescriptor` | 테스트가 `open(2)`로 연 O_RDWR fd, `closeOnDeinit: false`. `path == nil`. 인스턴스가 살아 있는 동안에도 path+토큰 열기가 성공(빌린 fd에 잠금 없음). RT2와 같은 왕복과 교차검증. 해제 뒤 `F_GETFD != -1`, path+토큰 열기 다시 성공, 테스트가 `close(fd) == 0` | 통과 |
| RT4 | `locking` | path+토큰 두 번 → 두 번째 `.locked(path:)`, 쓰기 중 readOnlyPath도 `.locked`. 추가: readOnlyPath 둘은 공존하고 그동안 path+토큰은 `.locked`. `closeOnDeinit: true` fd는 살아 있는 동안 잠그고 해제되면 풀린다 | 통과 |
| RT5 | `regularFileIsRejected` | attach된 이미지의 백킹 파일 경로 → readOnlyPath·path+토큰 모두 `.invalidArgument` | 통과 |
| RT6 | `sdinspectReadsDevice` | `sdinspect /dev/rdiskN` → exit 0, "GPT (healthy)", "sector size : 512   sectors: 131072", "WIN11ISO". `--hex` → exit 0, "\|EFI PART". `--sector-size 512 /dev/rdiskN` → exit 64. 추가: 쓰기 중인 디바이스 → exit 74, "locked by another process". detach 뒤 이미지 바이트가 실행 전과 같다 | 통과 |
| RT7 | `fat32OnSliceAfterRawWrite` | SDRawDevice로 T3 레이아웃 commit → 해제 → `hdiutil info`에 `/dev/diskNs2`가 나타날 때까지 폴링(최대 10초) → `newfs_msdos -F 32 -v WIN11ISO /dev/rdiskNs2` exit 0, `fsck_msdos -n` exit 0. detach 뒤 테이블 healthy, partitions 동일 | 통과 |

### 지시서에 없는 추가 테스트

| 테스트 | 내용 |
|---|---|
| `RawDeviceTests.directoryIsRejected` (항상) | 디렉터리 → `.invalidArgument` |
| `RawDeviceTests.missingPathIsIOError` (항상) | 없는 경로 → `.io(operation: "open", errno: ENOENT)` |
| `RawDeviceTests.borrowedDescriptorStaysOpenWhenRejected` (항상) | 일반 파일 fd, `closeOnDeinit: false` → `.invalidArgument`, fd가 같은 파일을 가리킨 채 열려 있고 잠기지 않음 |
| `RawDeviceTests.ownedDescriptorIsClosedWhenRejected` (항상) | 일반 파일 fd, `closeOnDeinit: true` → `.invalidArgument`, fd가 닫힘. 병렬 테스트가 fd 번호를 재사용할 수 있어 `F_GETFD` 대신 `fstat`의 (st_dev, st_ino)가 바뀌었는지로 판정 |
| `RawDeviceTests.writeOnlyDescriptorIsRejected` (항상) | O_WRONLY fd → `.invalidArgument` |
| `RawDeviceTests.invalidDescriptorIsIOError` (항상) | fd -1 → `.io(operation: "fcntl(F_GETFL)", errno: EBADF)` |
| `SDInspectTests.devicePathsRejectSectorSize` (항상) | 존재하지 않는 `/dev/slopdisk-test-missing-<UUID>`: `--sector-size`와 함께 → 64, 단독 → 74 ("open: No such file or directory"). 아무것도 열리지 않는다 |
| `SDInspectTests.sourceUsesNoWritePath` (기존, 확장) | 금지 토큰에 `dataLossRisk`, `SDRawDevice(path:`, `fileDescriptor:` 추가 |
| `RawDeviceAttachTests.largeMisalignedTransfers` | 2.5 MiB + 3섹터(바운스 버퍼 3회, 마지막은 부분)를 1바이트 어긋난 버퍼로 쓰고 읽어 비교, detach 뒤 이미지 파일에서도 비교. 범위 밖 읽기·섹터 배수가 아닌 쓰기 → `.invalidArgument` |
| `RawDeviceAttachTests.bufferedBlockDeviceRoundTrip` | `/dev/diskN`으로 RT2와 같은 왕복과 교차검증 |
| `RawDeviceAttachTests.bufferedBlockDeviceSynchronizeReachesImage` | `/dev/diskN`에 쓰고 `synchronize()` 직후(닫기 전) 이미지 파일에 바이트가 있음. §0의 fsync 선행 회귀 테스트 |

## 4. 플래너 결정과 다르게, 또는 지시서가 정하지 않은 부분을 정해 구현한 것

RP1~RP6와 R1·R2는 그대로 따랐다. §0의 세 항목(사용자 확인) 외에 아래를 정했다.

1. **fd init에도 RP5 타입 검사를 한다.** 지시서 requirements는 경로 init에만 fstat을 적었다. RP5는 "대상"이라고만 해서 fd init에도 적용했다. 일반 파일 fd → `.invalidArgument`.
2. **O_WRONLY fd는 `.invalidArgument`.** 지시서는 F_GETFL의 접근 모드로 isReadOnly를 정하라고만 했다. SDDisk가 쓴 것을 다시 읽어 검증하므로 쓰기 전용 fd는 받지 않는다. `F_GETFL` 실패는 `.io(operation: "fcntl(F_GETFL)")`.
3. **fd init의 `.locked(path:)`.** path가 nil이라 `"file descriptor N"` 문자열을 넣는다.
4. **`.io`의 operation 이름.** `"ioctl(DKIOCGETBLOCKSIZE)"`, `"ioctl(DKIOCGETBLOCKCOUNT)"`, `"ioctl(DKIOCSYNCHRONIZECACHE)"` (Linux는 `"ioctl(BLKSSZGET)"`, `"ioctl(BLKGETSIZE64)"`, `"fsync"`), `"fcntl(F_GETFL)"`, `"posix_memalign"`.
5. **off_t 오버플로 검사.** `sectorCount × sectorSize`가 `Int64.max`를 넘으면 `.invalidArgument`.
6. **바운스 버퍼는 디바이스마다 init 때 한 번 1 MiB를 할당한다.** 정렬은 `max(sectorSize, getpagesize())`, deinit에서 `free`. 호출마다 할당하지 않는다. 모든 I/O가 이 버퍼를 거친다(RP4). 1-3에서 hdiutil 디바이스는 버퍼 주소 정렬을 요구하지 않았지만, 실 USB 드라이버와 4Kn에서 확인하지 못했으므로(§2) RP4대로 유지했다.
7. **ENOTSUP과 EOPNOTSUPP를 둘 다 폴백 조건으로 본다.** macOS에서 둘은 값이 다르다(45, 102). ENOTTY도 포함(지시서대로).
8. **shim의 errno 보정.** ioctl이 실패했는데 errno가 0이면 EIO를 돌려준다(반환값 0이 성공과 겹치지 않게). Linux에서 `BLKSSZGET` 결과가 0 이하면 EINVAL.
9. **`internal import CSlopDiskShim`.** C 모듈이 SlopDisk의 공개 인터페이스로 새지 않게 했다.
10. **sdinspect.** `/dev/` 접두어 판정(`Arguments.isDevicePath`)과 `--sector-size` 충돌 검사를 인자 파서에 두었다. 사용법 문구에 디바이스 형식을 추가했다(출력 형식과 종료 코드는 10 §9 그대로). `.locked`는 기존 매핑대로 74, 지원하지 않는 섹터 크기(`.invalidArgument`)는 10의 결정 14대로 64다.
11. **RT6의 준비.** "GPT (healthy)"를 보려면 테이블이 있어야 해서, 공통 준비(빈 이미지) 대신 `makeT3Image`로 T3 테이블을 쓴 이미지를 붙였다. 바이트 비교의 "전"은 attach 뒤, sdinspect 실행 전에 읽은 이미지 파일이다.
12. **RT5를 항상 도는 테스트로도 두었다.** 디바이스가 필요 없는 검사라 `RawDeviceTests.regularFileIsRejected`로 Linux에서도 돈다. 지시서의 RT5는 opt-in 스위트에 그대로 있다(attach된 이미지의 백킹 파일 대상).
13. **RT7의 슬라이스 경로.** attach 시점에는 빈 이미지라 attach 출력에 슬라이스가 없다. attach 출력의 `/dev/diskN`에 `s2`를 붙여 `^/dev/r?disk[0-9]+s[0-9]+$`로 검사하고, `hdiutil info`가 이 테스트의 이미지 아래에 그 슬라이스를 보여 줄 때만 쓴다(`AttachedImage.rawSlice`). CLAUDE.md 안전 규칙에 이 파생 규칙을 적었다.
14. **테스트 헬퍼 정리.** `writeT3Layout(_:)`(기존 `makeT3Image`가 사용), `ToolCrossCheckTests.t3Rows`(T3 기대 행 공유), `HdiutilAttachTests.deviceEntries(backedBy:)`(`detachAll`과 `rawSlice`가 공유), `expectInvalidArgument`.
15. **Linux 확인 명령.** 1-2에 적은 대로 읽기 전용 마운트 형태로 바꿨다.

## 5. SnakeStick(루트 `Prompts/00-metainit.xml`)에 영향을 주는 발견

- R8(SDRawDevice)은 이 단계로 채워졌다. 10 보고서 §5 마지막 항목의 "SnakeStick은 `SDRawDevice`를 쓰지 않는다"는 루트 커밋 `83daeef`(결정 13)로 더 이상 사실이 아니다.
- R9 / U13 앞부분: hdiutil 디바이스에서는 SDRawDevice로 commit하고 해제하면 슬라이스가 생기고 `hdiutil info`에 나타났다(RT7). `-nomount`로 붙인 이미지에서는 GPT 쓰기 뒤와 `newfs_msdos` 뒤 약 6초 동안 자동 마운트가 없었다. 실 USB에서의 DiskArbitration 동작은 확인하지 못했다(Q7).
- U11 관련: macOS raw 노드(`/dev/rdiskN`, `/dev/rdiskNs1`)는 오프셋·길이가 섹터 정렬이 아니면 EINVAL이고, 버퍼 주소 정렬은 요구하지 않았다(hdiutil 디바이스 기준). libntfs-3g unix_io가 문제될 수 있는 것은 오프셋·길이 쪽이다.
- U12 관련: 디바이스 노드에서 `flock`은 동작했다. libntfs-3g가 쓰는 `fcntl` 레코드 잠금과 문자 디바이스의 `O_EXCL`은 시험하지 않았다.
- SlopDisk의 flock은 같은 노드를 여는 SlopDisk끼리만 막는다. `/dev/diskN`과 `/dev/rdiskN`은 서로의 잠금을 보지 못하고, `newfs_msdos`·mkntfs 같은 도구는 잠금을 걸지 않는다. 디바이스 단위 배타는 SnakeStick 쪽(DiskArbitration claim 등)에서 해야 한다.
- 버퍼드 노드(`/dev/diskN`, `/dev/diskNsK`)는 `fsync` 전까지 쓰기가 디바이스에 닿지 않았다(1-3 표). 다른 도구에 슬라이스를 넘길 때도 rdisk 쪽을 쓰는 편이 동기화 의미가 단순하다.
