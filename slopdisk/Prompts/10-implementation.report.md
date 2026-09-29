# 10-implementation 보고서

- 대상 지시서: `Prompts/10-implementation.xml`
- 수행일: 2026-09-30, macOS 26 (arm64), Apple Swift 6.4 (swiftlang-6.4.0.34.1)
- 커밋 (저장소 루트 `SnakeStick/`, `slopdisk/` 경로만 스테이징):
  - `c414079` Implement SlopDisk GPT core library
  - `7487417` Add read-only sdinspect tool
  - `899f392` Add SlopDisk test suite and fix GPT evidence check
  - `6ac4020` Guard sdinspect against overflowing header fields
  - (이 보고서와 README/CLAUDE.md 갱신은 그다음 커밋)

## 0. 수행 중 사용자와 정한 것

지시서에 답이 없어서 AskUserQuestion으로 물은 것과, 지시서 전제가 바뀐 것.

| 항목 | 결정 | 이유 |
|---|---|---|
| commit 뒤 `clear()` 호출 | precondition 트랩 | `clear()`는 SYNOPSIS(D31)에서 `try` 없이 쓰이므로 throw할 수 없다. D8의 `.transactionFinished`를 던질 수 없어서, 조용히 무시하는 대신 트랩한다. commit이 끝난 뒤라 디스크는 안전하다. |
| `SDFileBlockDevice`가 일반 파일이 아닌 경로를 받을 때 | `.invalidArgument` | 실디스크(`/dev/disk4` 등)를 `.file(...)`로 실수로 여는 경로를 막는다. 20의 RP5(SDRawDevice는 일반 파일 거부)와 대칭이다. |
| git 커밋 (D30, F3) | 커밋한다 | 작업 중 사용자가 "중간중간 커밋하라"고 지시했다. 확인해 보니 상위 `SnakeStick/`이 이미 git 저장소가 되어 있었다(F3는 더 이상 사실이 아니다). `git init`은 하지 않았다. 사용자의 다른 작업(`NTFS3G/`, `.gitmodules`, 워크스페이스 파일)은 스테이징하지 않았다. |

## 1. 확인한 것

실제로 실행한 명령과 결과. 경로는 `slopdisk/` 기준.

### macOS

| 명령 | 결과 |
|---|---|
| `swift package clean && swift build` | `Build complete!`. 출력에 warning 0줄. |
| `swift build --build-tests` | `Build complete!`. warning 0줄. |
| `swift test` | `Test run with 122 tests in 18 suites passed`. skip은 `HdiutilAttachTests` 스위트(1개 테스트)뿐이다. (b) 그룹(`ToolCrossCheckTests` 5개, `SDInspectTests.hdiutilFixture`)이 실제로 실행되어 통과했음을 로그의 `passed` 행으로 확인했다. |
| `SLOPDISK_TEST_HDIUTIL_ATTACH=1 swift test --filter HdiutilAttach` | `Test run with 1 test in 1 suite passed`. 두 번 실행했다. |
| `hdiutil info \| grep -c image-path` (attach 테스트 전후) | 전후 모두 8. 8개 모두 시스템 이미지(시뮬레이터 런타임, MetalToolchain, 사용자 다운로드 dmg)이고 테스트가 붙인 이미지는 남지 않았다. |
| `swift run sdinspect --help` | 사용법 출력, exit 0. |
| `hdiutil create -size 8m -layout GPTSPUD -type UDIF /tmp/sd-accept && swift run -q sdinspect /tmp/sd-accept.dmg` | `scheme : GPT (healthy)`, 파티션 1행 `0  40  16343  7.96 MiB  Apple HFS+  -  disk image`, exit 0. 확인 후 `/tmp/sd-accept.dmg`를 지웠다. |
| `swift run -q sdinspect /tmp/does-not-exist` | `sdinspect: /tmp/does-not-exist: open: No such file or directory`, exit 74. |

### Linux (docker)

지시서의 명령 `docker run --rm -v "$PWD":/w -w /w swift:latest swift build && swift test`는 `&&` 뒤의 `swift test`가 호스트에서 돈다. 또 컨테이너가 호스트의 `.build`에 Linux 산출물을 섞는다. 그래서 다음처럼 바꿔 실행했다. 소스는 읽기 전용으로 마운트했고, 빌드와 테스트는 둘 다 컨테이너 안에서 돈다.

```sh
docker pull swift:latest          # Swift version 6.4 (swift-6.4-RELEASE), Target: aarch64-unknown-linux-gnu
docker run --rm -v "$PWD":/w:ro -w /w swift:latest bash -c \
  'swift build --scratch-path /tmp/build; swift build --scratch-path /tmp/build --build-tests; swift test --scratch-path /tmp/build'
```

- 라이브러리·실행 파일 빌드 warning 0, 테스트 빌드 warning 0. 첫 실행 때 Linux에서만 나온 경고 2개(`FileManager.createFile` 반환값 미사용)는 고친 뒤 다시 확인했다.
- `Test run with 122 tests in 18 suites passed`. skip: `ToolCrossCheckTests` 스위트(5), `SDInspectTests.hdiutilFixture`, `HdiutilAttachTests`(1). 즉 (a) 통과, (b)(c) skip.
- sdinspect 바이너리 실행 테스트(`SDInspectTests`)는 Linux에서도 바이너리를 찾아 실행하고 통과했다.

### 구현 중 발견하고 고친 것

- 전부 0인 디스크가 `.gptUnrecoverable`로 판정되었다. LBA 1을 "읽었다"는 것을 "EFI PART 시그니처가 있다"로 취급한 버그였다. 첫 `swift test`에서 23개 이슈로 드러났다. 수정 후 통과 (`899f392`).
- `sdinspect`가 손상 헤더의 `PartitionEntryLBA + 엔트리 섹터 수`를 오버플로 검사 없이 더했다. 코드 리뷰로 찾았고 크래시를 직접 재현하지는 않았다. 오버플로 검사로 바꾸고 회귀 테스트(`garbageHeaderFieldsDoNotCrash`)를 더했다 (`6ac4020`).
- git 인덱스가 `Sources/slopdisk/`(소문자)로 기록되었다. 대소문자를 무시하는 파일시스템에서 대소문자만 바꾼 이름 변경 때문이다. Linux에서 빌드가 깨지는 문제라 첫 커밋을 amend해서 `Sources/SlopDisk/`로 고쳤다. `git show --stat`으로 확인했다. 재발 방지 메모를 CLAUDE.md의 Git 절에 넣었다.

## 2. 확인하지 못한 것

- macOS 13 실기. 라이브러리의 배포 대상은 macOS 13이고 컴파일은 통과했다(`~Copyable` 클로저 인자, typed throws 모두 가용성 에러 없음). 실행은 macOS 26에서만 했다. 테스트 번들은 Swift Testing 요구로 macOS 14 타깃으로 빌드된다.
- Linux x86_64. aarch64 컨테이너에서만 돌렸다.
- Linux에서의 (b)(c). 도구가 없어 설계대로 skip된다.
- 실제 4Kn 디바이스, 실제 USB 매체, Windows·UEFI 펌웨어가 SlopDisk가 쓴 테이블을 읽는지. 4Kn은 파일·메모리 이미지로만 확인했다. `gpt(8)`과 `hdiutil`은 일반 파일을 512바이트 섹터로 읽어서 4Kn 이미지를 교차검증할 수 없다.
- 크래시 주입(T6)은 write 호출 단위로 throw한다. 섹터 중간에서 찢긴 쓰기나 디바이스 캐시의 쓰기 순서 뒤바뀜은 시험하지 않았다.
- `F_FULLFSYNC`가 실제로 캐시를 비우는지. `synchronize()`가 에러 없이 돌아오는 것만 확인했다.
- T14의 FAT32 검증은 `newfs_msdos`와 `fsck_msdos -n`의 종료 코드로만 판정했다.
- F5의 GUID 값(디스크 GUID `FB4AD73B-…`, 파티션 GUID `5C98F85E-…`)을 새로 만든 hdiutil 이미지에서 확인하는 것. `hdiutil create`가 매번 새 GUID를 만든다. 이 값들은 T1에서 골든 바이트로 확인했고, T5에서는 같은 이미지의 `hdiutil imageinfo` partition-UUID와 비교했다.

## 3. ensure / T 목록별 통과 여부

모두 위 `swift test` 실행(macOS)에서 통과했다. (b)(c) 표시가 있는 것 외에는 Linux에서도 통과했다.

### code#api ensure

| ensure | 테스트 | 결과 |
|---|---|---|
| `SDSize.megabytes(400).bytes == 419_430_400` | `SizeTests.binaryUnits` | 통과 |
| description `"400 MiB"`, `"8 GiB"`, `"512 B"`, `"1.5 KiB"` | `SizeTests.descriptions` | 통과 |
| 8 TiB 메모리 디바이스 생성 직후 `allocatedByteCount == 0` | `MemoryBlockDeviceTests.eightTiBDeviceStartsEmpty` | 통과 |
| LBA 0에 한 섹터 쓰면 65536 | `…oneSectorAllocatesOneChunk` | 통과 |
| 안 쓴 LBA는 0 | `…unwrittenSectorsReadAsZero` | 통과 |
| export한 파일을 SDFileBlockDevice로 읽은 바이트 == 원본 | `…exportMatchesContents` | 통과 |
| readWrite 두 번 → 두 번째 `.locked` | `FileBlockDeviceTests.readWriteThenReadWriteIsLocked`, `secondReadWriteOpenIsLocked` | 통과 |
| readOnly 두 번 → 둘 다 성공 | `…sharedReadOnlyOpens` | 통과 |
| readOnly로 열린 동안 readWrite → `.locked` | `…sharedReadOnlyOpens` | 통과 |
| create 대상이 있으면 `.fileExists`, 기존 내용 불변 | `…createDoesNotTouchExistingFile` | 통과 |
| F4 fixture → `.gpt(.healthy)`, 1개, 40~16343, "disk image" | `DiskTests.fixtureOpensHealthy` (골든 바이트로 만든 fixture), `ToolCrossCheckTests.readsHdiutilFixture` (b) | 통과 |
| 주 헤더 512+40 +1 → degraded(`primaryHeaderInvalid(.headerCRC)` 포함), partitions 동일, 바이트 불변 | `DiskTests.damagedPrimaryHeaderIsDegradedAndReadingDoesNotWrite` | 통과 |
| 그 뒤 repair + refresh → healthy | 같은 테스트 | 통과 |
| 양쪽 훼손 → `.gptUnrecoverable`, `ignoringExistingTable: true` → `.none` | `DiskTests.bothHeadersDamagedIsUnrecoverable` | 통과 |
| 16 GiB: EFI 400 MiB → 2048~821247 | `PlacementTests.synopsisLayoutOn16GiB` | 통과 |
| 이어서 8192 MiB → 821248~17598463, "8 GiB" | 같은 테스트 | 통과 |
| 64 MiB(512): 16 MiB + `.remaining` → 34816~131038 | `PlacementTests.remainingOn64MiB512` | 통과 |
| 64 MiB(4096): 첫 begin 256, 둘째 end == N-1-1-4 | `PlacementTests.remainingOn64MiB4096` | 통과 |
| "윈도우설치" 통과, 💾×18 통과, 💾×19 `.labelTooLong` | `TransactionTests.labelLengthIsCountedInUTF16Units`, `LabelTests.hangulAndEmojiLimits` | 통과 |
| commit 없이 끝나면 바이트·partitions 불변 | `TransactionTests.withoutCommitNothingChanges` | 통과 |
| commit 후 addPartition → `.transactionFinished` | `TransactionTests.operationsAfterCommitAreFinished` | 통과 |
| `.mbr` / `.none`에서 clear 없이 add → `.schemeNotGPT` | `TransactionTests.nonGPTRequiresClear` | 통과 |
| `create(.inMemory, .bytes(1_048_577))` → 1_049_088 | `DiskImageTests.createRoundsUpToSectors` | 통과 |
| `.bytes(512 * 67)` → `.diskTooSmall` | `DiskImageTests.createRejectsTooSmall` | 통과 |
| create 직후 `.none`, 비어 있음 | `DiskImageTests.createStartsWithNoTable` | 통과 |
| `open(.inMemory)` → `.invalidArgument` | `DiskImageTests.inMemoryCannotBeOpened` | 통과 |
| 4096 파일 이미지를 `sectorSize: nil`로 open → 4096 | `DiskImageTests.fourKnLayout` | 통과 |

### §10 T1~T14

| T | 테스트 | 결과 |
|---|---|---|
| T1 골든 | `GoldenBytesTests` 9개 (헤더 필드, 헤더 CRC 재계산, 헤더·엔트리 재인코딩 바이트 동일, 엔트리 배열 CRC, 혼합 엔디언 GUID, Apple CHS 보호 MBR), `CRC32Tests.checkValue` (`0xCBF43926`) | 통과 |
| T2 SYNOPSIS | `SynopsisTests.synopsisRuns` (`@testable` 없이 import), `SynopsisTests.readmeMatchesTest` (README 블록과 테스트 본문을 글자 단위 비교) | 통과 |
| T3 gpt 교차검증 (b) | `ToolCrossCheckTests.gptShowSeesSlopDiskTable`: (2048, 32768, 1, C12A7328-…), (34816, 96223, 2, EBD0A0A2-…), `-l`로 "EFI", "WIN11ISO". 추가로 `gptShowSeesNonASCIILabels` | 통과 |
| T4 imageinfo (b) | `ToolCrossCheckTests.imageInfoPartitionUUIDsMatch`: scheme GUID, partition-UUID·start·length·name 일치 | 통과 |
| T5 hdiutil fixture (b) | `ToolCrossCheckTests.readsHdiutilFixture`, `repairedHdiutilFixtureStillReadsInTools` | 통과 |
| T6 크래시 주입 | `DamageTests.crashAtEveryWriteLeavesAReadableTable` (건강한 디스크 / 빈 디스크, 각각 k = 1…5) | 통과 |
| T7 쓰기 순서 | `DamageTests.writeOrder` (512), `writeOrder4Kn` | 통과 |
| T8 결정성 | `DiskImageTests.sameInputsGiveIdenticalBytes` (할당 청크 전체 비교), 대조군 `randomIDsDiffer` | 통과 |
| T9 대용량 | `DiskImageTests.eightTiBDisk`, `ProtectiveMBRTests.sizeClampsAbove2TiB` | 통과 |
| T10 4Kn | `DiskImageTests.fourKnLayout`, `GeometryTests.sector4096`, `ProtectiveMBRTests.fourKnSectorHoldsMBRInFirst512Bytes` | 통과 |
| T11 이미지 확장 | `DamageTests.enlargedImageIsRepairedToNewEnd` | 통과 |
| T12 MBR 인식 | `DamageTests.classicMBRIsRecognizedAndReplaced` (0x0C 1개 → `.mbr`, clear+add+commit → healthy, LBA0 0..<446이 0) | 통과 |
| T13 sdinspect | `SDInspectTests.healthyDegradedAndUnrecoverable` (exit 0/1/2), `hdiutilFixture` (b), 모든 실행 전후 파일 바이트 비교 | 통과 |
| T14 attach (c) | `HdiutilAttachTests.attachedTableFormatsAsFAT32` | `SLOPDISK_TEST_HDIUTIL_ATTACH=1`에서 통과 |

지시서에 없는 추가 테스트: 트랜잭션 세부(명시 시작 LBA, first-fit 빈틈 재사용, 슬롯 128개, 리사이즈, 실패한 commit 뒤 트랜잭션 유지, 디스크에서 읽은 중복 uniqueID), 손상 종류별 판정(하이브리드 MBR, 보호 MBR 누락, 주 엔트리 CRC 불일치, 백업 손상, `.fields`, `.copiesDiffer`, `.invalidEntries`, FAT 슈퍼플로피), 비표준 엔트리 배열(256바이트 × 64개) 읽기, commit 뒤 `clear()` 트랩(exit test), sdinspect 인자 오류·MBR·4Kn·쓰기 API 미사용 소스 검사.

## 4. 지시서와 다르게, 또는 지시서가 정하지 않은 부분을 정해 구현한 것

`<decisions source="planner">`(P1~P10) 자체를 바꾼 것은 없다. 아래는 명세가 비어 있던 곳을 채운 것과, 명세보다 엄격하게 한 것이다.

1. 헤더 `.fields` 판정에 §2 목록 외의 모순 두 가지를 더했다. 하나는 사용 영역이 LBA 0이나 AlternateLBA를 덮는 경우이고, 다른 하나는 엔트리 배열이 자기 헤더(MyLBA)를 덮는 경우다. 둘 다 정상 테이블에서는 나올 수 없다.
2. 보호 MBR(0xEE) 판단에 55 AA 시그니처를 요구한다. §2의 "type 바이트만 본다"는 CHS·LBA 필드를 보지 않는다는 뜻으로 읽었다. GPT 증거(§4-7) 판정에도 같은 규칙을 쓴다. 쓰레기 LBA0가 우연히 0xEE를 가져서 `.none` 대신 `.gptUnrecoverable`이 되는 일을 막는다.
3. 유효한 GPT 뒤에 0xEE가 없는 일반 MBR이 있으면 `.protectiveMBRMissing`과 `.hybridMBR`를 함께 보고한다. `.hybridMBR`의 뜻("0xEE 외 MBR 엔트리 존재, commit/repair 시 사라짐")에 문자 그대로 해당하고, 그 엔트리가 조용히 사라지지 않게 하려는 것이다. README에 적었다.
4. `.invalidEntries`는 §4-6의 두 조건(겹침, 사용 영역 밖) 외에 end < begin인 엔트리와 디스크 끝을 넘는 엔트리에도 붙는다.
5. §7의 쓰기 전 검사에 겹침(`.overlapsExistingPartition`)과 end < begin(`.invalidArgument`)을 더했다. 이 검사가 없으면 `.invalidEntries`인 테이블을 repair할 때 먼저 디스크에 쓰고 나서 재읽기 검증에서 `.verificationFailed`가 난다.
6. primary의 AlternateLBA가 1(자기 자신)이거나 디스크 밖이면 백업을 읽지 않는다. 이때 `.backupHeaderInvalid(.signature)`와 `.backupNotAtEndOfDisk`를 기록한다. 줄어든 이미지에서 범위 밖 읽기 에러로 판정 전체가 실패하지 않게 하려는 것이다.
7. 엔트리 배열은 1 MiB 단위로 스트리밍하며 읽고 CRC를 계산한다. P4의 "개수 임의"를 받아들이면서 메모리 사용이 헤더 값에 끌려가지 않게 하려는 것이다.
8. `addPartition(at:)`의 에러 구분(§6이 겹침과 공간 부족을 가르지 않았다): 시작 LBA가 기존 파티션 안이면 `.overlapsExistingPartition`이다. 시작은 빈 구간에 있는데 크기가 그 구간을 넘으면 `.insufficientSpace`다. `.remaining`이 들어갈 곳이 없을 때 `.insufficientSpace(requested:)`에는 한 섹터 크기를 담는다.
9. `resizePartition`: 다음 파티션과 겹치면 `.overlapsExistingPartition(next)`이고, 다음 파티션 없이 LastUsable을 넘으면 `.insufficientSpace`다. 크기 0은 `.invalidArgument`다.
10. commit이 실패하면(쓰기 도중 I/O 에러 등) 트랜잭션은 열린 채로 남고 disk 상태는 바뀌지 않는다. §6은 "성공하면 finished"만 정했다.
11. `withTransaction`은 디바이스가 128엔트리 GPT를 담을 수 없으면 본문 실행 전에 `.diskTooSmall`을 던진다. `repair()`도 같다.
12. `SDInspection`에 `code#api` 외의 공개 멤버를 더했다: `adoptedCopy`(어느 사본을 채택했는지), `rawSectors`(`--hex`용 LBA0·LBA1·백업 위치 원본 바이트), `MBRReport`(`hasSignature`, 4개 엔트리 원본, `Kind` = protective/hybrid/mbr/missing), `HeaderReport.isUsable`, `entryArraySectorCount`. sdinspect가 이 구조체 하나로 모든 출력을 만들어야 한다는 요구(P6) 때문이다.
13. 섹터 크기 감지는 `SDDiskImage.detectSectorSize(path:)`이다. 공개 API를 늘리지 않으려고 `package` 접근 수준으로 두고 sdinspect만 쓴다.
14. `sdinspect`는 `.invalidArgument`(일반 파일이 아닌 경로 등)를 64로 끝낸다. P9의 74는 I/O 오류용으로 남겼다.
15. `SDFileBlockDevice`는 섹터 크기로 2의 거듭제곱이면서 512 이상인 값을 받는다. 512/4096 제한은 `SDDiskImage`와 GPT 엔진(D5)이 건다.
16. `SDMemoryBlockDevice.chunks`를 internal getter로 열었다. T8의 "모든 할당 청크 비교"와 큰 디바이스 복사에 쓴다.
17. 테스트 헬퍼 `expectError`는 typed-throws 클로저 대신 untyped 클로저를 받는다. 제네릭 헬퍼에 넘긴 클로저의 thrown 타입 추론이 일부 문맥에서 `any Error`로 떨어지는 Swift 6.4의 동작 때문에 택한 회피다. 에러 타입은 런타임에 검사한다. 이 사실은 코드 주석과 CLAUDE.md에 남겼다.

## 5. 20(실디바이스)에 영향을 주는 발견

- 재사용할 수 있는 것:
  - `SDBlockRequest.validate(lba:byteCount:sectorSize:sectorCount:)`: 20 §4의 "공통 헬퍼"에 해당한다.
  - `POSIXIO.readAll` / `writeAll`: pread/pwrite 루프, 짧은 I/O와 EINTR 처리.
  - 테스트 쪽의 `HdiutilAttachTests.attach` / `detachAll(backedBy:)` / `isWholeDiskPath` / `isSliceDevicePath`와 `Tools.run`: RT 테스트의 attach 파싱과 정리에 쓸 수 있다. `detachAll`은 `hdiutil info -plist`에서 자기 이미지 경로에 붙은 디바이스만 떼므로, attach 출력 파싱이 실패해도 정리된다.
  - `RecordingDevice`, `CrashingDevice`, `ReadOnlyDevice` 래퍼.
  - `/usr/sbin/gpt` 교차검증 헬퍼: `ToolCrossCheckTests.gptShow`.
- `SDFileBlockDevice`가 일반 파일만 받으므로, 지금 `sdinspect /dev/rdiskN`은 "not a regular file" 메시지와 함께 exit 64로 끝난다. 이것은 코드에서 따라간 결과다. 안전 규칙 때문에 디바이스 경로로 실행해 보지는 않았고, 거부 동작은 디렉터리 경로로만 테스트했다(`FileBlockDeviceTests.rejectsNonRegularFiles`). 20 §6대로 `/dev/` 경로를 `SDRawDevice(readOnlyPath:)`로 보내면 된다.
- `SDInspectTests.sourceUsesNoWritePath`는 sdinspect 소스에 쓰기 API 토큰(`withTransaction`, `repair(`, `commit(`, `.readWrite`, `SDDisk(`, `SDDiskImage.open`, `writeSectors` 등)이 없는지 검사한다. 20에서 sdinspect를 고칠 때 이 목록과 충돌하는지 확인해야 한다. `SDRawDevice(readOnlyPath:)`는 걸리지 않는다.
- `SDInspection.read`는 섹터 크기가 2의 거듭제곱이면서 512 이상인지만 검사한다. RP6(512/4096만)은 SDRawDevice 쪽에서 따로 검사해야 한다.
- `SDDisk.write`는 쓰기 순서(D11)대로 `synchronize()`를 두 번 부르고, 재읽기 검증은 같은 디바이스로 한다. 디바이스 쪽 읽기 캐시가 있으면 재읽기 검증이 캐시를 볼 수 있다. rdisk(raw)를 권장하는 20의 제약과 맞다.
- 참고 (코드 밖의 사실): 이 작업 중 저장소 루트 `Prompts/00-metainit.xml`이 갱신되었다. 거기 적힌 SnakeStick 결정 3에는 "SnakeStick은 `SDRawDevice`를 쓰지 않는다"(2026-09-30 사용자 확정)고 되어 있다. 같은 파일의 `<slopdisk-requirements>` R1~R7은 이 작업에서 대조하지 않았다. 루트 쪽 작업의 범위다. 20을 진행할지는 사용자가 판단할 일이라 여기 적어 둔다.
