// SPDX-License-Identifier: LGPL-2.1-or-later

import Foundation

/// One image of a WIM file, as described by the WIM's XML metadata.
///
/// The values are copied out of the ``WIMFile`` when ``WIMFile/images`` is read, so an image
/// stays valid after the file is closed. Properties missing from the XML, and numeric
/// properties that are not decimal integers, are `nil`. For properties not listed here, use
/// ``WIMFile/property(_:ofImage:)``.
public struct WIMImage: Sendable, Equatable {
    /// The 1-based index of the image in the WIM file.
    public let index: Int

    /// `NAME`.
    public let name: String?

    /// `DESCRIPTION`.
    public let description: String?

    /// `DISPLAYNAME`.
    public let displayName: String?

    /// `WINDOWS/ARCH`.
    public let architecture: WIMArchitecture?

    /// `WINDOWS/VERSION/MAJOR`.
    public let major: Int?

    /// `WINDOWS/VERSION/MINOR`.
    public let minor: Int?

    /// `WINDOWS/VERSION/BUILD`.
    public let build: Int?

    init(index: Int, property: (String) -> String?) {
        self.index = index
        name = property("NAME")
        description = property("DESCRIPTION")
        displayName = property("DISPLAYNAME")
        architecture = property("WINDOWS/ARCH").flatMap(Int.init).map(WIMArchitecture.init(code:))
        major = property("WINDOWS/VERSION/MAJOR").flatMap(Int.init)
        minor = property("WINDOWS/VERSION/MINOR").flatMap(Int.init)
        build = property("WINDOWS/VERSION/BUILD").flatMap(Int.init)
    }
}

/// The processor architecture in an image's `WINDOWS/ARCH` property.
public enum WIMArchitecture: Sendable, Equatable {
    case x86
    case arm
    case x64
    case arm64
    /// Any other value of `WINDOWS/ARCH`.
    case other(Int)

    /// Maps a `WINDOWS/ARCH` value (`PROCESSOR_ARCHITECTURE_*`) to an architecture.
    public init(code: Int) {
        switch code {
        case 0: self = .x86
        case 5: self = .arm
        case 9: self = .x64
        case 12: self = .arm64
        default: self = .other(code)
        }
    }

    /// The `WINDOWS/ARCH` value.
    public var code: Int {
        switch self {
        case .x86: 0
        case .arm: 5
        case .x64: 9
        case .arm64: 12
        case .other(let code): code
        }
    }
}

/// One image for ``WIMFile/create(images:to:compression:)``: a host directory captured as the
/// image's root, its `NAME`, and further XML properties.
public struct WIMImageSource: Sendable {
    public var directory: URL
    public var name: String
    /// Keys in the syntax of ``WIMFile/property(_:ofImage:)``, such as `WINDOWS/ARCH`.
    public var properties: [String: String]

    public init(directory: URL, name: String, properties: [String: String] = [:]) {
        self.directory = directory
        self.name = name
        self.properties = properties
    }
}

/// The compression format of the resources in a WIM file written by ``WIMFile/create(images:to:compression:)``.
public enum WIMCompression: Sendable {
    case none
    case xpress
    case lzx
}
