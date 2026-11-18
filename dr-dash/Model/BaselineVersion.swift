import Foundation
import SwiftData

/// One baseline file. Replacing a baseline adds a version; older versions stay.
@Model
final class BaselineVersion {
    @Attribute(.unique) var id: UUID
    var version: Int
    var fileName: String
    var recordedAt: Date
    var createdAt: Date
    /// Encoded `StoredECGPayload`.
    @Attribute(.externalStorage) var recordingData: Data

    var child: Child?

    init(
        id: UUID = UUID(),
        version: Int,
        fileName: String,
        recordedAt: Date,
        recording: StoredECGPayload,
        createdAt: Date = .now
    ) {
        self.id = id
        self.version = version
        self.fileName = fileName
        self.recordedAt = recordedAt
        self.createdAt = createdAt
        self.recordingData = (try? recording.encode()) ?? Data()
    }

    var recording: StoredECGPayload {
        get { (try? StoredECGPayload.decode(recordingData)) ?? .empty }
        set {
            if let data = try? newValue.encode() {
                recordingData = data
            }
        }
    }

    /// Inserts the next version on `child`. Older versions remain.
    @discardableResult
    static func addVersion(
        to child: Child,
        fileName: String,
        recordedAt: Date,
        recording: StoredECGPayload,
        createdAt: Date = .now
    ) -> BaselineVersion {
        let next = (child.baselines.map(\.version).max() ?? 0) + 1
        let version = BaselineVersion(
            version: next,
            fileName: fileName,
            recordedAt: recordedAt,
            recording: recording,
            createdAt: createdAt
        )
        child.modelContext?.insert(version)
        version.child = child
        return version
    }
}
