// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// "Show Log…": every `.log` event of the current job, in a monospaced font (§14).
struct LogView: View {
    static let windowID = "log"
    let model: InstallerViewModel

    var body: some View {
        ScrollView {
            Text(model.log.isEmpty ? String(localized: "No log yet.") : model.log.joined(separator: "\n"))
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .frame(minWidth: 560, minHeight: 360)
    }
}
