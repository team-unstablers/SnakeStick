// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import IOKit

/// IOKit lookups for `IOMedia` objects by BSD name.
enum IORegistry {
    struct Media {
        var bsdName: String
        var isWhole: Bool
        /// Byte offset within the parent disk (`Base`); 0 for a whole disk.
        var base: UInt64
        var size: UInt64
        var preferredBlockSize: UInt64
        /// The BSD name of the whole disk this media belongs to (itself for a whole disk).
        var wholeDisk: String?
        /// Whether the whole disk sits on a block storage driver (a physical device or a disk
        /// image) rather than being synthesized by a volume manager such as APFS.
        var isSynthesized: Bool
    }

    /// The BSD names of every `IOMedia`, whole disks and partitions.
    static func allMediaBSDNames() -> [String] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOMedia"), &iterator) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }
        var names: [String] = []
        while case let service = IOIteratorNext(iterator), service != 0 {
            if let name = stringProperty(service, "BSD Name") {
                names.append(name)
            }
            IOObjectRelease(service)
        }
        return names
    }

    /// The `IOMedia` with BSD name `bsdName`, or `nil` if there is none (yet).
    static func media(bsdName: String) -> Media? {
        guard let matching = IOBSDNameMatching(kIOMainPortDefault, 0, bsdName) else {
            return nil
        }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != 0 else {
            return nil
        }
        defer { IOObjectRelease(service) }
        guard IOObjectConformsTo(service, "IOMedia") != 0 else {
            return nil
        }
        let isWhole = boolProperty(service, "Whole") ?? false
        let whole = isWhole ? (bsdName, service) : wholeAncestor(of: service)
        var synthesized = false
        if let wholeService = whole?.1 {
            synthesized = !isOnBlockStorageDriver(wholeService)
            if wholeService != service {
                IOObjectRelease(wholeService)
            }
        }
        return Media(
            bsdName: bsdName,
            isWhole: isWhole,
            base: numberProperty(service, "Base") ?? 0,
            size: numberProperty(service, "Size") ?? 0,
            preferredBlockSize: numberProperty(service, "Preferred Block Size") ?? 0,
            wholeDisk: whole?.0,
            isSynthesized: synthesized
        )
    }

    /// The whole disks that `bsdName` depends on: its own whole disk and, through volume managers
    /// such as APFS, the whole disks of the physical stores beneath it. `disk3s1s1` (an APFS
    /// snapshot on the synthesized `disk3`) gives `["disk3", "disk0"]`.
    static func wholeDisksBeneath(bsdName: String) -> Set<String> {
        guard let matching = IOBSDNameMatching(kIOMainPortDefault, 0, bsdName) else {
            return []
        }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != 0 else {
            return []
        }
        var result: Set<String> = []
        var current = service
        // Walk up the service plane; every whole IOMedia on the way is a disk this one lives on.
        for _ in 0 ..< 64 {
            if IOObjectConformsTo(current, "IOMedia") != 0,
               boolProperty(current, "Whole") == true,
               let name = stringProperty(current, "BSD Name") {
                result.insert(name)
            }
            var parent: io_registry_entry_t = 0
            let status = IORegistryEntryGetParentEntry(current, kIOServicePlane, &parent)
            IOObjectRelease(current)
            guard status == KERN_SUCCESS else {
                return result
            }
            current = parent
        }
        IOObjectRelease(current)
        return result
    }

    private static func wholeAncestor(of service: io_registry_entry_t) -> (String, io_registry_entry_t)? {
        IOObjectRetain(service)
        var current = service
        for _ in 0 ..< 16 {
            var parent: io_registry_entry_t = 0
            let status = IORegistryEntryGetParentEntry(current, kIOServicePlane, &parent)
            IOObjectRelease(current)
            guard status == KERN_SUCCESS else {
                return nil
            }
            current = parent
            if IOObjectConformsTo(current, "IOMedia") != 0, boolProperty(current, "Whole") == true,
               let name = stringProperty(current, "BSD Name") {
                return (name, current)
            }
        }
        IOObjectRelease(current)
        return nil
    }

    private static func isOnBlockStorageDriver(_ service: io_registry_entry_t) -> Bool {
        var parent: io_registry_entry_t = 0
        guard IORegistryEntryGetParentEntry(service, kIOServicePlane, &parent) == KERN_SUCCESS else {
            return false
        }
        defer { IOObjectRelease(parent) }
        return IOObjectConformsTo(parent, "IOBlockStorageDriver") != 0
    }

    private static func property(_ service: io_registry_entry_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }

    private static func stringProperty(_ service: io_registry_entry_t, _ key: String) -> String? {
        property(service, key) as? String
    }

    private static func boolProperty(_ service: io_registry_entry_t, _ key: String) -> Bool? {
        (property(service, key) as? NSNumber)?.boolValue
    }

    private static func numberProperty(_ service: io_registry_entry_t, _ key: String) -> UInt64? {
        (property(service, key) as? NSNumber)?.uint64Value
    }
}
