import Foundation

/// Canonical lead names, matching the parent app. The later ECG port can add its own lead type.
nonisolated enum ECGLeadName {
    static let i = "I"
    static let ii = "II"
    static let iii = "III"
    static let aVR = "aVR"
    static let aVL = "aVL"
    static let aVF = "aVF"
    static let v1 = "V1"
    static let v2 = "V2"
    static let v3 = "V3"
    static let v4 = "V4"
    static let v5 = "V5"
    static let v6 = "V6"
    static let all = [i, ii, iii, aVR, aVL, aVF, v1, v2, v3, v4, v5, v6]
}

/// One stored lead. `samples` are millivolts, oldest first.
nonisolated struct StoredECGLead: Codable, Equatable, Sendable, Identifiable {
    var name: String
    var sampleRate: Double
    var samples: [Float]

    var id: String { name }

    var duration: TimeInterval {
        sampleRate > 0 ? Double(samples.count) / sampleRate : 0
    }
}

/// Plotting payload for a baseline or a clinic recording.
/// Encoded with `ClinicTransferCoding` and kept on the model as `Data`.
nonisolated struct StoredECGPayload: Codable, Equatable, Sendable {
    var leads: [StoredECGLead]

    static let empty = StoredECGPayload(leads: [])

    var duration: TimeInterval {
        leads.map(\.duration).max() ?? 0
    }

    func lead(_ name: String) -> StoredECGLead? {
        leads.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    func encode() throws -> Data {
        try ClinicTransferCoding.encoder().encode(self)
    }

    static func decode(_ data: Data) throws -> StoredECGPayload {
        try ClinicTransferCoding.decoder().decode(StoredECGPayload.self, from: data)
    }
}
