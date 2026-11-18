import Observation
import SwiftData
import SwiftUI

/// `entry` is the code sheet. A wrong or expired code stays on `entry` and sets `codeError`.
/// `success` is the only phase that advances `lastSyncDate`.
/// `stopped` means the doctor tapped Stop. Fully received items stay, and the cursor does not move.
/// `failed` is a disconnect or a short transfer. It is not the success sheet.
enum SyncPhonePhase: Equatable {
    case entry
    case contacting
    case progress
    case success
    case stopped
    case failed
}

/// Mac side of syncing a phone. `child == nil` accepts whichever child the phone's payload names.
/// Review writes `selection` when that binding exists, and otherwise calls `onReview`.
struct SyncPhoneSheet: View {
    var child: Child?
    var selection: Binding<UUID?>?
    var onReview: (Child) -> Void

    @State private var model = SyncPhoneModel()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    init(
        child: Child?,
        selection: Binding<UUID?>? = nil,
        onReview: @escaping (Child) -> Void = { _ in }
    ) {
        self.child = child
        self.selection = selection
        self.onReview = onReview
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch model.phase {
            case .entry, .contacting:
                entry
            case .progress:
                progress
            case .success:
                success
            case .stopped:
                stopped
            case .failed:
                failed
            }
        }
        .padding(24)
        .frame(minWidth: 480, alignment: .leading)
        .background(ClinicPalette.canvas)
        .presentationBackground(ClinicPalette.canvas)
        .onAppear {
            model.configure(preferred: child, context: modelContext)
        }
        .onDisappear {
            model.leave()
        }
    }

    private var codeBinding: Binding<String> {
        Binding(
            get: { model.code },
            set: { model.code = ClinicNearbyCode.digits(from: $0) }
        )
    }

    private var entry: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Sync phone")
                .font(.title2.weight(.semibold))
            Text("Enter the 6-digit code shown on the phone.")
            Text("The phone connects directly to this Mac. Nothing is sent online.")
                .foregroundStyle(ClinicPalette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            ClinicCodeField(
                code: codeBinding,
                isEnabled: model.phase != .contacting,
                onSubmit: { model.connect() }
            )
            if let codeError = model.codeError {
                Text(codeError.message)
                    .foregroundStyle(ClinicPalette.foreground(.red))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if model.phase == .contacting {
                ProgressView()
                Text(model.contactingDetail)
                    .foregroundStyle(ClinicPalette.secondaryText)
            }
            HStack {
                Spacer()
                if model.phase == .contacting {
                    ClinicSecondaryButton(title: "Cancel") {
                        model.cancelContact()
                    }
                } else {
                    ClinicSecondaryButton(title: "Cancel") {
                        dismiss()
                    }
                    ClinicPrimaryButton(
                        title: "Connect",
                        isEnabled: ClinicNearbyCode.isWellFormed(model.code)
                    ) {
                        model.connect()
                    }
                }
            }
        }
    }

    private var progress: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Syncing")
                .font(.title2.weight(.semibold))
            if let name = model.syncedChild?.fullName, !name.isEmpty {
                Text(name)
                    .font(.title3)
            }
            if model.recordingTotal + model.journalTotal > 0 {
                ProgressView(
                    value: Double(model.recordingsReceived + model.journalReceived),
                    total: Double(model.recordingTotal + model.journalTotal)
                )
            } else {
                ProgressView()
            }
            Text("Recordings \(model.recordingsReceived) of \(model.recordingTotal)")
                .monospacedDigit()
            Text("Journal \(model.journalReceived) of \(model.journalTotal)")
                .monospacedDigit()
            HStack {
                Spacer()
                ClinicSecondaryButton(title: "Stop sync") {
                    model.stop()
                }
            }
        }
    }

    @ViewBuilder
    private var success: some View {
        if let receipt = model.receipt {
            VStack(alignment: .leading, spacing: 16) {
                Text("Sync finished")
                    .font(.title2.weight(.semibold))
                Text(displayName(receipt.childName))
                    .font(.title3)
                Text(receipt.spanText)
                Text(countText(receipt.recordingCount, singular: "recording", plural: "recordings"))
                Text(countText(receipt.missedDayCount, singular: "missed day", plural: "missed days"))
                Text(countText(receipt.journalCount, singular: "journal entry", plural: "journal entries"))
                HStack {
                    Spacer()
                    ClinicSecondaryButton(title: "Done") {
                        dismiss()
                    }
                    ClinicPrimaryButton(title: "Review this child") {
                        review()
                    }
                }
            }
        }
    }

    private var stopped: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Sync stopped")
                .font(.title2.weight(.semibold))
            Text(keptSentence)
                .foregroundStyle(ClinicPalette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                ClinicSecondaryButton(title: "Try again") {
                    model.tryAgain()
                }
                ClinicPrimaryButton(title: "Done") {
                    dismiss()
                }
            }
        }
    }

    private var failed: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Sync failed")
                .font(.title2.weight(.semibold))
            Text(model.failureMessage)
                .foregroundStyle(ClinicPalette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Text(keptSentence)
                .foregroundStyle(ClinicPalette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                ClinicSecondaryButton(title: "Try again") {
                    model.tryAgain()
                }
                ClinicPrimaryButton(title: "Done") {
                    dismiss()
                }
            }
        }
    }

    private var keptSentence: String {
        let recordings = model.recordingsReceived
        let journal = model.journalReceived
        let saved: String
        if recordings == 0 && journal == 0 {
            saved = "Nothing was fully received."
        } else {
            saved = "Saved \(countText(recordings, singular: "recording", plural: "recordings")) and \(countText(journal, singular: "journal entry", plural: "journal entries"))."
        }
        return saved + " The last sync date was not changed."
    }

    private func countText(_ count: Int, singular: String, plural: String) -> String {
        "\(count) \(count == 1 ? singular : plural)"
    }

    private func displayName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "This child" : trimmed
    }

    private func review() {
        guard let synced = model.syncedChild else { return }
        if let selection {
            selection.wrappedValue = synced.id
        } else {
            onReview(synced)
        }
        dismiss()
    }
}

/// Six native fields, one digit each. The code stays digits only and is at most six characters.
private struct ClinicCodeField: View {
    @Binding var code: String
    var isEnabled: Bool
    var onSubmit: () -> Void

    @FocusState private var focusedIndex: Int?

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<6, id: \.self) { index in
                TextField("", text: digitBinding(index))
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.center)
                    .font(.title3.monospaced())
                    .frame(width: 44)
                    .focused($focusedIndex, equals: index)
                    .onSubmit(onSubmit)
                    .accessibilityLabel(index == 0 ? "6-digit code" : "Digit \(index + 1)")
            }
        }
        .disabled(!isEnabled)
        .onAppear { focusedIndex = 0 }
    }

    private func digitBinding(_ index: Int) -> Binding<String> {
        Binding(
            get: {
                let characters = Array(code)
                guard index < characters.count else { return "" }
                return String(characters[index])
            },
            set: { raw in
                let digits = raw.filter { $0.isASCII && $0.isNumber }
                var characters = Array(code)
                if digits.isEmpty {
                    if index < characters.count {
                        characters.remove(at: index)
                    }
                    code = String(characters)
                    focusedIndex = max(0, index - 1)
                    return
                }
                let typed = digits[digits.index(before: digits.endIndex)]
                if index < characters.count {
                    characters[index] = typed
                } else if index == characters.count {
                    characters.append(typed)
                }
                code = String(characters.prefix(6))
                focusedIndex = min(index + 1, 5)
            }
        )
    }
}

@MainActor
@Observable
final class SyncPhoneModel {
    private(set) var phase: SyncPhonePhase = .entry
    var code = ""
    private(set) var codeError: ClinicCodeFailure?
    private(set) var contactingDetail = "Looking for a phone. Nothing is sent online."
    private(set) var recordingsReceived = 0
    private(set) var recordingTotal = 0
    private(set) var journalReceived = 0
    private(set) var journalTotal = 0
    private(set) var receipt: ClinicSyncReceipt?
    private(set) var failureMessage = ""
    private(set) var syncedChild: Child?

    private var preferred: Child?
    private var context: ModelContext?
    private var transport: ClinicNearbySession?
    private var inbox = ClinicWireInbox()
    private var pending: [PendingSyncItem] = []
    private var receivedRecordings: [ClinicRecordingPayload] = []
    private var receivedDiary: [ClinicDiaryPayload] = []
    private var manifestNewerThan: Date?
    private var codeAccepted = false
    private var didConfigure = false
    private var sessionGeneration = 0
    private var left = false

    func configure(preferred: Child?, context: ModelContext) {
        guard !didConfigure else { return }
        didConfigure = true
        self.preferred = preferred
        self.context = context
    }

    func connect() {
        guard phase == .entry || phase == .failed || phase == .stopped else { return }
        let digits = ClinicNearbyCode.digits(from: code)
        code = digits
        guard ClinicNearbyCode.isWellFormed(digits) else { return }
        codeError = nil
        failureMessage = ""
        receipt = nil
        syncedChild = nil
        pending = []
        receivedRecordings = []
        receivedDiary = []
        recordingsReceived = 0
        journalReceived = 0
        recordingTotal = 0
        journalTotal = 0
        manifestNewerThan = nil
        codeAccepted = false
        inbox = ClinicWireInbox()
        phase = .contacting
        contactingDetail = "Looking for a phone. Nothing is sent online."
        sessionGeneration += 1
        let generation = sessionGeneration
        transport?.stop()
        let session = ClinicNearbySession(mode: .browseSync) { [weak self] event in
            guard let self, self.sessionGeneration == generation else { return }
            self.handle(event)
        }
        transport = session
        session.start()
    }

    func cancelContact() {
        guard phase == .contacting else { return }
        phase = .entry
        pending = []
        shutdown(sendCancel: false)
        inbox = ClinicWireInbox()
    }

    func stop() {
        guard phase == .progress else { return }
        phase = .stopped
        shutdown(sendCancel: true)
    }

    func tryAgain() {
        guard phase == .failed || phase == .stopped else { return }
        codeError = nil
        failureMessage = ""
        phase = .entry
    }

    func leave() {
        guard !left else { return }
        left = true
        if phase == .progress {
            phase = .stopped
            shutdown(sendCancel: true)
        } else {
            shutdown(sendCancel: false)
        }
    }

    private func handle(_ event: ClinicTransportEvent) {
        guard !left else { return }
        switch event {
        case .ready:
            guard phase == .contacting, !codeAccepted else { return }
            contactingDetail = "Checking the code."
            do {
                try transport?.send(ClinicWireMessage.code(code))
            } catch {
                fail("The code could not be sent to the phone.")
            }
        case .peerLost:
            fail("The phone disconnected before the sync finished.")
        case .startFailed(let message):
            fail(message)
        case .data(let data):
            receive(data)
        }
    }

    private func receive(_ data: Data) {
        guard phase == .contacting || phase == .progress else { return }
        do {
            guard let incoming = try inbox.take(data) else { return }
            handle(incoming)
        } catch {
            fail(ClinicWire.userMessage(for: error))
        }
    }

    private func handle(_ incoming: ClinicIncoming) {
        switch incoming {
        case .code:
            fail("The phone sent an unexpected message.")
        case .codeResult(let accepted, let reason):
            guard phase == .contacting, !codeAccepted else { return }
            if accepted {
                codeAccepted = true
                contactingDetail = "Code accepted. Waiting for recordings."
            } else {
                // Stay on the code sheet. Do not open the progress or success sheet.
                codeError = reason ?? .mismatch
                phase = .entry
                shutdown(sendCancel: false)
                inbox = ClinicWireInbox()
            }
        case .manifest(let childID, let newerThan, let recordings, let diary):
            beginManifest(childID: childID, newerThan: newerThan, recordings: recordings, diary: diary)
        case .recording(let payload, _, _):
            receiveRecording(payload)
        case .diary(let payload, _, _):
            receiveDiary(payload)
        case .complete:
            guard codeAccepted else {
                fail("The phone sent clinic data before the code was accepted.")
                return
            }
            finishIfComplete()
        case .cancel:
            fail("The phone cancelled the sync.")
        case .link:
            fail("The phone sent an unexpected message.")
        }
    }

    private func beginManifest(childID: UUID, newerThan: Date?, recordings: Int, diary: Int) {
        guard phase == .contacting || phase == .progress else { return }
        guard codeAccepted else {
            fail("The phone sent clinic data before the code was accepted.")
            return
        }
        if let syncedChild {
            if childID != syncedChild.id || recordings != recordingTotal || diary != journalTotal {
                fail("The phone sent a conflicting sync manifest.")
            }
            return
        }
        guard let child = resolve(childID) else {
            pending = []
            if preferred != nil {
                fail("This code is for a different child.")
            } else {
                fail("No child on this Mac matches this phone.")
            }
            return
        }
        syncedChild = child
        manifestNewerThan = newerThan
        recordingTotal = recordings
        journalTotal = diary
        phase = .progress
        let queued = pending
        pending = []
        for item in queued {
            switch item {
            case .recording(let payload):
                addRecording(payload)
            case .diary(let payload):
                addDiary(payload)
            }
        }
    }

    private func receiveRecording(_ payload: ClinicRecordingPayload) {
        guard codeAccepted else {
            fail("The phone sent clinic data before the code was accepted.")
            return
        }
        guard phase == .contacting || phase == .progress else { return }
        if syncedChild == nil {
            pending.append(.recording(payload))
        } else {
            addRecording(payload)
        }
    }

    private func receiveDiary(_ payload: ClinicDiaryPayload) {
        guard codeAccepted else {
            fail("The phone sent clinic data before the code was accepted.")
            return
        }
        guard phase == .contacting || phase == .progress else { return }
        if syncedChild == nil {
            pending.append(.diary(payload))
        } else {
            addDiary(payload)
        }
    }

    private func addRecording(_ payload: ClinicRecordingPayload) {
        guard let syncedChild else { return }
        ClinicSyncMerge.mergeRecordings([payload], into: syncedChild)
        if let index = receivedRecordings.firstIndex(where: { $0.id == payload.id }) {
            receivedRecordings[index] = payload
        } else {
            receivedRecordings.append(payload)
        }
        recordingsReceived = receivedRecordings.count
        persist()
    }

    private func addDiary(_ payload: ClinicDiaryPayload) {
        guard let syncedChild else { return }
        ClinicSyncMerge.mergeDiary([payload], into: syncedChild)
        if let index = receivedDiary.firstIndex(where: { $0.id == payload.id }) {
            receivedDiary[index] = payload
        } else {
            receivedDiary.append(payload)
        }
        journalReceived = receivedDiary.count
        persist()
    }

    private func finishIfComplete() {
        guard phase == .contacting || phase == .progress else { return }
        guard let syncedChild else {
            fail("The phone finished before identifying the child.")
            return
        }
        guard receivedRecordings.count >= recordingTotal, receivedDiary.count >= journalTotal else {
            fail("The phone finished before every item arrived.")
            return
        }
        let payload = ClinicSyncPayload(
            childID: syncedChild.id,
            newerThan: manifestNewerThan,
            recordings: receivedRecordings,
            diary: receivedDiary
        )
        syncedChild.lastSyncDate = ClinicSyncClock.advanced(
            existing: syncedChild.lastSyncDate,
            payload: payload,
            completedAt: .now
        )
        receipt = ClinicSyncClock.receipt(
            childName: syncedChild.fullName,
            recordings: receivedRecordings,
            diary: receivedDiary
        )
        persist()
        phase = .success
        shutdown(sendCancel: false)
    }

    private func resolve(_ id: UUID) -> Child? {
        if let preferred {
            return preferred.id == id ? preferred : nil
        }
        guard let context else { return nil }
        return ClinicChildLookup.child(id: id, in: context)
    }

    private func persist() {
        try? (syncedChild?.modelContext ?? context)?.save()
    }

    private func fail(_ message: String) {
        guard phase == .contacting || phase == .progress else { return }
        failureMessage = message
        phase = .failed
        shutdown(sendCancel: false)
    }

    private func shutdown(sendCancel: Bool) {
        sessionGeneration += 1
        let current = transport
        transport = nil
        guard let current else { return }
        if sendCancel {
            try? current.send(ClinicWireMessage.cancel())
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(300))
                current.stop()
            }
        } else {
            current.stop()
        }
    }
}

private enum PendingSyncItem {
    case recording(ClinicRecordingPayload)
    case diary(ClinicDiaryPayload)
}
