import SwiftData
import SwiftUI

/// Sheets the toolbar can present. Later phases replace the placeholder bodies.
enum ClinicSheet: Identifiable, Equatable {
    case addPatient
    case syncPhone
    /// `childID` is `Child.id`.
    case linkPhone(UUID)

    var id: String {
        switch self {
        case .addPatient: "addPatient"
        case .syncPhone: "syncPhone"
        case .linkPhone(let childID): "linkPhone-\(childID.uuidString)"
        }
    }
}

struct ClinicSheetHost: View {
    let sheet: ClinicSheet
    /// Set to the new child's id after a successful add. Omit it and the write is ignored.
    @Binding var selectedChildID: UUID?
    /// Called with the new child's id after a successful add. The window presents Link phone once this sheet closes.
    var onAdded: (UUID) -> Void

    @Query(sort: \Child.fullName) private var children: [Child]
    @Environment(\.modelContext) private var modelContext

    init(
        sheet: ClinicSheet,
        selectedChildID: Binding<UUID?> = .constant(nil),
        onAdded: @escaping (UUID) -> Void = { _ in }
    ) {
        self.sheet = sheet
        self._selectedChildID = selectedChildID
        self.onAdded = onAdded
    }

    var body: some View {
        switch sheet {
        case .addPatient:
            AddPatientSheet(selectedChildID: $selectedChildID, onAdded: onAdded)
        case .syncPhone:
            SyncPhoneSheet(child: nil, selection: $selectedChildID)
        case .linkPhone(let childID):
            if let child = resolvedChild(childID) {
                LinkPhoneSheet(child: child)
            } else {
                ClinicSheetPlaceholder(
                    title: "Link phone",
                    message: "This child is not in the open clinic."
                )
            }
        }
    }

    private func resolvedChild(_ id: UUID) -> Child? {
        if let match = children.first(where: { $0.id == id }) { return match }
        return ClinicChildLookup.child(id: id, in: modelContext)
    }
}

struct ClinicSheetPlaceholder: View {
    var title: String
    var message: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.title2.weight(.semibold))
            Text(message)
                .foregroundStyle(ClinicPalette.secondaryText)
            HStack {
                Spacer()
                ClinicPrimaryButton(title: "Done") {
                    dismiss()
                }
            }
        }
        .padding(24)
        .frame(minWidth: 440)
        .background(ClinicPalette.canvas)
        .presentationBackground(ClinicPalette.canvas)
    }
}
