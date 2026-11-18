import AppKit
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
            .frame(maxWidth: .infinity)
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

/// One text field drawn as six cells, with a dash between the two halves.
private struct ClinicCodeField: View {
    @Binding var code: String
    var isEnabled: Bool
    var onSubmit: () -> Void

    @State private var caretIndex = 0
    @State private var isFocused = false
    @State private var focusRequest = 0

    var body: some View {
        ZStack {
            ClinicCodeInput(
                code: $code,
                caretIndex: $caretIndex,
                isFocused: $isFocused,
                isEnabled: isEnabled,
                focusRequest: focusRequest,
                onSubmit: onSubmit
            )
            codeRow
                .allowsHitTesting(isEnabled)
        }
        .frame(width: 310, height: 54)
        .onAppear { focusRequest += 1 }
        .onChange(of: isEnabled) { _, enabled in
            if enabled { focusRequest += 1 }
        }
    }

    private var codeRow: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { index in
                cell(index)
            }
            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .fill(ClinicPalette.secondaryText)
                .frame(width: 10, height: 2)
                .accessibilityHidden(true)
            ForEach(3..<6, id: \.self) { index in
                cell(index)
            }
        }
        .accessibilityHidden(true)
    }

    private func cell(_ index: Int) -> some View {
        let characters = Array(code)
        let digit = index < characters.count ? String(characters[index]) : ""
        let caret = caretPlacement(at: index)
        return ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor))
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(
                    caret == .none ? Color(nsColor: .separatorColor) : Color.accentColor,
                    lineWidth: caret == .none ? 1 : 2
                )
            HStack(spacing: 2) {
                if caret == .before || caret == .alone {
                    caretMark
                }
                if !digit.isEmpty {
                    Text(digit)
                        .font(.system(size: 28, weight: .regular, design: .monospaced))
                        .foregroundStyle(ClinicPalette.primaryText)
                }
                if caret == .after {
                    caretMark
                }
            }
        }
        .frame(width: 44, height: 54)
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onTapGesture {
            caretIndex = min(index, code.count)
            focusRequest += 1
        }
    }

    private var caretMark: some View {
        TimelineView(.periodic(from: .now, by: 0.55)) { context in
            let visible = Int(context.date.timeIntervalSinceReferenceDate / 0.55).isMultiple(of: 2)
            Capsule()
                .fill(Color.accentColor)
                .frame(width: 2, height: 26)
                .opacity(visible ? 1 : 0)
        }
    }

    private func caretPlacement(at index: Int) -> CaretPlacement {
        guard isFocused else { return .none }
        let insertion = min(max(caretIndex, 0), code.count)
        if insertion == 6 { return index == 5 ? .after : .none }
        guard insertion == index else { return .none }
        return index < code.count ? .before : .alone
    }

    private enum CaretPlacement {
        case none
        case before
        case after
        case alone
    }
}

/// The single editor behind the six cells. Typing, backspace, and paste all change one string.
private struct ClinicCodeInput: NSViewRepresentable {
    @Binding var code: String
    @Binding var caretIndex: Int
    @Binding var isFocused: Bool
    var isEnabled: Bool
    var focusRequest: Int
    var onSubmit: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(string: code)
        field.delegate = context.coordinator
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.textColor = .clear
        field.font = .monospacedDigitSystemFont(ofSize: 28, weight: .regular)
        field.maximumNumberOfLines = 1
        field.cell?.sendsActionOnEndEditing = false
        field.alphaValue = 0.01
        field.setAccessibilityLabel("6-digit code")
        context.coordinator.field = field
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.code = $code
        context.coordinator.caretIndex = $caretIndex
        context.coordinator.isFocused = $isFocused
        context.coordinator.onSubmit = onSubmit
        field.isEnabled = isEnabled
        if field.stringValue != code {
            context.coordinator.replace(field, with: code, caret: caretIndex)
        }
        guard context.coordinator.appliedFocus != focusRequest else { return }
        context.coordinator.appliedFocus = focusRequest
        let index = min(max(caretIndex, 0), code.count)
        context.coordinator.focus(field, at: index)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(code: $code, caretIndex: $caretIndex, isFocused: $isFocused, onSubmit: onSubmit)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var code: Binding<String>
        var caretIndex: Binding<Int>
        var isFocused: Binding<Bool>
        var onSubmit: () -> Void
        var appliedFocus = 0
        weak var field: NSTextField?
        private var isApplying = false

        init(
            code: Binding<String>,
            caretIndex: Binding<Int>,
            isFocused: Binding<Bool>,
            onSubmit: @escaping () -> Void
        ) {
            self.code = code
            self.caretIndex = caretIndex
            self.isFocused = isFocused
            self.onSubmit = onSubmit
        }

        func controlTextDidChange(_ notification: Notification) {
            guard !isApplying, let field = notification.object as? NSTextField else { return }
            let digits = ClinicNearbyCode.digits(from: field.stringValue)
            let caret = min(currentCaret(in: field), digits.count)
            replace(field, with: digits, caret: caret)
            code.wrappedValue = digits
            caretIndex.wrappedValue = caret
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            isFocused.wrappedValue = true
            guard let editor = field?.currentEditor() as? NSTextView else { return }
            editor.drawsBackground = false
            editor.backgroundColor = .clear
            editor.insertionPointColor = .clear
            editor.textColor = .clear
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            isFocused.wrappedValue = false
        }

        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                onSubmit()
                return true
            }
            return false
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !isApplying, let editor = notification.object as? NSTextView else { return }
            let index = min(max(editor.selectedRange.location, 0), code.wrappedValue.count)
            guard caretIndex.wrappedValue != index else { return }
            caretIndex.wrappedValue = index
        }

        func replace(_ field: NSTextField, with digits: String, caret: Int) {
            isApplying = true
            if field.stringValue != digits {
                field.stringValue = digits
            }
            placeCaret(in: field, at: caret)
            isApplying = false
        }

        func focus(_ field: NSTextField, at index: Int, attempt: Int = 0) {
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(40 * (attempt + 1))) {
                guard field.window != nil else {
                    if attempt < 6 {
                        self.focus(field, at: index, attempt: attempt + 1)
                    }
                    return
                }
                field.window?.makeFirstResponder(field)
                self.placeCaret(in: field, at: index)
            }
        }

        func placeCaret(in field: NSTextField, at index: Int) {
            let clamped = min(max(index, 0), field.stringValue.count)
            field.currentEditor()?.selectedRange = NSRange(location: clamped, length: 0)
        }

        private func currentCaret(in field: NSTextField) -> Int {
            field.currentEditor()?.selectedRange.location ?? field.stringValue.count
        }
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
                reopenBrowse()
            }
        case .peerLost:
            if phase == .success {
                transport?.stop()
                transport = nil
                return
            }
            if phase == .contacting, !codeAccepted {
                reopenBrowse()
                return
            }
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
        case .link, .receipt:
            fail("The phone sent an unexpected message.")
        }
    }

    /// A dropped invitation before the code is accepted is not a finished sync.
    private func reopenBrowse() {
        guard !left, phase == .contacting, !codeAccepted else { return }
        sessionGeneration += 1
        let generation = sessionGeneration
        let old = transport
        transport = nil
        old?.stop()
        inbox = ClinicWireInbox()
        contactingDetail = "Looking for a phone. Nothing is sent online."
        let session = ClinicNearbySession(mode: .browseSync) { [weak self] event in
            guard let self, self.sessionGeneration == generation else { return }
            self.handle(event)
        }
        transport = session
        session.start()
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
        let covered = receivedRecordings.count >= recordingTotal && receivedDiary.count >= journalTotal
        guard ClinicTransferCommit.mayAdvanceLastSync(completeCoversManifest: covered, droppedBeforeComplete: false) else {
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
        try? transport?.send(ClinicWireMessage.receipt())
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
