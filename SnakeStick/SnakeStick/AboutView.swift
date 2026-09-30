// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI

/// "About SnakeStick" (Figma `08 정보 (About)`): the app, its license notice, and the free
/// software it is built on.
struct AboutView: View {
    static let windowID = "about"
    static let sourceURL = URL(string: "https://github.com/team-unstablers/SnakeStick")!

    struct Credit: Identifiable {
        let name: String
        let license: LocalizedStringKey
        let note: LocalizedStringKey?
        let url: URL
        var id: String { name }
    }

    static let credits = [
        Credit(name: "ntfs-3g", license: "GNU GPL v2 or later", note: nil, url: URL(string: "https://github.com/tuxera/ntfs-3g")!),
        Credit(name: "uefi-ntfs", license: "GNU GPL v2", note: nil, url: URL(string: "https://github.com/pbatard/uefi-ntfs")!),
        Credit(name: "wimlib", license: "GNU GPL v3 or later", note: nil, url: URL(string: "https://github.com/ebiggers/wimlib")!),
        Credit(name: "Rufus", license: "GNU GPL v3", note: "Its source code was used as a reference", url: URL(string: "https://github.com/pbatard/rufus")!),
    ]

    @State private var showsLicense = false

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 4) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 96, height: 96)
                    .padding(.bottom, 8)
                Text("SnakeStick")
                    .font(.system(size: 15, weight: .bold))
                Text("Version \(Self.info("CFBundleShortVersionString")) (\(Self.info("CFBundleVersion")))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 8) {
                Text("This software is open source software licensed under the GPLv3.\nThis software comes with no warranty.")
                Text("This software was written by an LLM-based coding agent under human supervision.")
                Text("This software was made possible by the free software below.\nThank you for making such great software!")
            }
            .font(.callout)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)

            GroupBox {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(Self.credits.enumerated()), id: \.element.id) { index, credit in
                        if index > 0 {
                            Divider()
                                .padding(.vertical, 4)
                        }
                        CreditRow(credit: credit)
                    }
                }
                .padding(4)
            }

            HStack(spacing: 12) {
                Link("Source Code", destination: Self.sourceURL)
                    .buttonStyle(.bordered)
                Button("Full License Text…") { showsLicense = true }
            }

            Text(Self.info("NSHumanReadableCopyright"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 20)
        .frame(width: 437)
        .fixedSize(horizontal: false, vertical: true)
        .sheet(isPresented: $showsLicense) {
            LicenseSheet()
        }
    }

    static func info(_ key: String) -> String {
        Bundle.main.object(forInfoDictionaryKey: key) as? String ?? ""
    }
}

/// One entry of the credits (Figma `Credit Row`).
private struct CreditRow: View {
    let credit: AboutView.Credit

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Text(credit.name)
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(credit.license)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let note = credit.note {
                Text(note)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Link(credit.url.host().map { $0 + credit.url.path() } ?? credit.url.absoluteString, destination: credit.url)
                .font(.subheadline)
                .focusEffectDisabled()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// "Full License Text…": the GPLv3 (the repository's `COPYING`, bundled with the app).
private struct LicenseSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .trailing, spacing: 12) {
            ScrollView {
                Text(Self.text)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(.rect(cornerRadius: 6))
            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding()
        .frame(width: 560, height: 480)
    }

    static let text: String = {
        guard let url = Bundle.main.url(forResource: "COPYING", withExtension: nil),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else {
            return "GNU General Public License, version 3: https://www.gnu.org/licenses/gpl-3.0.html"
        }
        return text
    }()
}

/// Replaces the standard "About SnakeStick" menu item so that it opens ``AboutView``.
struct AboutCommand: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("About SnakeStick") {
            openWindow(id: AboutView.windowID)
        }
    }
}
