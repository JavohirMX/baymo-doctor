import Foundation

/// A recorded ECG trace in millivolts.
nonisolated struct Waveform: Codable, Equatable, Sendable {
    var samples: [Float]
    var sampleRate: Double

    var duration: TimeInterval {
        sampleRate > 0 ? Double(samples.count) / sampleRate : 0
    }

    init(samples: [Float], sampleRate: Double) {
        self.samples = samples
        self.sampleRate = sampleRate
    }

    private enum CodingKeys: String, CodingKey {
        case samples, sampleRate
    }

    /// Samples are stored as raw little-endian Float32 bytes (iOS targets are little-endian).
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let data = try container.decode(Data.self, forKey: .samples)
        guard data.count % MemoryLayout<Float>.size == 0 else {
            throw DecodingError.dataCorruptedError(
                forKey: .samples, in: container,
                debugDescription: "Sample data is not a whole number of Float32 values")
        }
        var decoded = [Float](repeating: 0, count: data.count / MemoryLayout<Float>.size)
        decoded.withUnsafeMutableBytes { _ = data.copyBytes(to: $0) }
        samples = decoded
        sampleRate = try container.decode(Double.self, forKey: .sampleRate)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        let data = samples.withUnsafeBytes { Data($0) }
        try container.encode(data, forKey: .samples)
        try container.encode(sampleRate, forKey: .sampleRate)
    }
}
