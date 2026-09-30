//
//  SnakeStickApp.swift
//  SnakeStick
//
//  Created by Gyuhwan Park on 9/30/26.
//
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

@main
struct SnakeStickApp: App {
    @State private var model = InstallerViewModel()

    var body: some Scene {
        Window("SnakeStick", id: "main") {
            ContentView(model: model)
        }
        .windowResizability(.contentSize)

        Window("Log", id: LogView.windowID) {
            LogView(model: model)
        }
    }
}
