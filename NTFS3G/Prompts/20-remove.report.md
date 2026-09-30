# 20-remove 보고서

`Prompts/20-remove.xml`(NTFS3G: removeItem)의 실행 결과다. 작업일 2026-09-30, 머신은 macOS 26.6.2(25G83), Apple Swift 6.4(swiftlang-6.4.0.34.1), 서브모듈 `Vendor/ntfs-3g`는 태그 `2026.9.28`.

## 요약

- `NTFSVolume.removeItem(_:)`과 `NTFS3GError.directoryNotEmpty(String)`를 추가했다. 구현은 `Sources/NTFS3G/NTFSVolume+Removing.swift`에 있다.
- C2(대소문자 무시)를 지키려면 `ntfs_delete`를 직접 부를 수 없었다. 그래서 C 헬퍼 `cntfs3g_delete_ignoring_case()`를 `Vendor/CNTFS3G/cntfs3g_helpers.c`에 추가했다. 기존 `cntfs3g_lookup_ignoring_case()`와 같은 방식이다. 경로 탐색 헬퍼(`openInode`, `openDirectory`)에도 `ignoringCase` 매개변수를 추가했다.
- C1의 "실패 시에는 호출자가 닫아야 한다"는 `dir.c`와 맞지 않는다. `ntfs_delete`는 실패할 때도 두 inode를 모두 닫는다. 코드는 `dir.c`의 실제 동작을 따른다(아래 "지시서와 다르게 구현한 것").
- 지시서가 정하지 않은 동작 두 가지는 작업 중에 사용자에게 물어서 정했다. 메타데이터 파일을 지우려 하면 EPERM을 던지고, `validatedName`은 쓰지 않는다.
- 새 테스트는 13개다(`RemoveTests` 12개, 통합 테스트 1개). `ReadmeTests/readmeSynopsis()`는 README SYNOPSIS에 맞춰 고쳤다. 서브모듈은 수정하지 않았다.

## 확인한 것

아래는 모두 실제로 실행하고 결과를 본 명령이다. 따로 적지 않으면 `NTFS3G/`에서 실행했다.

| 명령 | 결과 |
|---|---|
| `swift package clean && swift build` | `Build complete!`, 종료 코드 0. 고유 경고 113개는 모두 서브모듈 C 코드에서 나왔다(`ntfsprogs/mkntfs.c` 18개, `libntfs-3g/*.c` 95개). 10단계 보고서의 113개와 같다. NTFS3G가 소유한 파일(`Sources/NTFS3G/*`, `Vendor/CNTFS3G/cntfs3g_helpers.c`, `mkntfs_entry.c`, `include/CNTFS3G.h`)에서 나온 경고는 없다. |
| `swift test` | 종료 코드 0. `Test run with 77 tests in 7 suites passed`(64개 + 새 테스트 13개. 통합 테스트 3개는 skipped로 집계), CNTFS3GTests `1 test passed`. |
| `NTFS3G_INTEGRATION=1 swift test --filter Remove` | 종료 코드 0. `Test run with 13 tests in 2 suites passed`. 통합 테스트 `fileLargerThan4GiBRemoveFreesSpace()`가 실행되어 통과했다(5.1초). |
| 위 실행 전후 `hdiutil info \| grep -c image-path` | 전 8, 후 8 |
| `NTFS3G_INTEGRATION=1 swift test` (전체) | 종료 코드 0. 77개 + 1개 통과. `fskitReadsCopiedTree()`, `fileLargerThan4GiB()`, `fileLargerThan4GiBRemoveFreesSpace()` 모두 통과. 실행 후에도 `hdiutil info \| grep -c image-path`는 8이었고, `NTFS3GTests` 문자열은 0건이었다. |
| `git -C Vendor/ntfs-3g status --short` | 출력 없음 |
| `ls $TMPDIR \| grep -c NTFS3GTests` | 0. 스크래치 디렉터리가 남지 않았다. |

4 GiB 초과 파일 통합 테스트에서 실제로 측정한 값은 다음과 같다(파일 크기 4 GiB + 1 MiB, 클러스터 4096 B).

| 시점 | freeBytes |
|---|---|
| 쓰기 전 | 4,309,364,736 |
| 쓴 뒤 | 13,348,864 |
| removeItem 뒤 | 4,309,364,736 |

차이는 4,296,015,872 B로, 파일 크기를 클러스터 단위로 올린 값과 같다. 테스트는 이 등식과 재마운트 뒤 freeBytes가 그대로인지를 검사한다.

그 밖에 검증 목적으로 실행한 것:

- **C 헬퍼가 필요한지 확인했다.** `cntfs3g_delete_ignoring_case()`에서 `NVolClearCaseSensitive(vol)`를 잠시 뺐더니 `removeIgnoresCase()`와 `removeFromLargeDirectory()`가 `remove /EFI/Boot/BOOTX64.EFI: No such file or directory`로 실패했다. 되돌린 뒤에는 통과했다.
- **AddressSanitizer.** `swift test --sanitize=address --filter RemoveTests`(빌드 디렉터리는 따로 둠)로 12개 모두 통과했고 ASan 보고는 없었다. 테스트 바이너리가 `libclang_rt.asan_osx_dynamic.dylib`에 링크되고 CNTFS3G가 `-fsanitize=address`로 빌드된 것도 확인했다. 다만 ASan으로는 이중 close를 잡을 수 없다. 아래 "확인하지 못한 것"을 본다.

## 확인하지 못한 것

- **이중 close가 없다는 것을 실행으로 증명하지 못했다.** 이 판단은 `dir.c`를 읽은 결과에만 근거한다. ENOTEMPTY 경로에 `ntfs_inode_close`를 두 번 부르는 코드를 일부러 넣고 ASan으로 돌려 봤지만 테스트는 통과했고 보고도 없었다. `ntfs_inode_close()`는 사용자 inode를 해제하지 않고 `nidata_cache`에 넣기 때문이다(`inode.c:516-539`). 넣었던 코드는 커밋 전에 되돌렸다.
- **정확히 일치하는 이름을 먼저 찾는 동작.** 대소문자만 다른 두 항목(`a`와 `A`)이 한 디렉터리에 있을 때 `removeItem("/a")`가 `a`를 지우는지는 테스트하지 못했다. NTFS3G API로는 그런 디렉터리를 만들 수 없다(`alreadyExists`).
- **다른 도구가 만든 볼륨.** Windows가 만든 Win32 + DOS 8.3 이름 쌍이나 하드 링크가 있는 항목은 테스트하지 않았다. NTFS3G가 만드는 이름은 POSIX 네임스페이스 하나뿐이다. `ntfs_delete`는 코드상 DOS/Win32 쌍을 둘 다 지운다(`dir.c` 1994~2000행, 2040~2045행).
- **삭제 뒤 볼륨을 macOS FSKit이나 Windows가 읽는지.** 삭제 뒤의 볼륨은 NTFSVolume으로 다시 마운트해서만 확인했다. FSKit 마운트와 Windows `chkdsk`는 돌리지 않았다.
- **부모 디렉터리의 수정 시각(P4).** libntfs-3g가 `ntfs_inode_update_times(dir_ni, NTFS_UPDATE_MCTIME)`로 갱신하게 두었고, 따로 테스트하지 않았다.
- **release 구성과 Xcode 빌드.** `swift test -c release`와 SnakeStick 워크스페이스의 Xcode 빌드는 돌리지 않았다.

## 멈추고 보고한 지점

작업 중 사용자에게 한 번 물었다(AskUserQuestion, 질문 2개). 두 질문 모두 사용자가 추천안을 골랐다.

1. **메타데이터 파일 삭제.** 지시서는 `/$MFT`나 `/$Extend/$Quota` 같은 경로를 다루지 않았다. `ntfs_delete`는 이런 파일도 막지 않는다. 그대로 두면 볼륨이 깨진다.
   - 제시한 선택지: EPERM으로 거부 / notFound로 숨김 / 새 에러 케이스 / 막지 않음.
   - **사용자 선택: EPERM으로 거부.** 규칙은 ntfs-3g FUSE 드라이버의 `ntfs_fuse_rm()`(`src/ntfs-3g.c:2468-2491`)과 같다. MFT 번호가 16(`FILE_first_user`)보다 작거나 `$Extend` 아래에 있으면 거부한다. 에러는 `.posix(operation: "remove", path:, errno: EPERM)`이고, 새 에러 케이스는 만들지 않았다.
2. **`validatedName` 사용 여부.** P1은 헬퍼 목록에 `validatedName`을 넣었다. 이것으로 이름을 검사하면 `/CON`이나 `/a:b`는 `invalidName`이 된다. 기존 조회(`openChild`)는 이 검사를 하지 않는다.
   - 제시한 선택지: 검사하지 않음 / validatedName 사용.
   - **사용자 선택: 검사하지 않음.** 조회처럼 `NTFSName` 변환만 한다. 그래서 없는 `/CON`은 `notFound`이다. 다른 도구가 만든, Windows가 금지하는 이름의 항목도 지울 수 있다.

## 지시서와 다르게 구현한 것

| 지시서 | 구현 | 이유 |
|---|---|---|
| C1 "실패 시에는 호출자가 닫아야 한다" | `ntfs_delete` 호출 뒤에는 결과와 관계없이 어느 inode도 닫지 않는다. | `ntfs_delete`의 모든 실패 경로가 `err_out:`(`dir.c:2180`)을 거쳐 `out:`(2166행)으로 가고, 거기서 `dir_ni`(2169행)와 `ni`(2171행)를 닫는다. 인자 검사 실패도 마찬가지다. 함수 주석(1896~1899행)에도 "@ni is always closed ... (even if it failed)"라고 적혀 있다. 호출자가 또 닫으면 이중 close가 된다. |
| P1 "`ntfs_delete`를 ... 부른다" | C 헬퍼 `cntfs3g_delete_ignoring_case()`가 볼륨의 `NV_CaseSensitive` 플래그를 한 호출 동안만 끄고 `ntfs_delete(vol, NULL, ni, dir_ni, name, len)`를 부른다. | C2를 지키기 위해서다. `ntfs_delete`는 지울 `$FILE_NAME`을 이름 비교로 고른다. 먼저 정확히 비교하고, 다음에 대소문자를 무시해 다시 비교한다. 그런데 볼륨이 case-sensitive이면(mount 기본값, `volume.c:532`) POSIX 이름은 두 번째 비교에서도 정확히 비교한다(`dir.c:1986-1987`). `ntfs_create`가 만드는 이름은 POSIX다(`dir.c:1698`). 그래서 `BOOTX64.EFI`를 넘기면 ENOENT가 난다(실행으로 확인, "확인한 것" 참조). `pathname`에는 NULL을 넘긴다. 이 인자는 경로 캐시를 무효화하는 데에만 쓰이고, NULL이면 inode 번호로 무효화한다(`dir.c:157-159`). |
| P1 헬퍼 목록의 `validatedName` | 쓰지 않는다. | 멈추고 보고한 지점 2 |
| C2 "기존 조회(`cntfs3g_lookup_ignoring_case`)와 같은 규칙" | 각 경로 구성 요소를 먼저 정확히 찾는다(`ntfs_inode_lookup_by_name`). ENOENT일 때만 `cntfs3g_lookup_ignoring_case`로 다시 찾는다. | 대소문자만 다른 항목이 둘 있으면 `cntfs3g_lookup_ignoring_case`는 B+트리에서 먼저 만나는 쪽을 돌려준다. `$I30` 정렬(`collate.c:229-234`)은 대문자로 바꾼 이름이 같으면 원래 문자 값으로 순서를 정하므로, `A`가 `a`보다 앞선다. 그러면 `a`를 지우라고 했는데 `A`가 지워질 수 있다. `ntfs_delete` 자신도 정확히 비교한 다음에 대소문자를 무시하는 순서를 쓴다. |
| P2 "`ntfs_delete`가 ENOTEMPTY를 돌려주면 매핑, 아니면 `contentsOfDirectory`로 사전 검사" | 매핑만 한다. 사전 검사는 없다. | `ntfs_delete`는 인덱스를 지우기 전에 `ntfs_check_unlinkable_dir()`에서 ENOTEMPTY를 돌려준다(`dir.c:1859`, `1882`). 이때 볼륨은 바뀌지 않는다. `removeNonEmptyDirectoryThrows()`에서 확인했다. |
| `<status>` "테스트 6~8개" | 새 테스트 13개 | ensure 9개에 C2, NFD 철자, B+트리 디렉터리, 메타데이터 거부 테스트를 더했다. |
| `<closing>` "README: API 표와 SYNOPSIS" | 그 밖에 STATUS 표, Behavior(Case, Nothing is overwritten, removeItem 항목), DESIGN NOTES(Case collisions), KNOWN LIMITATIONS도 고쳤다. `NTFSVolume` 클래스 주석도 고쳤다. | 원래 README에 "There is no delete"와 "No delete, ..."가 있었고, 클래스 주석에는 "lookups match names exactly"가 있었다. 고치지 않으면 새 API와 어긋난다. |
| `<closing>` "커밋 1개: `git add -- NTFS3G` 뒤 `git commit ... -- NTFS3G`" | 커밋 3개로 나눴다. 각 커밋은 변경한 파일을 하나하나 pathspec으로 지정했다. | 사용자가 작업 중간중간 커밋하라고 지시했다. 이 작업 중 저장소의 다른 경로(`SnakeStick/`)에 다른 세션의 변경이 있었고, 스테이징된 삭제도 하나 있었다. 이런 것이 섞이지 않게 `NTFS3G` 디렉터리 전체가 아니라 파일 경로를 지정했다. |
| ensure "4 GiB 초과 ... IntegrationTests에서만" + acceptance `--filter Remove` | 통합 테스트 이름을 `fileLargerThan4GiBRemoveFreesSpace()`로 했다. | `swift test --filter`는 대소문자를 구분한다. 처음 붙인 이름 `removeFileLargerThan4GiB()`는 `--filter Remove`에 걸리지 않았다(실행으로 확인). |

지시서가 정하지 않았던 동작을 추가로 정한 것:

- **검사 순서.** 기존 메서드와 같다. `volumeClosed` → `readOnlyVolume` → `invalidPath`(파싱) → `invalidPath("/")` → 이름 변환(`invalidName`) → 메타데이터 검사 → 경로 탐색(`notFound`/`notADirectory`) → 삭제. 그래서 읽기 전용 볼륨에서는 없는 경로도 `readOnlyVolume`이다.
- **메타데이터 검사.** 메타데이터 파일은 `$Extend`를 포함해 모두 루트 디렉터리의 항목이다. 그래서 첫 경로 구성 요소의 MFT 참조 번호만 보고 판정한다(`cntfs3g_is_metadata`). 이 검사는 inode를 열지 않는다. 메타데이터 inode를 두 번째로 여는 일(`$MFT`는 볼륨이 이미 열어 두고 있다)을 피하려는 것이다. 이 검사도 대소문자를 무시하므로 `/$mft`와 `/$extend/$ObjId`도 EPERM이다.
- **`notFound`에 넣는 경로.** 기존 규칙과 같다. 없는 첫 구성 요소까지의 경로를 넣는다(`/missing/x` → `notFound("/missing")`). 에러에 넣는 경로의 철자는 호출자가 쓴 철자를 NFC로 바꾼 것이다. 디스크에 저장된 철자가 아니다.
- **`directoryNotEmpty`의 대상.** 파일이 든 디렉터리뿐 아니라 하위 디렉터리만 든 디렉터리도 `directoryNotEmpty`다.

## 발견한 것 (다음 작업에 참고)

- **removeItem만 대소문자를 무시한다.** `writeFile`, `createDirectory` 등은 부모 경로를 여전히 대소문자를 구분해서 찾는다. 그래서 `removeItem("/EFI/Boot/BOOTX64.EFI")` 다음에 `writeFile("/EFI/Boot/BOOTX64.EFI", from:)`을 부르면 `notFound("/EFI")`가 난다. 디스크에 저장된 철자(`copyTree`가 ISO에서 옮긴 `/efi/boot/...`)로 불러야 한다. `removeIgnoresCase()`가 이 동작을 고정한다. SnakeStick 본편이 경로를 Windows식 대문자로 쓰려면 이 점을 감안해야 한다.
- 인덱스가 B+트리가 된 디렉터리(항목 600개)에서 항목을 모두 지운 뒤, 그 디렉터리를 `removeItem`으로 지울 수 있었다. 원래 걱정한 것은 `ntfs_check_empty_dir()`이다. 이 함수는 `$INDEX_ROOT` 크기만 보고 비었는지 판단하므로, 자식 노드 표시가 남으면 ENOTEMPTY가 날 수 있었다. 실제로는 그렇지 않았다(`removeFromLargeDirectory()`).
- `ntfs_delete`는 링크가 하나뿐인 항목의 마지막 `$FILE_NAME`을 MFT 레코드에 남긴다(복구용, Windows와 같은 동작, `dir.c` 주석). 레코드 자체는 해제된다.
- `swift test --filter`의 정규식은 대소문자를 구분한다.

## ensure → 테스트 대응표

테스트 이름은 `NTFS3GTests` 타깃 기준이다.

| code#api의 ensure | 테스트 |
|---|---|
| writeFile 뒤 removeItem → contentsOfDirectory에 없음, 재마운트 뒤에도 없음 | `RemoveTests/removeFileIsGoneAfterRemount()` |
| removeItem 뒤 같은 경로에 writeFile(from:) 성공, 재마운트 뒤 새 바이트를 읽는다 | `RemoveTests/removeThenWriteFileAtSamePath()` (9 MiB + 1 B를 300,000 B로 교체, 시각도 확인). copyTree로 만든 트리에서 같은 순서를 밟는 것은 `RemoveTests/removeIgnoresCase()`와 `readmeSynopsis()` |
| 빈 디렉터리 → 성공 | `RemoveTests/removeEmptyDirectory()` |
| 파일이 든 디렉터리 → directoryNotEmpty(path) | `RemoveTests/removeNonEmptyDirectoryThrows()` (하위 디렉터리만 든 경우 포함. 실패 뒤 내용이 그대로인지도 확인) |
| 없는 경로 → notFound(path) | `RemoveTests/removeMissingThrowsNotFound()` (`notADirectory` 경우 포함) |
| "/" → invalidPath("/") | `RemoveTests/removeRejectsInvalidPaths(path:)` ("/" 외 6개) |
| readOnly 볼륨 → readOnlyVolume | `RemoveTests/removeOnReadOnlyVolume()` |
| close() 뒤 → volumeClosed | `RemoveTests/removeAfterClose()` |
| 4 GiB 초과 파일: 지운 뒤 freeBytes가 그만큼 는다 (NTFS3G_INTEGRATION=1) | `IntegrationTests/fileLargerThan4GiBRemoveFreesSpace()` |
| C2 `/EFI/Boot/BOOTX64.EFI` → `/efi/boot/bootx64.efi` 삭제 | `RemoveTests/removeIgnoresCase()`, `RemoveTests/removeFromLargeDirectory()` (B+트리 인덱스에서 대소문자를 바꿔 300개 삭제) |

ensure에 없는 테스트:

- `RemoveTests/removeNFDSpelling()`: NFC로 저장된 이름을 NFD 철자로 지운다(P3).
- `RemoveTests/removeMetadataThrows(path:)`: `/$MFT`, `/$mft`, `/$Bitmap`, `/$Extend`, `/$Extend/$Quota`, `/$extend/$ObjId` → EPERM. 그 뒤 볼륨을 다시 마운트해 쓸 수 있는지도 확인한다.
- `RemoveTests/removeFromLargeDirectory()`: 비운 B+트리 디렉터리를 지운다.

## 커밋

| 커밋 | 제목 |
|---|---|
| `a780895` | Add NTFSVolume.removeItem |
| `77eb72e` | Document NTFSVolume.removeItem in the README |
| (이 보고서가 든 커밋) | Add the NTFS3G stage 20 report |

모두 `git add -- <NTFS3G 아래 파일 경로>` 뒤 `git commit -m ... -- <같은 경로>`로 커밋했다. `Co-Authored-By` 트레일러는 없다.
