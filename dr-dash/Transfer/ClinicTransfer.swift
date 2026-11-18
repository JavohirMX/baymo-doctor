import Foundation
import SwiftData

/// Versioned clinic JSON the later Multipeer session will send.
/// Dates use ISO-8601. This file does not open a session.
nonisolated enum ClinicTransfer {
    static let version = 1
    /// Multipeer service type. The session itself is a later phase.
    static let serviceType = "baymo-clinic"
    static let codeDigitCount = 6
    static let codeLifetime: TimeInterval = 5 * 60

    static func codeIsExpired(issuedAt: Date, now: Date) -> Bool {
        now.timeIntervalSince(issuedAt) >= codeLifetime
    }

    /// Strictly newer than the cursor. A nil cursor includes the whole history.
    /// An item timestamp equal to the cursor is not new.
    static func isNewer(_ date: Date, than cursor: Date?) -> Bool {
        guard let cursor else { return true }
        return date > cursor
    }
}

nonisolated enum ClinicTransferKind: String, Codable, Equatable, Sendable {
    case link
    case sync
}

nonisolated enum ClinicTransferError: Error, Equatable {
    case unsupportedVersion(Int)
    case incompletePayload(ClinicTransferKind)
}

nonisolated enum ClinicTransferCoding {
    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    static func encode(_ envelope: ClinicTransferEnvelope) throws -> Data {
        try encoder().encode(envelope)
    }

    static func decode(_ data: Data) throws -> ClinicTransferEnvelope {
        try decoder().decode(ClinicTransferEnvelope.self, from: data)
    }
}

/// `version` plus either a link body or a sync body.
nonisolated struct ClinicTransferEnvelope: Equatable, Sendable {
    var version: Int
    var kind: ClinicTransferKind
    var link: ClinicLinkPayload?
    var sync: ClinicSyncPayload?

    init(link: ClinicLinkPayload, version: Int = ClinicTransfer.version) {
        self.version = version
        self.kind = .link
        self.link = link
        self.sync = nil
    }

    init(sync: ClinicSyncPayload, version: Int = ClinicTransfer.version) {
        self.version = version
        self.kind = .sync
        self.link = nil
        self.sync = sync
    }

    @MainActor
    static func link(for child: Child) -> ClinicTransferEnvelope {
        ClinicTransferEnvelope(link: ClinicLinkPayload(child: child))
    }

    @MainActor
    static func sync(for child: Child, newerThan cursor: Date?) -> ClinicTransferEnvelope {
        ClinicTransferEnvelope(sync: ClinicSyncPayload(child: child, newerThan: cursor))
    }
}

extension ClinicTransferEnvelope: Codable {
    private enum CodingKeys: String, CodingKey {
        case version
        case kind
        case link
        case sync
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(Int.self, forKey: .version)
        guard version == ClinicTransfer.version else {
            throw ClinicTransferError.unsupportedVersion(version)
        }
        let kind = try container.decode(ClinicTransferKind.self, forKey: .kind)
        let link = try container.decodeIfPresent(ClinicLinkPayload.self, forKey: .link)
        let sync = try container.decodeIfPresent(ClinicSyncPayload.self, forKey: .sync)
        switch kind {
        case .link:
            guard link != nil, sync == nil else { throw ClinicTransferError.incompletePayload(.link) }
        case .sync:
            guard sync != nil, link == nil else { throw ClinicTransferError.incompletePayload(.sync) }
        }
        self.version = version
        self.kind = kind
        self.link = link
        self.sync = sync
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(kind, forKey: .kind)
        try container.encodeIfPresent(link, forKey: .link)
        try container.encodeIfPresent(sync, forKey: .sync)
    }
}

/// Profile, the current baseline, and the schedule. Older baselines stay on the Mac.
nonisolated struct ClinicLinkPayload: Equatable, Sendable {
    var profile: ClinicProfilePayload
    var baseline: ClinicBaselinePayload?
    var schedule: ClinicSchedulePayload

    @MainActor
    init(child: Child) {
        self.profile = ClinicProfilePayload(child: child)
        self.baseline = child.currentBaseline.map(ClinicBaselinePayload.init(version:))
        self.schedule = ClinicSchedulePayload(schedule: child.schedule)
    }
}

extension ClinicLinkPayload: Codable {}

nonisolated struct ClinicProfilePayload: Codable, Equatable, Sendable {
    var id: UUID
    var fullName: String
    var nickname: String
    var birthDate: Date
    var sex: ChildSex
    var conditionText: String
    /// Setup notes travel with the profile. A doctor's note on a recording does not.
    var setupNotes: String

    @MainActor
    init(child: Child) {
        id = child.id
        fullName = child.fullName
        nickname = child.nickname
        birthDate = child.birthDate
        sex = child.sex
        conditionText = child.conditionText
        setupNotes = child.setupNotes
    }
}

nonisolated struct ClinicBaselinePayload: Codable, Equatable, Sendable {
    var id: UUID
    var version: Int
    var fileName: String
    var recordedAt: Date
    var createdAt: Date
    var recording: StoredECGPayload

    @MainActor
    init(version baseline: BaselineVersion) {
        id = baseline.id
        version = baseline.version
        fileName = baseline.fileName
        recordedAt = baseline.recordedAt
        createdAt = baseline.createdAt
        recording = baseline.recording
    }
}

nonisolated struct ClinicSchedulePayload: Codable, Equatable, Sendable {
    var cadence: ScheduleCadence
    var weekdays: [Int]
    var durationMinutes: Int
    var reminderHour: Int
    var reminderMinute: Int
    var recordWhenSymptoms: Bool

    @MainActor
    init(schedule: Schedule?) {
        cadence = schedule?.cadence ?? .everyDay
        weekdays = schedule?.weekdays ?? []
        durationMinutes = schedule?.durationMinutes ?? Schedule.defaultDurationMinutes
        reminderHour = schedule?.reminderHour ?? Schedule.defaultReminderHour
        reminderMinute = schedule?.reminderMinute ?? Schedule.defaultReminderMinute
        recordWhenSymptoms = schedule?.recordWhenSymptoms ?? false
    }
}

/// Recordings and diary strictly newer than `newerThan`. Nil means the full history.
/// Doctor notes and review flags are not in this payload.
nonisolated struct ClinicSyncPayload: Equatable, Sendable {
    var childID: UUID
    var newerThan: Date?
    var recordings: [ClinicRecordingPayload]
    var diary: [ClinicDiaryPayload]

    var recordingCount: Int { recordings.count }
    var diaryCount: Int { diary.count }

    init(
        childID: UUID,
        newerThan: Date?,
        recordings: [ClinicRecordingPayload],
        diary: [ClinicDiaryPayload]
    ) {
        self.childID = childID
        self.newerThan = newerThan
        self.recordings = recordings
        self.diary = diary
    }

    @MainActor
    init(child: Child, newerThan cursor: Date?) {
        self.childID = child.id
        self.newerThan = cursor
        self.recordings = child.recordings
            .filter { ClinicTransfer.isNewer($0.startDate, than: cursor) }
            .sorted { $0.startDate < $1.startDate }
            .map(ClinicRecordingPayload.init(recording:))
        self.diary = child.diaryEvents
            .filter { ClinicTransfer.isNewer($0.startedAt, than: cursor) }
            .sorted { $0.startedAt < $1.startedAt }
            .map(ClinicDiaryPayload.init(event:))
    }

    func filtering(newerThan cursor: Date?) -> ClinicSyncPayload {
        ClinicSyncPayload(
            childID: childID,
            newerThan: cursor,
            recordings: recordings.filter { ClinicTransfer.isNewer($0.startDate, than: cursor) },
            diary: diary.filter { ClinicTransfer.isNewer($0.startedAt, than: cursor) }
        )
    }
}

extension ClinicSyncPayload: Codable {}

nonisolated struct ClinicRecordingPayload: Codable, Equatable, Sendable {
    var id: UUID
    var startDate: Date
    var duration: TimeInterval
    var parentStatus: ParentRecordingStatus
    var heartRate: Int?
    var prMS: Int?
    var qrsMS: Int?
    var axisDegrees: Int?
    var signalQuality: String
    var samples: StoredECGPayload

    @MainActor
    init(recording: ClinicRecording) {
        id = recording.id
        startDate = recording.startDate
        duration = recording.duration
        parentStatus = recording.parentStatus
        heartRate = recording.heartRate
        prMS = recording.prMS
        qrsMS = recording.qrsMS
        axisDegrees = recording.axisDegrees
        signalQuality = recording.signalQuality
        samples = recording.samples
    }
}

nonisolated struct ClinicDiaryPayload: Codable, Equatable, Sendable {
    var id: UUID
    var kind: DiaryEventKind
    var startedAt: Date
    var text: String
    var symptomName: String?

    @MainActor
    init(event: DiaryEvent) {
        id = event.id
        kind = event.kind
        startedAt = event.startedAt
        text = event.text
        symptomName = event.symptomName
    }
}

/// Upserts by id. Does not move `lastSyncDate`.
/// A finished sync should advance that cursor itself. Missed checks leave Needs attention
/// once the cursor moves past their start, even if they are still unreviewed.
enum ClinicSyncMerge {
    /// Incoming items whose ids are not already known. Later duplicates in `incoming` are dropped.
    nonisolated static func novel<Item: Identifiable>(
        incoming: [Item],
        existingIDs: Set<Item.ID>
    ) -> [Item] where Item.ID: Hashable {
        var seen = existingIDs
        return incoming.filter { seen.insert($0.id).inserted }
    }

    @MainActor
    static func mergeRecordings(_ incoming: [ClinicRecordingPayload], into child: Child) {
        var byID = Dictionary(uniqueKeysWithValues: child.recordings.map { ($0.id, $0) })
        for payload in incoming {
            if let existing = byID[payload.id] {
                existing.applyPhoneFields(from: payload)
            } else {
                let created = ClinicRecording.add(
                    to: child,
                    id: payload.id,
                    startDate: payload.startDate,
                    duration: payload.duration,
                    parentStatus: payload.parentStatus,
                    heartRate: payload.heartRate,
                    prMS: payload.prMS,
                    qrsMS: payload.qrsMS,
                    axisDegrees: payload.axisDegrees,
                    signalQuality: payload.signalQuality,
                    samples: payload.samples
                )
                byID[payload.id] = created
            }
        }
    }

    @MainActor
    static func mergeDiary(_ incoming: [ClinicDiaryPayload], into child: Child) {
        var byID = Dictionary(uniqueKeysWithValues: child.diaryEvents.map { ($0.id, $0) })
        for payload in incoming {
            if let existing = byID[payload.id] {
                existing.applyPhoneFields(from: payload)
            } else {
                let created = DiaryEvent.add(
                    to: child,
                    id: payload.id,
                    kind: payload.kind,
                    startedAt: payload.startedAt,
                    text: payload.text,
                    symptomName: payload.symptomName
                )
                byID[payload.id] = created
            }
        }
    }
}
