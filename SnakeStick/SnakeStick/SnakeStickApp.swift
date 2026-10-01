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
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("SnakeStick", id: "main") {
            ContentView(model: appDelegate.model)
                .background(WindowAccessor { appDelegate.guardMainWindow($0) })
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .appInfo) {
                AboutCommand()
            }
        }

        Window("Log", id: LogView.windowID) {
            LogView(model: appDelegate.model)
        }

        Window("About SnakeStick", id: AboutView.windowID) {
            // Not reopened at the next launch. `.restorationBehavior(.disabled)` needs macOS 15;
            // the deployment target is 14 (stage 20, decision 6).
            AboutView()
                .background(WindowAccessor { $0.isRestorable = false })
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
    }
}
