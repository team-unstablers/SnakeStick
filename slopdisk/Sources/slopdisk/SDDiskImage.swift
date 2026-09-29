//
//  SDDiskImage.swift
//  slopdisk
//
//  Created by Gyuhwan Park on 9/30/26.
//

import Foundation

enum SDDiskImageSource {
    /// A disk image backed by a file on disk.
    case file(URL)
    /// malloc-backed disk image, which is not backed by a file on disk.
    case inMemory
}

protocol SDDiskImage: SDDisk {
    
}

extension SDDiskImage {
    static func create(_ source: SDDiskImageSource, desiredSize size: Int) -> SDDiskImage {
    }
}
