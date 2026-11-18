import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Edits one child's details, replaces the baseline with a new version, and updates the schedule.
/// The child page presents this sheet with the `Child` to change.
struct EditChildSheet: View {
    let child: Child
    @Environment(\.dismiss) private var dismiss

    @State private var details: PatientDetailsDraft
    @State private var schedule: ScheduleDraft
    @State private var replacement: ImportedBaseline?
    @State private var baselineError: String?
    @State private var saveError: String?
    @State private var choosingFile = false

    init(child: Child) {
        self.child = child
        _details = State(initialValue: PatientDetailsDraft(child: child))
        _schedule = State(initialValue: ScheduleDraft(schedule: child.schedule))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                Section {
                    Text("Edit patient")
                        .font(.title2.weight(.semibold))
                    Text("Details, baseline, and schedule stay on this Mac.")
                        .font(.callout)
                        .foregroundStyle(ClinicPalette.secondaryText)
                }
                ChildDetailsForm(details: $details)
                BaselineFileCard(
                    file: displayedBaseline,
                    error: baselineError,
                    footnote: child.currentBaseline == nil
                        ? nil
                        : "Replacing adds a version. Older baselines stay.",
                    onChoose: { choosingFile = true }
                )
                ScheduleForm(draft: $schedule)
                if let saveError {
                    Text(saveError)
                        .font(.callout)
                        .foregroundStyle(ClinicPalette.foreground(.red))
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack(spacing: 10) {
                ClinicSecondaryButton(title: "Cancel") { dismiss() }
                Spacer(minLength: 8)
                ClinicPrimaryButton(title: "Save", isEnabled: canSave) {
                    save()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 20)
        }
        .frame(width: 620)
        .frame(minHeight: 480, maxHeight: 680)
        .background(ClinicPalette.canvas)
        .presentationBackground(ClinicPalette.canvas)
        .fileImporter(
            isPresented: $choosingFile,
            allowedContentTypes: BaselineFileParser.contentTypes,
            allowsMultipleSelection: false
        ) { result in
            accept(BaselineFileParser.importing(result))
        }
    }

    private var displayedBaseline: BaselineFileSummary? {
        if let replacement {
            return BaselineFileSummary(fileName: replacement.fileName, recordedAt: replacement.recordedAt)
        }
        guard let current = child.currentBaseline else { return nil }
        return BaselineFileSummary(fileName: current.fileName, recordedAt: current.recordedAt)
    }

    private var canSave: Bool {
        details.canContinue && schedule.isComplete
    }

    private func accept(_ outcome: (baseline: ImportedBaseline?, error: String?)) {
        if let error = outcome.error {
            baselineError = error
            return
        }
        guard let imported = outcome.baseline else { return }
        replacement = imported
        baselineError = nil
        saveError = nil
    }

    private func save() {
        guard details.canContinue, schedule.isComplete else { return }
        guard let context = child.modelContext else {
            saveError = "The changes could not be saved."
            return
        }
        details.write(to: child)
        if let existing = child.schedule {
            schedule.apply(to: existing)
        } else {
            let plan = Schedule()
            schedule.apply(to: plan)
            child.schedule = plan
        }
        if let replacement {
            BaselineVersion.addVersion(
                to: child,
                fileName: replacement.fileName,
                recordedAt: replacement.recordedAt,
                recording: replacement.recording
            )
        }
        do {
            try context.save()
        } catch {
            context.rollback()
            saveError = "The changes could not be saved."
            return
        }
        dismiss()
    }
}
