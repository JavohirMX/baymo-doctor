import Foundation

/// Multipeer framing around `ClinicTransfer` payloads. This file does not define a second clinic schema.
/// Message order and JSON fields are the contract in `docs/clinic-transfer.md`.
nonisolated enum ClinicNearby {
    static let displayName = "Baymo Doctor"
    static let roleKey = "role"
    static let linkRole = "link"
    static let syncRole = "sync"
}

/// Six-digit pairing code. Link codes are issued by the Mac. Sync codes are issued by the phone.
nonisolated enum ClinicNearbyCode {
    static func make() -> String {
        String(format: "%0\(ClinicTransfer.codeDigitCount)d", Int.random(in: 0...999_999))
    }

    static func digits(from text: String) -> String {
        String(text.filter { $0.isASCII && $0.isNumber }.prefix(ClinicTransfer.codeDigitCount))
    }

    static func isWellFormed(_ code: String) -> Bool {
        code.count == ClinicTransfer.codeDigitCount && code.allSatisfy { $0.isASCII && $0.isNumber }
    }

    static func remaining(issuedAt: Date, now: Date) -> TimeInterval {
        max(0, ClinicTransfer.codeLifetime - now.timeIntervalSince(issuedAt))
    }

    static func countdown(issuedAt: Date, now: Date) -> String {
        let seconds = Int(remaining(issuedAt: issuedAt, now: now).rounded(.down))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    /// Display form only. The wire value has no space.
    static func grouped(_ code: String) -> String {
        guard code.count == 6 else { return code }
        let middle = code.index(code.startIndex, offsetBy: 3)
        return "\(code[..<middle]) \(code[middle...])"
    }
}

nonisolated enum ClinicCodeFailure: String, Codable, Equatable, Sendable {
    case mismatch
    case expired

    var message: String {
        switch self {
        case .mismatch:
            "That code does not match."
        case .expired:
            "That code has expired."
        }
    }
}

nonisolated enum ClinicWireType: String, Codable, Equatable, Sendable {
    case code
    case codeResult
    case link
    case syncManifest
    case recording
    case diary
    case complete
    case cancel
    case chunk
}

nonisolated enum ClinicWireError: Error, Equatable {
    case unsupportedVersion(Int)
    case incomplete(String)
    case badChunk
    case tooLarge
    case notConnected
    case unreadable
}

/// One logical multipeer message. Clinic bodies reuse `ClinicTransferEnvelope` and the payload structs.
nonisolated struct ClinicWireMessage: Codable, Equatable, Sendable {
    var version: Int
    var type: ClinicWireType
    var code: String?
    var accepted: Bool?
    var reason: ClinicCodeFailure?
    var envelope: ClinicTransferEnvelope?
    var childID: UUID?
    var newerThan: Date?
    var recordingCount: Int?
    var diaryCount: Int?
    var index: Int?
    var count: Int?
    var recording: ClinicRecordingPayload?
    var diary: ClinicDiaryPayload?
    /// Chunk set id. Recording and diary ids stay inside those payload objects.
    var id: UUID?
    /// One raw slice of an encoded logical message. JSON encodes it as base64.
    var data: Data?

    init(
        version: Int = ClinicTransfer.version,
        type: ClinicWireType,
        code: String? = nil,
        accepted: Bool? = nil,
        reason: ClinicCodeFailure? = nil,
        envelope: ClinicTransferEnvelope? = nil,
        childID: UUID? = nil,
        newerThan: Date? = nil,
        recordingCount: Int? = nil,
        diaryCount: Int? = nil,
        index: Int? = nil,
        count: Int? = nil,
        recording: ClinicRecordingPayload? = nil,
        diary: ClinicDiaryPayload? = nil,
        id: UUID? = nil,
        data: Data? = nil
    ) {
        self.version = version
        self.type = type
        self.code = code
        self.accepted = accepted
        self.reason = reason
        self.envelope = envelope
        self.childID = childID
        self.newerThan = newerThan
        self.recordingCount = recordingCount
        self.diaryCount = diaryCount
        self.index = index
        self.count = count
        self.recording = recording
        self.diary = diary
        self.id = id
        self.data = data
    }

    static func code(_ code: String) -> ClinicWireMessage {
        ClinicWireMessage(type: .code, code: code)
    }

    static func codeResult(accepted: Bool, reason: ClinicCodeFailure?) -> ClinicWireMessage {
        ClinicWireMessage(type: .codeResult, accepted: accepted, reason: accepted ? nil : reason)
    }

    static func link(_ payload: ClinicLinkPayload) -> ClinicWireMessage {
        ClinicWireMessage(type: .link, envelope: ClinicTransferEnvelope(link: payload))
    }

    static func syncManifest(_ payload: ClinicSyncPayload) -> ClinicWireMessage {
        ClinicWireMessage(
            type: .syncManifest,
            childID: payload.childID,
            newerThan: payload.newerThan,
            recordingCount: payload.recordingCount,
            diaryCount: payload.diaryCount
        )
    }

    static func recording(_ payload: ClinicRecordingPayload, index: Int, count: Int) -> ClinicWireMessage {
        ClinicWireMessage(type: .recording, index: index, count: count, recording: payload)
    }

    static func diary(_ payload: ClinicDiaryPayload, index: Int, count: Int) -> ClinicWireMessage {
        ClinicWireMessage(type: .diary, index: index, count: count, diary: payload)
    }

    static func complete() -> ClinicWireMessage {
        ClinicWireMessage(type: .complete)
    }

    static func cancel() -> ClinicWireMessage {
        ClinicWireMessage(type: .cancel)
    }
}

nonisolated enum ClinicIncoming: Sendable {
    case code(String)
    case codeResult(accepted: Bool, reason: ClinicCodeFailure?)
    case link(ClinicLinkPayload)
    case manifest(childID: UUID, newerThan: Date?, recordings: Int, diary: Int)
    case recording(ClinicRecordingPayload, index: Int, count: Int)
    case diary(ClinicDiaryPayload, index: Int, count: Int)
    case complete
    case cancel

    static func make(_ message: ClinicWireMessage) throws -> ClinicIncoming {
        switch message.type {
        case .code:
            guard let code = message.code else { throw ClinicWireError.incomplete("code") }
            return .code(code)
        case .codeResult:
            guard let accepted = message.accepted else { throw ClinicWireError.incomplete("codeResult") }
            if accepted {
                return .codeResult(accepted: true, reason: nil)
            }
            return .codeResult(accepted: false, reason: message.reason ?? .mismatch)
        case .link:
            guard let envelope = message.envelope, envelope.kind == .link, let payload = envelope.link else {
                throw ClinicWireError.incomplete("link")
            }
            return .link(payload)
        case .syncManifest:
            guard
                let childID = message.childID,
                let recordings = message.recordingCount,
                let diary = message.diaryCount,
                recordings >= 0,
                diary >= 0
            else {
                throw ClinicWireError.incomplete("syncManifest")
            }
            return .manifest(childID: childID, newerThan: message.newerThan, recordings: recordings, diary: diary)
        case .recording:
            guard let recording = message.recording, let index = message.index, let count = message.count, index >= 0, count >= 0 else {
                throw ClinicWireError.incomplete("recording")
            }
            return .recording(recording, index: index, count: count)
        case .diary:
            guard let event = message.diary, let index = message.index, let count = message.count, index >= 0, count >= 0 else {
                throw ClinicWireError.incomplete("diary")
            }
            return .diary(event, index: index, count: count)
        case .complete:
            return .complete
        case .cancel:
            return .cancel
        case .chunk:
            throw ClinicWireError.badChunk
        }
    }
}

nonisolated enum ClinicWire {
    /// Raw JSON slice size before base64. Both sides must stay at or under this.
    static let chunkSize = 16 * 1024
    static let maxChunks = 8_192

    static func encode(_ message: ClinicWireMessage) throws -> Data {
        try ClinicTransferCoding.encoder().encode(message)
    }

    static func decodeMessage(_ data: Data) throws -> ClinicWireMessage {
        let message: ClinicWireMessage
        do {
            message = try ClinicTransferCoding.decoder().decode(ClinicWireMessage.self, from: data)
        } catch let error as ClinicTransferError {
            throw error
        } catch {
            throw ClinicWireError.unreadable
        }
        guard message.version == ClinicTransfer.version else {
            throw ClinicWireError.unsupportedVersion(message.version)
        }
        return message
    }

    /// One data blob per frame. Small messages are sent as themselves. Larger ones become `chunk` frames.
    static func frames(for message: ClinicWireMessage) throws -> [Data] {
        let json = try encode(message)
        if message.type == .chunk || json.count <= chunkSize {
            return [json]
        }
        var slices: [Data] = []
        var offset = 0
        while offset < json.count {
            let end = min(offset + chunkSize, json.count)
            slices.append(json.subdata(in: offset..<end))
            offset = end
        }
        guard slices.count <= maxChunks else { throw ClinicWireError.tooLarge }
        let chunkID = UUID()
        return try slices.enumerated().map { index, slice in
            try encode(ClinicWireMessage(
                type: .chunk,
                index: index,
                count: slices.count,
                id: chunkID,
                data: slice
            ))
        }
    }

    static func userMessage(for error: Error) -> String {
        if let wire = error as? ClinicWireError {
            switch wire {
            case .tooLarge:
                return "The transfer is too large."
            case .notConnected:
                return "The phone disconnected before the transfer finished."
            case .unsupportedVersion:
                return "The phone sent an unsupported transfer version."
            case .incomplete, .badChunk, .unreadable:
                return "The phone sent a message this Mac could not read."
            }
        }
        if case ClinicTransferError.unsupportedVersion = error {
            return "The phone sent an unsupported transfer version."
        }
        return "The phone sent a message this Mac could not read."
    }
}

nonisolated struct ClinicChunkAssembler {
    private var parts: [UUID: [Int: Data]] = [:]
    private var expected: [UUID: Int] = [:]

    mutating func add(id: UUID, index: Int, count: Int, data: Data) throws -> Data? {
        guard (1...ClinicWire.maxChunks).contains(count), (0..<count).contains(index), !data.isEmpty, data.count <= ClinicWire.chunkSize else {
            throw ClinicWireError.badChunk
        }
        if let previous = expected[id], previous != count {
            throw ClinicWireError.badChunk
        }
        expected[id] = count
        parts[id, default: [:]][index] = data
        let stored = parts[id] ?? [:]
        guard stored.count == count else { return nil }
        var joined = Data()
        for position in 0..<count {
            guard let slice = stored[position] else { return nil }
            joined.append(slice)
        }
        parts[id] = nil
        expected[id] = nil
        return joined
    }
}

struct ClinicWireInbox {
    private var assembler = ClinicChunkAssembler()

    mutating func take(_ data: Data) throws -> ClinicIncoming? {
        let message = try ClinicWire.decodeMessage(data)
        if message.type == .chunk {
            guard let id = message.id, let index = message.index, let count = message.count, let slice = message.data else {
                throw ClinicWireError.incomplete("chunk")
            }
            guard let joined = try assembler.add(id: id, index: index, count: count, data: slice) else {
                return nil
            }
            let inner = try ClinicWire.decodeMessage(joined)
            guard inner.type != .chunk else { throw ClinicWireError.badChunk }
            return try ClinicIncoming.make(inner)
        }
        return try ClinicIncoming.make(message)
    }
}
