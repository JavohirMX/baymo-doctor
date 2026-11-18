import Observation
import SwiftData
import SwiftUI

/// Waiting sheet, including a wrong or expired code. Success is `.linked`.
enum LinkPhonePhase: Equatable {
    case waiting
    case sending
    case linked
    case failed
}

/// Mac side of linking a phone. The Mac advertises `baymo-clinic` and shows a 6-digit code.
/// A mismatch or an expired code stays on this sheet and sends no clinic payload.
/// Dismissing does not delete the child.
struct LinkPhoneSheet: View {
    var child: Child
    @State private var model: LinkPhoneModel
    @Environment(\.dismiss) private var dismiss

    init(child: Child) {
        self.child = child
        _model = State(initialValue: LinkPhoneModel(child: child))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch model.phase {
            case .waiting:
                waiting
            case .sending:
                sending
            case .linked:
                linked
            case .failed:
                failed
            }
        }
        .padding(24)
        .frame(minWidth: 440, alignment: .leading)
        .background(ClinicPalette.canvas)
        .presentationBackground(ClinicPalette.canvas)
        .task {
            model.start()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                model.tick()
            }
        }
        .onDisappear {
            model.leave()
        }
    }

    private var waiting: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Link phone")
                .font(.title2.weight(.semibold))
            Text(ClinicNearbyCode.grouped(model.code))
                .font(.system(size: 44, weight: .semibold, design: .monospaced))
                .textSelection(.enabled)
                .accessibilityLabel("Pairing code \(model.code)")
            Text("Expires in \(ClinicNearbyCode.countdown(issuedAt: model.issuedAt, now: model.now))")
                .font(.title3.monospacedDigit())
                .foregroundStyle(ClinicPalette.secondaryText)
            Text("The phone connects directly to this Mac. Nothing is sent online.")
                .foregroundStyle(ClinicPalette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            banners
            HStack {
                Spacer()
                ClinicSecondaryButton(title: "Link later") {
                    dismiss()
                }
                if model.codeError == .expired {
                    ClinicPrimaryButton(title: "New code") {
                        model.issueNewCode()
                    }
                } else {
                    ClinicSecondaryButton(title: "New code") {
                        model.issueNewCode()
                    }
                }
            }
        }
    }

    private var sending: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Link phone")
                .font(.title2.weight(.semibold))
            ProgressView()
            Text("Sending the profile, baseline, and schedule.")
                .foregroundStyle(ClinicPalette.secondaryText)
            HStack {
                Spacer()
                ClinicSecondaryButton(title: "Link later") {
                    dismiss()
                }
            }
        }
    }

    private var linked: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Phone linked")
                .font(.title2.weight(.semibold))
            Text(child.fullName)
                .font(.title3)
            Text("The profile, baseline, and schedule were sent to the phone.")
                .foregroundStyle(ClinicPalette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                ClinicPrimaryButton(title: "Done") {
                    dismiss()
                }
            }
        }
    }

    private var failed: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Link failed")
                .font(.title2.weight(.semibold))
            Text(model.failureMessage)
                .foregroundStyle(ClinicPalette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                ClinicSecondaryButton(title: "Link later") {
                    dismiss()
                }
                ClinicPrimaryButton(title: "New code") {
                    model.issueNewCode()
                }
            }
        }
    }

    @ViewBuilder
    private var banners: some View {
        if let codeError = model.codeError {
            Text(codeError.message)
                .foregroundStyle(ClinicPalette.foreground(.red))
                .fixedSize(horizontal: false, vertical: true)
        }
        if let networkError = model.networkError {
            Text(networkError)
                .foregroundStyle(ClinicPalette.foreground(.red))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

@MainActor
@Observable
final class LinkPhoneModel {
    private let child: Child
    private(set) var phase: LinkPhonePhase = .waiting
    private(set) var code: String
    private(set) var issuedAt: Date
    private(set) var now = Date()
    private(set) var codeError: ClinicCodeFailure?
    private(set) var networkError: String?
    private(set) var failureMessage = ""
    private var transport: ClinicNearbySession?
    private var inbox = ClinicWireInbox()
    private var sessionGeneration = 0
    private var left = false
    private var linkCommit = ClinicTransferCommit()

    init(child: Child) {
        self.child = child
        code = ClinicNearbyCode.make()
        issuedAt = .now
    }

    func start() {
        guard !left, transport == nil else { return }
        sessionGeneration += 1
        let generation = sessionGeneration
        let session = ClinicNearbySession(mode: .advertiseLink) { [weak self] event in
            guard let self, self.sessionGeneration == generation else { return }
            self.handle(event)
        }
        transport = session
        session.start()
    }

    func tick() {
        now = .now
        guard !left, phase == .waiting else { return }
        guard ClinicTransfer.codeIsExpired(issuedAt: issuedAt, now: now) else { return }
        codeError = .expired
    }

    func issueNewCode() {
        guard !left, phase == .waiting || phase == .failed else { return }
        code = ClinicNearbyCode.make()
        issuedAt = .now
        now = .now
        codeError = nil
        networkError = nil
        failureMessage = ""
        linkCommit = ClinicTransferCommit()
        phase = .waiting
        inbox = ClinicWireInbox()
        sessionGeneration += 1
        transport?.stop()
        transport = nil
        start()
    }

    /// Stops advertising. Does not delete the child or clear a link that already succeeded.
    func leave() {
        guard !left else { return }
        left = true
        let current = transport
        let linked = phase == .linked
        transport = nil
        if phase == .sending {
            phase = .waiting
        }
        guard let current else { return }
        if linked {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1))
                current.stop()
            }
        } else {
            current.stop()
        }
    }

    private func handle(_ event: ClinicTransportEvent) {
        guard !left else { return }
        switch event {
        case .ready:
            break
        case .peerLost:
            if phase == .linked {
                transport?.stop()
                transport = nil
                return
            }
            guard phase == .sending else { return }
            linkCommit.noteCancelledOrDropped()
            failureMessage = "The phone disconnected before the link finished. This child was not marked as linked."
            phase = .failed
            transport?.stop()
            transport = nil
        case .startFailed(let message):
            guard phase == .waiting else { return }
            networkError = message
        case .data(let data):
            receive(data)
        }
    }

    private func receive(_ data: Data) {
        guard !left, phase == .waiting || phase == .sending else { return }
        do {
            guard let incoming = try inbox.take(data) else { return }
            switch incoming {
            case .code(let value):
                guard phase == .waiting else { return }
                networkError = nil
                judge(value)
            case .receipt:
                markLinked()
            default:
                guard phase == .waiting else { return }
                networkError = "The phone sent an unexpected message."
            }
        } catch {
            networkError = ClinicWire.userMessage(for: error)
        }
    }

    private func judge(_ entered: String) {
        guard phase == .waiting else { return }
        if ClinicTransfer.codeIsExpired(issuedAt: issuedAt, now: .now) {
            reject(.expired)
            return
        }
        guard ClinicNearbyCode.isWellFormed(entered), entered == code else {
            reject(.mismatch)
            return
        }
        sendLink()
    }

    /// Tells the phone the code failed and sends no link payload.
    private func reject(_ reason: ClinicCodeFailure) {
        guard phase == .waiting else { return }
        codeError = reason
        inbox = ClinicWireInbox()
        let current = transport
        try? current?.send(ClinicWireMessage.codeResult(accepted: false, reason: reason))
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            guard phase == .waiting, codeError == reason else { return }
            current?.disconnectPeers()
        }
    }

    private func sendLink() {
        phase = .sending
        codeError = nil
        networkError = nil
        Task { @MainActor in
            await Task.yield()
            guard phase == .sending, let transport else { return }
            do {
                try transport.send(ClinicWireMessage.codeResult(accepted: true, reason: nil))
                guard phase == .sending else { return }
                let frames = try ClinicWire.frames(for: ClinicWireMessage.link(ClinicLinkPayload(child: child)))
                guard phase == .sending else { return }
                try transport.send(frames: frames)
                guard phase == .sending else { return }
                try transport.send(ClinicWireMessage.complete())
                guard phase == .sending else { return }
                linkCommit.noteLocalComplete()
            } catch {
                guard phase == .sending else { return }
                failureMessage = Self.linkFailureMessage(for: error)
                phase = .failed
                transport.stop()
                self.transport = nil
            }
        }
    }

    private static func linkFailureMessage(for error: Error) -> String {
        if case ClinicWireError.notConnected = error {
            return "The phone disconnected before the link finished. This child was not marked as linked."
        }
        if case ClinicWireError.tooLarge = error {
            return "The link is too large to send. This child was not marked as linked."
        }
        return "The link could not be sent. This child was not marked as linked."
    }

    /// The child stays unlinked until the phone confirms it applied the payload.
    private func markLinked() {
        guard phase == .sending, linkCommit.noteReceipt() else { return }
        child.setLinkState(.linked)
        try? child.modelContext?.save()
        phase = .linked
    }
}
