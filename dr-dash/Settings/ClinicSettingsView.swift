import AppKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct ClinicSettingsView: View {
    @Environment(ClinicLibrary.self) private var library

    var body: some View {
        ClinicSettingsForm()
            .modelContainer(library.container)
            .id(library.storeKind)
    }
}

private struct ClinicSettingsForm: View {
    @Environment(ClinicLibrary.self) private var library
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Child.fullName) private var children: [Child]
    @AppStorage(ClinicAppearance.storageKey) private var appearance: ClinicAppearance = .system
    @State private var selectedChildID: UUID?
    @State private var isImporting = false
    @State private var transferMessage: String?

    var body: some View {
        Form {
            Section {
                Picker("Appearance", selection: $appearance) {
                    ForEach(ClinicAppearance.allCases) { choice in
                        Text(choice.title).tag(choice)
                    }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
                .accessibilityLabel("Appearance")
            } header: {
                Text("Appearance")
            }

            Section {
                Toggle(
                    "Show demo clinic",
                    isOn: Binding(
                        get: { library.showsDemoClinic },
                        set: { library.setShowsDemoClinic($0) }
                    )
                )
                Text("Demo children live in a separate store. Turning this off returns to the real clinic and does not copy or delete either one.")
                    .font(.callout)
                    .foregroundStyle(ClinicPalette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("Developer")
            }

            Section {
                Picker("Child", selection: $selectedChildID) {
                    Text("None").tag(Optional<UUID>.none)
                    ForEach(children, id: \.id) { child in
                        Text(childTitle(child)).tag(Optional(child.id))
                    }
                }
                Button("Export link JSON") {
                    exportLink()
                }
                .disabled(selectedChild == nil)
                Button("Export sync JSON") {
                    exportSync()
                }
                .disabled(selectedChild == nil)
                Button("Import JSON…") {
                    isImporting = true
                }
                if let transferMessage {
                    Text(transferMessage)
                        .font(.callout)
                        .foregroundStyle(ClinicPalette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } header: {
                Text("Developer transfer")
            } footer: {
                Text("Exports use the same link and sync JSON as the nearby phone transfer. They are saved in this Mac's clinic folder and shown in Finder. A sync import merges by id and does not change the last sync date.")
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 480)
        .background(ClinicPalette.canvas)
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                importFile(at: url)
            case .failure:
                transferMessage = "The JSON file could not be opened."
            }
        }
        .onChange(of: children.map(\.id)) { _, ids in
            if let selectedChildID, !ids.contains(selectedChildID) {
                self.selectedChildID = nil
            }
        }
    }

    private var selectedChild: Child? {
        children.first { $0.id == selectedChildID }
    }

    private func childTitle(_ child: Child) -> String {
        let name = child.fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Unnamed child" : name
    }

    private func exportLink() {
        guard let child = selectedChild else { return }
        do {
            let url = try ClinicTransferFiles.writeEnvelope(
                .link(for: child),
                fileName: "link-\(child.id.uuidString).json"
            )
            NSWorkspace.shared.activateFileViewerSelecting([url])
            transferMessage = "Exported the link JSON for \(childTitle(child)) and showed it in Finder."
        } catch {
            transferMessage = "The link JSON could not be exported."
        }
    }

    private func exportSync() {
        guard let child = selectedChild else { return }
        do {
            let url = try ClinicTransferFiles.writeEnvelope(
                .sync(for: child, newerThan: child.lastSyncDate),
                fileName: "sync-\(child.id.uuidString).json"
            )
            NSWorkspace.shared.activateFileViewerSelecting([url])
            transferMessage = "Exported the sync JSON for \(childTitle(child)) and showed it in Finder."
        } catch {
            transferMessage = "The sync JSON could not be exported."
        }
    }

    private func importFile(at url: URL) {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }
        do {
            let data = try Data(contentsOf: url)
            let envelope = try ClinicTransferCoding.decode(data)
            switch envelope.kind {
            case .link:
                guard let payload = envelope.link else { throw ClinicTransferError.incompletePayload(.link) }
                let child = try ClinicLinkApply.apply(payload, in: modelContext, selectedChildID: selectedChildID)
                transferMessage = "Updated \(childTitle(child)) from the link file."
            case .sync:
                guard let payload = envelope.sync else { throw ClinicTransferError.incompletePayload(.sync) }
                let child = try ClinicSyncImport.merge(payload, in: modelContext)
                transferMessage = "Merged \(payload.recordingCount) recordings and \(payload.diaryCount) journal entries into \(childTitle(child)). The last sync date was not changed."
            }
        } catch {
            transferMessage = ClinicFileError.message(for: error)
        }
    }
}
