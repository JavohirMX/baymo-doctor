import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Two-step sheet for `.addPatient`. Pass `selectedChildID` so a successful add selects the new child.
struct AddPatientSheet: View {
    @Binding var selectedChildID: UUID?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var step: AddPatientStepHeader.Step = .details
    @State private var details = PatientDetailsDraft()
    @State private var schedule = ScheduleDraft()
    @State private var baseline: ImportedBaseline?
    @State private var baselineError: String?
    @State private var saveError: String?
    @State private var choosingFile = false
    /// The window uses this to open Link phone for the child that was just saved.
    var onAdded: (UUID) -> Void

    init(
        selectedChildID: Binding<UUID?> = .constant(nil),
        onAdded: @escaping (UUID) -> Void = { _ in }
    ) {
        self._selectedChildID = selectedChildID
        self.onAdded = onAdded
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            AddPatientStepHeader(step: step)
                .padding(.horizontal, 24)
                .padding(.top, 16)
            Form {
                switch step {
                case .details:
                    Section {
                        Text("Child details")
                            .font(.title2.weight(.semibold))
                        Text("You can change these later in the child's profile.")
                            .font(.callout)
                            .foregroundStyle(ClinicPalette.secondaryText)
                    }
                    ChildDetailsForm(details: $details)
                case .baseline:
                    BaselineFileCard(
                        file: baseline.map {
                            BaselineFileSummary(fileName: $0.fileName, recordedAt: $0.recordedAt)
                        },
                        error: baselineError,
                        footnote: nil,
                        onChoose: { choosingFile = true }
                    )
                    ScheduleForm(draft: $schedule)
                    if let saveError {
                        Text(saveError)
                            .font(.callout)
                            .foregroundStyle(ClinicPalette.foreground(.red))
                    }
                }
            }
            .formStyle(.grouped)

            Divider()
            footer
        }
        .frame(width: 620)
        .background(ClinicPalette.canvas)
        .presentationBackground(ClinicPalette.canvas)
        .presentationSizing(.fitted)
        .fileImporter(
            isPresented: $choosingFile,
            allowedContentTypes: BaselineFileParser.contentTypes,
            allowsMultipleSelection: false
        ) { result in
            accept(BaselineFileParser.importing(result))
        }
    }

    @ViewBuilder
    private var footer: some View {
        HStack(spacing: 10) {
            switch step {
            case .details:
                ClinicSecondaryButton(title: "Cancel") { dismiss() }
                Spacer(minLength: 8)
                ClinicPrimaryButton(title: "Continue", isEnabled: details.canContinue) {
                    step = .baseline
                }
                .keyboardShortcut(.defaultAction)
            case .baseline:
                ClinicSecondaryButton(title: "Back") { step = .details }
                Spacer(minLength: 8)
                ClinicSecondaryButton(title: "Cancel") { dismiss() }
                ClinicPrimaryButton(title: "Add patient", isEnabled: canAdd) {
                    addPatient()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 20)
    }

    private var canAdd: Bool {
        details.canContinue && baseline != nil && schedule.isComplete
    }

    private func accept(_ outcome: (baseline: ImportedBaseline?, error: String?)) {
        if let error = outcome.error {
            baselineError = error
            return
        }
        guard let imported = outcome.baseline else { return }
        baseline = imported
        baselineError = nil
        saveError = nil
    }

    private func addPatient() {
        guard let birthDate = details.birthDate, let baseline else { return }
        let plan = Schedule()
        schedule.apply(to: plan)
        let child = Child.add(
            to: modelContext,
            fullName: details.trimmedName,
            nickname: details.nickname.trimmingCharacters(in: .whitespacesAndNewlines),
            birthDate: Calendar.current.startOfDay(for: min(birthDate, .now)),
            sex: details.sex,
            conditionText: details.conditionText.trimmingCharacters(in: .whitespacesAndNewlines),
            setupNotes: details.setupNotes.trimmingCharacters(in: .whitespacesAndNewlines),
            schedule: plan
        )
        BaselineVersion.addVersion(
            to: child,
            fileName: baseline.fileName,
            recordedAt: baseline.recordedAt,
            recording: baseline.recording
        )
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            saveError = "The patient could not be saved."
            return
        }
        selectedChildID = child.id
        onAdded(child.id)
        dismiss()
    }
}
