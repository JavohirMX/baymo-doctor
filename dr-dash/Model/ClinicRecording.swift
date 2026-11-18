import Foundation
import SwiftData

/// One recording or missed check. `id` is the parent's id and is the sync merge key.
@Model
final class ClinicRecording {
    @Attribute(.unique) var id: UUID
    var startDate: Date
    /// Length in seconds. A missed check may be zero and have no samples.
    var duration: TimeInterval
    var parentStatusRaw: String
    var heartRate: Int?
    /// PR interval in milliseconds, when the phone measured one.
    var prMS: Int?
    /// QRS duration in milliseconds, when the phone measured one.
    var qrsMS: Int?
    /// QRS axis in degrees, when two limb leads existed. Nil means the chart shows an em dash.
    var axisDegrees: Int?
    /// The phone's quality words. Empty when the payload did not include any.
    var signalQuality: String
    var reviewed: Bool = false
    /// Stays on this Mac. Sync never overwrites it.
    var doctorNote: String
    /// Encoded `StoredECGPayload` for the ECG paper view. Summary fields above are enough for trends.
    @Attribute(.externalStorage) var samplesData: Data

    var child: Child?

    init(
        id: UUID = UUID(),
        startDate: Date,
        duration: TimeInterval,
        parentStatus: ParentRecordingStatus,
        heartRate: Int? = nil,
        prMS: Int? = nil,
        qrsMS: Int? = nil,
        axisDegrees: Int? = nil,
        signalQuality: String = "",
        reviewed: Bool = false,
        doctorNote: String = "",
        samples: StoredECGPayload = .empty
    ) {
        self.id = id
        self.startDate = startDate
        self.duration = duration
        self.parentStatusRaw = parentStatus.rawValue
        self.heartRate = heartRate
        self.prMS = prMS
        self.qrsMS = qrsMS
        self.axisDegrees = axisDegrees
        self.signalQuality = signalQuality
        self.reviewed = reviewed
        self.doctorNote = doctorNote
        self.samplesData = (try? samples.encode()) ?? Data()
    }

    var parentStatus: ParentRecordingStatus {
        get { ParentRecordingStatus(rawValue: parentStatusRaw) ?? .notAnalyzed }
        set { parentStatusRaw = newValue.rawValue }
    }

    var samples: StoredECGPayload {
        get { (try? StoredECGPayload.decode(samplesData)) ?? .empty }
        set {
            if let data = try? newValue.encode() {
                samplesData = data
            }
        }
    }

    var attentionRecording: ClinicAttentionRecording {
        ClinicAttentionRecording(
            id: id,
            startDate: startDate,
            parentStatus: parentStatus,
            reviewed: reviewed
        )
    }

    /// Copies phone-owned fields. Leaves `reviewed` and `doctorNote` as they are on this Mac.
    func applyPhoneFields(from payload: ClinicRecordingPayload) {
        startDate = payload.startDate
        duration = payload.duration
        parentStatus = payload.parentStatus
        heartRate = payload.heartRate
        prMS = payload.prMS
        qrsMS = payload.qrsMS
        axisDegrees = payload.axisDegrees
        signalQuality = payload.signalQuality
        samples = payload.samples
    }

    @discardableResult
    static func add(
        to child: Child,
        id: UUID = UUID(),
        startDate: Date,
        duration: TimeInterval,
        parentStatus: ParentRecordingStatus,
        heartRate: Int? = nil,
        prMS: Int? = nil,
        qrsMS: Int? = nil,
        axisDegrees: Int? = nil,
        signalQuality: String = "",
        reviewed: Bool = false,
        doctorNote: String = "",
        samples: StoredECGPayload = .empty
    ) -> ClinicRecording {
        let recording = ClinicRecording(
            id: id,
            startDate: startDate,
            duration: duration,
            parentStatus: parentStatus,
            heartRate: heartRate,
            prMS: prMS,
            qrsMS: qrsMS,
            axisDegrees: axisDegrees,
            signalQuality: signalQuality,
            reviewed: reviewed,
            doctorNote: doctorNote,
            samples: samples
        )
        child.modelContext?.insert(recording)
        recording.child = child
        return recording
    }
}
