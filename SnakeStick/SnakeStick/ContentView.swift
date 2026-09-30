// SPDX-License-Identifier: GPL-3.0-or-later

import SnakeStickCore
import SwiftUI
import UniformTypeIdentifiers

/// The one window (§14, Figma `SnakeStick — macOS GUI`): source, target and options above the
/// progress panel and the buttons.
struct ContentView: View {
    @Bindable var model: InstallerViewModel
    @Environment(\.openWindow) private var openWindow
    @State private var choosingISO = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 14) {
                SourceSection(model: model, choose: { choosingISO = true })
                TargetSection(model: model)
                OptionsSection(model: model)
            }
            .disabled(model.isBusy)
            ProgressPanel(model: model)
            actions
        }
        .padding(16)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
        .fileImporter(isPresented: $choosingISO, allowedContentTypes: [Self.isoType]) { result in
            if case .success(let url) = result {
                model.chooseISO(url)
            }
        }
        .onOpenURL { url in
            // `open -a SnakeStick some.iso`, or Open With in the Finder.
            if url.isFileURL, url.pathExtension.lowercased() == "iso" {
                model.chooseISO(url)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first, url.pathExtension.lowercased() == "iso" else {
                return false
            }
            model.chooseISO(url)
            return true
        }
        .alert(eraseTitle, isPresented: $model.showsEraseConfirmation) {
            Button("Erase and Write", role: .destructive) { model.confirmErase() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(eraseMessage)
        }
        .alert("Stop writing?", isPresented: $model.showsCancelConfirmation) {
            Button("Keep Writing") {}
                .keyboardShortcut(.defaultAction)
            Button("Stop", role: .destructive) { model.confirmCancel() }
        } message: {
            Text("If you stop now, “\(model.jobDiskModel)” will be left unbootable. To use it, you have to start over.")
        }
        .alert("Allow Full Disk Access for SnakeStick", isPresented: $model.showsFullDiskAccessNotice) {
            Button("Open System Settings") { Self.openFullDiskAccessSettings() }
                .keyboardShortcut(.defaultAction)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("macOS keeps the helper that writes the disk away from removable disks and your folders until SnakeStick has Full Disk Access. Add SnakeStick in System Settings > Privacy & Security > Full Disk Access, then try again.")
        }
        .alert("Allow the SnakeStick helper", isPresented: $model.showsApprovalNotice) {
            Button("Open System Settings") { HelperClient.openLoginItems() }
                .keyboardShortcut(.defaultAction)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("SnakeStick writes disks with a helper that runs as root. Allow it in System Settings > General > Login Items, then try again.")
        }
    }

    static let isoType = UTType("public.iso-image") ?? UTType(filenameExtension: "iso") ?? .diskImage

    /// Opens Privacy & Security > Full Disk Access and shows the app in the Finder, ready to be
    /// dragged into the list. Access granted to the app covers the helper inside its bundle.
    static func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }

    private var eraseTitle: String {
        String(localized: "Erase “\(model.selectedCandidate?.model ?? "")”?")
    }

    private var eraseMessage: String {
        let disk = model.selectedCandidate
        return String(localized: "All partitions and data on \(disk?.bsdName ?? "")(\(UIText.size(disk?.sizeBytes ?? 0))) will be erased and it will be made into a Windows installation disk. This cannot be undone. If you continue, you will be asked for an administrator password once.")
    }

    @ViewBuilder private var actions: some View {
        HStack(spacing: 16) {
            if case .failed = model.stage {
                Button("Show Log…") { openWindow(id: LogView.windowID) }
            }
            Spacer(minLength: 0)
            switch model.stage {
            case .idle:
                Button("Cancel") {}
                    .disabled(true)
                Button("Start Writing") { model.requestStart() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canStart)
            case .starting, .writing:
                Button("Cancel") { model.requestCancel() }
                    .keyboardShortcut(.cancelAction)
                Button("Start Writing") {}
                    .buttonStyle(.borderedProminent)
                    .disabled(true)
            case .finished:
                Button("Eject") { model.eject() }
                Button("Done") { model.acknowledge() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            case .failed:
                Button("Try Again") { model.retry() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canStart)
            }
        }
    }
}

/// A group label above a system group box (Figma `Source` / `Target` / `Options`).
struct SectionBox<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    content
                }
                .padding(4)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// Icon, title and subtitle (Figma `Media Label`).
struct MediaLabel: View {
    let symbol: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 10) {
            MediaIcon(symbol: symbol)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }
}

struct MediaIcon: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 24))
            .foregroundStyle(.secondary)
            .frame(width: 36, height: 30)
    }
}

struct SourceSection: View {
    let model: InstallerViewModel
    let choose: () -> Void

    var body: some View {
        SectionBox(title: "Source ISO") {
            HStack(spacing: 12) {
                MediaLabel(symbol: "opticaldisc", title: title, subtitle: subtitle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Choose…", action: choose)
            }
        }
    }

    private var title: String {
        model.iso?.url.lastPathComponent ?? String(localized: "Choose an ISO file")
    }

    private var subtitle: String {
        guard let iso = model.iso else {
            return String(localized: "Windows 10 or 11 installation ISO. You can also drop it on the window.")
        }
        if let info = iso.info {
            return UIText.isoSubtitle(info)
        }
        return iso.error ?? String(localized: "Reading the ISO…")
    }
}

struct TargetSection: View {
    @Bindable var model: InstallerViewModel

    var body: some View {
        SectionBox(title: "Target Disk") {
            HStack(spacing: 10) {
                MediaIcon(symbol: "externaldrive")
                VStack(alignment: .leading, spacing: 4) {
                    Picker(selection: $model.selectedDisk) {
                        if model.selectedDisk == nil {
                            Text("Select a Disk").tag(String?.none)
                        }
                        Section("External Disks") {
                            ForEach(model.disks) { disk in
                                Text(UIText.diskMenuItem(disk, fits: model.fits(disk)))
                                    .tag(Optional(disk.bsdName))
                                    .selectionDisabled(!model.fits(disk))
                            }
                        }
                        Divider()
                        Text("Internal disks and the startup disk are not shown")
                            .tag(Optional(InstallerViewModel.noteTag))
                            .selectionDisabled()
                    } label: {
                        EmptyView()
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var subtitle: String {
        guard let disk = model.selectedCandidate else {
            return String(localized: "Only external and removable disks are shown")
        }
        return UIText.diskSubtitle(disk)
    }
}

struct OptionsSection: View {
    @Bindable var model: InstallerViewModel

    var body: some View {
        SectionBox(title: "Options") {
            HStack(spacing: 12) {
                Text("Volume Label")
                    .frame(maxWidth: .infinity, alignment: .leading)
                TextField("Volume Label", text: $model.volumeLabel, prompt: Text("Use ISO label"))
                    .labelsHidden()
                    .frame(width: 220)
            }
            Divider()
            OptionRow(
                title: "Verify after writing",
                help: "After writing, reads the NTFS volume on the stick back and compares it with the ISO's file tree.",
                isOn: $model.verifyAfterWrite
            )
            Divider()
            OptionRow(
                title: "Use Windows UEFI CA 2023 signed boot loaders",
                help: model.ca2023Available
                    ? "Needed to boot with Secure Boot on PCs that have revoked the 2011 certificate. Only for Windows 11 25H2 or later ISOs."
                    : "Available once you choose a Windows 11 25H2 or later ISO.",
                isOn: $model.useCA2023
            )
            .disabled(!model.ca2023Available)
        }
    }
}

/// A checkbox with help text under it (Figma `Option Row`).
struct OptionRow: View {
    let title: LocalizedStringKey
    let help: LocalizedStringKey
    @Binding var isOn: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Toggle(title, isOn: $isOn)
                .toggleStyle(.checkbox)
            Text(help)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 19)
        }
    }
}

/// The status box under the form (Figma `Progress Panel`).
struct ProgressPanel: View {
    let model: InstallerViewModel

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    if let icon {
                        Image(systemName: icon.name)
                            .foregroundStyle(icon.color)
                    }
                    Text(status)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let trailing {
                        Text(trailing)
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.callout)
                if case .failed(let error) = model.stage {
                    Text(UIText.errorBody(error))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ProgressView(value: fraction)
                        .progressViewStyle(.linear)
                }
            }
            .padding(4)
        }
    }

    private var fraction: Double {
        switch model.stage {
        case .writing(let progress): progress.fraction
        case .finished: 1
        default: 0
        }
    }

    private var icon: (name: String, color: Color)? {
        switch model.stage {
        case .finished: ("checkmark.circle.fill", .green)
        case .failed: ("xmark.octagon.fill", .red)
        case .idle where model.stoppedByUser: ("exclamationmark.triangle.fill", .yellow)
        default: nil
        }
    }

    private var status: String {
        switch model.stage {
        case .idle:
            if model.stoppedByUser {
                return String(localized: "Stopped — the stick cannot be booted")
            }
            return model.canStart
                ? String(localized: "Ready to write")
                : String(localized: "Choose an ISO file and a target disk")
        case .starting:
            return String(localized: "Waiting for authorization…")
        case .writing(let progress):
            let step = progress.phase.rawValue
            let title = UIText.stepTitle(progress.phase)
            if progress.phase == .copyFiles, let detail = progress.detail, !detail.isEmpty {
                let shown = detail.hasPrefix("/") ? String(detail.dropFirst()) : detail
                return String(localized: "Step \(step)/8: \(title) — \(shown)")
            }
            return String(localized: "Step \(step)/8: \(title)")
        case .finished(let result):
            return result.verified
                ? String(localized: "Finished — the written data matches the ISO")
                : String(localized: "Finished")
        case .failed(let error):
            return String(localized: "Failed at step \(error.phase.rawValue)/8: \(UIText.stepName(error.phase))")
        }
    }

    private var trailing: String? {
        switch model.stage {
        case .idle where model.canStart && !model.stoppedByUser:
            guard let required = model.requiredBytes, let disk = model.selectedCandidate else {
                return nil
            }
            return String(localized: "Needs \(UIText.size(required)) / \(UIText.size(disk.sizeBytes))")
        case .writing(let progress):
            guard progress.phase == .copyFiles, let remaining = progress.estimatedRemaining else {
                return nil
            }
            let minutes = max(1, Int((remaining / 60).rounded(.up)))
            return String(localized: "About \(minutes) min left")
        case .finished(let result):
            return UIText.elapsed(result.elapsed)
        default:
            return nil
        }
    }
}

#Preview {
    ContentView(model: InstallerViewModel())
}
