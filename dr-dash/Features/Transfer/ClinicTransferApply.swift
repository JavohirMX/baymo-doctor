import Foundation
import SwiftData

/// What a finished sync shows. Missed days are distinct local dates of `missed` recordings.
struct ClinicSyncReceipt: Equatable, Sendable {
    var childName: String
    var earliest: Date?
    var latest: Date?
    var recordingCount: Int
    var missedDayCount: Int
    var journalCount: Int

    var spanText: String {
        switch (earliest, latest) {
        case let (start?, end?):
            let left = start.formatted(date: .abbreviated, time: .omitted)
            let right = end.formatted(date: .abbreviated, time: .omitted)
            return left == right ? left : "\(left) to \(right)"
        default:
            return "No new dates"
        }
    }
}

/// Cursor written only after a sync finishes.
///
/// `ClinicSyncPayload.newerThan` is the exclusive start the sender filtered with, not the covered end.
/// The covered end is the latest recording `startDate` or diary `startedAt`.
/// When that set is empty, a finished sync uses `completedAt`. The stored cursor never moves backward.
enum ClinicSyncClock {
    static func advanced(existing: Date?, payload: ClinicSyncPayload, completedAt: Date) -> Date {
        let coveredEnd = (payload.recordings.map(\.startDate) + payload.diary.map(\.startedAt)).max()
        let candidate: Date
        if let coveredEnd {
            candidate = coveredEnd
        } else {
            // Includes a payload that names `newerThan` and then contains nothing newer.
            candidate = completedAt
        }
        guard let existing else { return candidate }
        return max(existing, candidate)
    }

    static func receipt(
        childName: String,
        recordings: [ClinicRecordingPayload],
        diary: [ClinicDiaryPayload],
        calendar: Calendar = .current
    ) -> ClinicSyncReceipt {
        let dates = recordings.map(\.startDate) + diary.map(\.startedAt)
        let missedDays = Set(
            recordings
                .filter { $0.parentStatus == .missed }
                .map { calendar.startOfDay(for: $0.startDate) }
        )
        return ClinicSyncReceipt(
            childName: childName,
            earliest: dates.min(),
            latest: dates.max(),
            recordingCount: recordings.count,
            missedDayCount: missedDays.count,
            journalCount: diary.count
        )
    }
}

enum ClinicChildLookup {
    @MainActor
    static func child(id: UUID, in context: ModelContext) -> Child? {
        guard let children = try? context.fetch(FetchDescriptor<Child>()) else { return nil }
        return children.first { $0.id == id }
    }
}

enum ClinicFileError: LocalizedError {
    case chooseChild
    case unknownChild
    case baselineUsedElsewhere

    var errorDescription: String? {
        switch self {
        case .chooseChild:
            "Choose a child, or import a link whose id matches a child on this Mac."
        case .unknownChild:
            "No child on this Mac has this id."
        case .baselineUsedElsewhere:
            "That baseline already belongs to another child."
        }
    }

    static func message(for error: Error) -> String {
        if let fileError = error as? ClinicFileError {
            return fileError.localizedDescription
        }
        switch error {
        case ClinicTransferError.unsupportedVersion:
            return "This file uses an unsupported clinic transfer version."
        case ClinicTransferError.incompletePayload:
            return "This file is not a complete clinic link or sync."
        case is DecodingError:
            return "This file is not a clinic link or sync."
        default:
            let nsError = error as NSError
            if nsError.domain == NSCocoaErrorDomain {
                return nsError.localizedDescription
            }
            return "This file is not a clinic link or sync."
        }
    }
}

/// Applies a link file onto a child. Does not change link state, recordings, diary, or last sync.
enum ClinicLinkApply {
    @MainActor
    static func apply(_ payload: ClinicLinkPayload, in context: ModelContext, selectedChildID: UUID?) throws -> Child {
        let matched = ClinicChildLookup.child(id: payload.profile.id, in: context)
        let selected = selectedChildID.flatMap { ClinicChildLookup.child(id: $0, in: context) }
        guard let child = matched ?? selected else {
            throw ClinicFileError.chooseChild
        }
        child.fullName = payload.profile.fullName
        child.nickname = payload.profile.nickname
        child.birthDate = payload.profile.birthDate
        child.sex = payload.profile.sex
        child.conditionText = payload.profile.conditionText
        child.setupNotes = payload.profile.setupNotes
        if child.schedule == nil {
            let schedule = Schedule()
            context.insert(schedule)
            child.schedule = schedule
        }
        child.schedule?.apply(payload.schedule)
        if let baseline = payload.baseline {
            try upsert(baseline, onto: child, in: context)
        }
        try context.save()
        return child
    }

    @MainActor
    private static func upsert(_ payload: ClinicBaselinePayload, onto child: Child, in context: ModelContext) throws {
        if let existing = child.baselines.first(where: { $0.id == payload.id }) {
            existing.version = payload.version
            existing.fileName = payload.fileName
            existing.recordedAt = payload.recordedAt
            existing.createdAt = payload.createdAt
            existing.recording = payload.recording
            return
        }
        let known = (try? context.fetch(FetchDescriptor<BaselineVersion>())) ?? []
        if known.contains(where: { $0.id == payload.id }) {
            throw ClinicFileError.baselineUsedElsewhere
        }
        let created = BaselineVersion(
            id: payload.id,
            version: payload.version,
            fileName: payload.fileName,
            recordedAt: payload.recordedAt,
            recording: payload.recording,
            createdAt: payload.createdAt
        )
        context.insert(created)
        created.child = child
    }
}

/// File import of a sync envelope. Merges by id and leaves `lastSyncDate` where it is.
enum ClinicSyncImport {
    @MainActor
    @discardableResult
    static func merge(_ payload: ClinicSyncPayload, in context: ModelContext) throws -> Child {
        guard let child = ClinicChildLookup.child(id: payload.childID, in: context) else {
            throw ClinicFileError.unknownChild
        }
        ClinicSyncMerge.mergeRecordings(payload.recordings, into: child)
        ClinicSyncMerge.mergeDiary(payload.diary, into: child)
        try context.save()
        return child
    }
}

enum ClinicTransferFiles {
    static func writeEnvelope(_ envelope: ClinicTransferEnvelope, fileName: String) throws -> URL {
        let data = try ClinicTransferCoding.encode(envelope)
        let folder = try exportDirectory()
        let url = folder.appending(path: fileName)
        try data.write(to: url, options: .atomic)
        return url
    }

    static func exportDirectory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let folder = base.appending(path: "Clinic/Exports", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }
}
