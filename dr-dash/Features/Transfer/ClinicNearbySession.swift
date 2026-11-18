import Foundation
import MultipeerConnectivity

nonisolated enum ClinicTransportEvent: Sendable {
    case ready
    case peerLost
    case data(Data)
    case startFailed(String)
}

/// Advertises a link or browses for a sync. The peer name is "Baymo Doctor".
/// Delegate callbacks hop to the main actor before the model sees them.
final class ClinicNearbySession: NSObject, MCSessionDelegate, MCNearbyServiceAdvertiserDelegate, MCNearbyServiceBrowserDelegate {
    nonisolated enum Mode: Sendable {
        case advertiseLink
        case browseSync
    }

    nonisolated(unsafe) private let session: MCSession
    nonisolated(unsafe) private let advertiser: MCNearbyServiceAdvertiser?
    nonisolated(unsafe) private let browser: MCNearbyServiceBrowser?
    nonisolated(unsafe) private let mode: Mode
    nonisolated(unsafe) private let forward: @Sendable (ClinicTransportEvent) -> Void
    nonisolated(unsafe) private let flags = NearbyFlags()

    init(mode: Mode, onEvent: @escaping @MainActor (ClinicTransportEvent) -> Void) {
        let peerID = MCPeerID(displayName: ClinicNearby.displayName)
        let session = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
        self.session = session
        self.mode = mode
        switch mode {
        case .advertiseLink:
            advertiser = MCNearbyServiceAdvertiser(
                peer: peerID,
                discoveryInfo: [ClinicNearby.roleKey: ClinicNearby.linkRole],
                serviceType: ClinicTransfer.serviceType
            )
            browser = nil
        case .browseSync:
            advertiser = nil
            browser = MCNearbyServiceBrowser(peer: peerID, serviceType: ClinicTransfer.serviceType)
        }
        forward = { event in
            Task { @MainActor in
                onEvent(event)
            }
        }
        super.init()
        session.delegate = self
        advertiser?.delegate = self
        browser?.delegate = self
    }

    func start() {
        guard flags.markStarted() else { return }
        advertiser?.startAdvertisingPeer()
        browser?.startBrowsingForPeers()
    }

    func stop() {
        flags.markStopped()
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        session.disconnect()
    }

    /// Drops the current peer and keeps advertising. Used when a link code is rejected.
    func disconnectPeers() {
        flags.prepareDeliberateDisconnect()
        session.disconnect()
    }

    func send(_ message: ClinicWireMessage) throws {
        try send(frames: ClinicWire.frames(for: message))
    }

    func send(frames: [Data]) throws {
        let peers = session.connectedPeers
        guard !peers.isEmpty else { throw ClinicWireError.notConnected }
        for frame in frames {
            try session.send(frame, toPeers: peers, with: .reliable)
        }
    }

    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        switch state {
        case .connected:
            if flags.noteConnected() {
                emit(.ready)
            }
        case .notConnected:
            let droppedLivePeer = flags.noteDisconnected()
            if droppedLivePeer {
                emit(.peerLost)
            } else if mode == .browseSync {
                inviteNext()
            }
        case .connecting:
            break
        @unknown default:
            break
        }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        emit(.data(data))
    }

    nonisolated func session(
        _ session: MCSession,
        didReceive stream: InputStream,
        withName streamName: String,
        fromPeer peerID: MCPeerID
    ) {}

    nonisolated func session(
        _ session: MCSession,
        didStartReceivingResourceWithName resourceName: String,
        fromPeer peerID: MCPeerID,
        with progress: Progress
    ) {}

    nonisolated func session(
        _ session: MCSession,
        didFinishReceivingResourceWithName resourceName: String,
        fromPeer peerID: MCPeerID,
        at localURL: URL?,
        withError error: Error?
    ) {}

    nonisolated func session(
        _ session: MCSession,
        didReceiveCertificate certificate: [Any]?,
        fromPeer peerID: MCPeerID,
        certificateHandler: @escaping (Bool) -> Void
    ) {
        certificateHandler(true)
    }

    nonisolated func advertiser(
        _ advertiser: MCNearbyServiceAdvertiser,
        didReceiveInvitationFromPeer peerID: MCPeerID,
        withContext context: Data?,
        invitationHandler: @escaping (Bool, MCSession?) -> Void
    ) {
        let accept = flags.beginInvitation()
        invitationHandler(accept, accept ? session : nil)
    }

    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        emit(.startFailed(error.localizedDescription))
    }

    nonisolated func browser(
        _ browser: MCNearbyServiceBrowser,
        foundPeer peerID: MCPeerID,
        withDiscoveryInfo info: [String: String]?
    ) {
        guard info?[ClinicNearby.roleKey] == ClinicNearby.syncRole else { return }
        flags.remember(peerID)
        inviteNext()
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        flags.forget(peerID)
        inviteNext()
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        emit(.startFailed(error.localizedDescription))
    }

    nonisolated private func inviteNext() {
        guard mode == .browseSync, let peerID = flags.nextInvite() else { return }
        browser?.invitePeer(peerID, to: session, withContext: nil, timeout: 30)
    }

    nonisolated private func emit(_ event: ClinicTransportEvent) {
        guard !flags.isStopped else { return }
        forward(event)
    }
}

/// Invitation and browse flags touched from the Multipeer queue and the main actor.
nonisolated private final class NearbyFlags: @unchecked Sendable {
    private let lock = NSLock()
    private var stopped = false
    private var started = false
    private var connected = false
    private var reserving = false
    private var inviting: MCPeerID?
    private var discovered: [MCPeerID] = []
    private var attempted: [MCPeerID] = []

    func markStarted() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if started || stopped { return false }
        started = true
        return true
    }

    func markStopped() {
        lock.lock()
        stopped = true
        lock.unlock()
    }

    var isStopped: Bool {
        lock.lock()
        defer { lock.unlock() }
        return stopped
    }

    func beginInvitation() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !stopped, !connected, !reserving else { return false }
        reserving = true
        return true
    }

    func noteConnected() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !stopped else { return false }
        reserving = false
        inviting = nil
        let changed = !connected
        connected = true
        return changed
    }

    /// True only when a peer that had reached `.connected` dropped, and the session was not stopped on purpose.
    func noteDisconnected() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        reserving = false
        inviting = nil
        let wasLive = connected
        connected = false
        return wasLive && !stopped
    }

    func prepareDeliberateDisconnect() {
        lock.lock()
        connected = false
        reserving = false
        inviting = nil
        lock.unlock()
    }

    func remember(_ peer: MCPeerID) {
        lock.lock()
        defer { lock.unlock() }
        if !discovered.contains(peer) {
            discovered.append(peer)
        }
    }

    func forget(_ peer: MCPeerID) {
        lock.lock()
        defer { lock.unlock() }
        discovered.removeAll { $0 == peer }
        attempted.removeAll { $0 == peer }
        if inviting == peer {
            inviting = nil
        }
    }

    /// Invites each discovered phone once. A failed invite does not spin on the same peer.
    func nextInvite() -> MCPeerID? {
        lock.lock()
        defer { lock.unlock() }
        guard !stopped, !connected, inviting == nil else { return nil }
        guard let peer = discovered.first(where: { candidate in !attempted.contains(candidate) }) else { return nil }
        attempted.append(peer)
        inviting = peer
        return peer
    }
}
