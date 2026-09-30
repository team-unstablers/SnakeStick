// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation
import NTFS3G
import Testing

/// The README's SYNOPSIS, with a small tree standing in for the mounted ISO.
@Test func readmeSynopsis() throws {
    let scratch = try ScratchDirectory()
    defer { scratch.remove() }
    let source = scratch.url.appendingPathComponent("iso", isDirectory: true)
    try Fixtures.makeDirectory(source.path)
    try Fixtures.makeDirectory(source.path + "/sources")
    try Fixtures.makeDirectory(source.path + "/efi")
    try Fixtures.makeDirectory(source.path + "/efi/boot")
    try Fixtures.makeFile(source.path + "/setup.exe", pattern(count: 4000))
    try Fixtures.makeFile(source.path + "/sources/install.wim", pattern(count: 3 << 20))
    try Fixtures.makeFile(source.path + "/efi/boot/bootx64.efi", pattern(count: 2000, seed: 1))
    let replacement = pattern(count: 2500, seed: 2)
    let replacementSource = scratch.path("bootx64.efi")
    try Fixtures.makeFile(replacementSource, replacement)
    let image = scratch.path("windows-data.img")

    let size = try NTFSVolume.estimatedVolumeSize(forTreeAt: source)
    FileManager.default.createFile(atPath: image, contents: nil)
    let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: image))
    try handle.truncate(atOffset: UInt64(size))
    try handle.close()

    try NTFSVolume.format(path: image, options: .init(label: "WIN11", partitionStartSector: 2048))

    let volume = try NTFSVolume(path: image, mode: .readWrite)
    var lastProgress: NTFSCopyProgress?
    let summary = try volume.copyTree(from: source) { progress in
        lastProgress = progress
    }

    try volume.removeItem("/efi/boot/bootx64.efi")
    try volume.writeFile("/efi/boot/bootx64.efi", from: URL(fileURLWithPath: replacementSource))
    try volume.close()
    #expect(summary == NTFSCopySummary(files: 3, directories: 3, bytes: 4000 + (3 << 20) + 2000))
    #expect(lastProgress?.completedBytes == lastProgress?.totalBytes)

    let check = try NTFSVolume(path: image, mode: .readOnly)
    defer { try? check.close() }
    #expect(check.label == "WIN11")
    #expect(try check.contentsOfDirectory("/") == [
        .init(name: "efi", kind: .directory),
        .init(name: "setup.exe", kind: .file),
        .init(name: "sources", kind: .directory),
    ])
    #expect(try check.attributesOfItem("/sources/install.wim").size == 3 << 20)
    #expect(try check.readAll("/efi/boot/bootx64.efi") == replacement)
}
