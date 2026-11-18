import Foundation

nonisolated struct BeatAnalysis: Sendable {
    let beatCount: Int
    /// Beats per minute from the median beat-to-beat interval.
    let heartRate: Double?
    /// Coefficient of variation of beat-to-beat intervals. Higher means a less regular rhythm.
    let rhythmVariability: Double?
    /// Mean correlation of each beat with the average beat (0–1). Real heartbeats look alike; noise doesn't.
    let shapeConsistency: Double?
    /// Sample index of each R peak.
    var rPeaks: [Int] = []
    /// The average beat from 0.1 s before to 0.15 s after the R peak, in mV. Nil with fewer than 3 whole beats.
    var averageBeat: [Double]?

    static let empty = BeatAnalysis(beatCount: 0, heartRate: nil, rhythmVariability: nil, shapeConsistency: nil)
}

/// Finds heartbeats (R peaks) in a single-lead ECG.
/// A simplified Pan–Tompkins approach: slope energy, moving-window integration, adaptive threshold.
nonisolated enum BeatDetector {
    static func analyze(_ samples: [Float], sampleRate: Double) -> BeatAnalysis {
        let count = samples.count
        guard sampleRate > 0, count > Int(sampleRate * 2) else { return .empty }

        // Slope energy is the same for upright and inverted beats and ignores slow baseline wander.
        var energy = [Double](repeating: 0, count: count)
        for index in 1..<(count - 1) {
            let slope = Double(samples[index + 1] - samples[index - 1])
            energy[index] = slope * slope
        }

        let window = max(Int(sampleRate * 0.08), 1)
        var integrated = [Double](repeating: 0, count: count)
        var sum = 0.0
        for index in 0..<count {
            sum += energy[index]
            if index >= window { sum -= energy[index - window] }
            integrated[index] = sum / Double(window)
        }

        let sorted = integrated.sorted()
        let reference = sorted[Int(Double(count - 1) * 0.98)]
        guard reference > 0 else { return .empty }
        let threshold = reference * 0.3
        let refractory = Int(sampleRate * 0.2)

        var peaks: [Int] = []
        var index = 0
        while index < count {
            guard integrated[index] > threshold else {
                index += 1
                continue
            }
            var best = index
            var end = index
            while end < count, integrated[end] > threshold {
                if integrated[end] > integrated[best] { best = end }
                end += 1
            }
            if let last = peaks.last, best - last < refractory {
                if integrated[best] > integrated[last] { peaks[peaks.count - 1] = best }
            } else {
                peaks.append(best)
            }
            index = end
        }

        let rPeaks = peaks.map { alignToRPeak($0, samples: samples, window: window, sampleRate: sampleRate) }
        let intervals = zip(rPeaks.dropFirst(), rPeaks).map { Double($0 - $1) / sampleRate }.filter { $0 > 0 }
        guard intervals.count >= 2 else {
            return BeatAnalysis(beatCount: rPeaks.count, heartRate: nil, rhythmVariability: nil, shapeConsistency: nil, rPeaks: rPeaks)
        }
        let median = intervals.sorted()[intervals.count / 2]
        let mean = intervals.reduce(0, +) / Double(intervals.count)
        let variance = intervals.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(intervals.count)
        let shape = beatShape(samples: samples, rPeaks: rPeaks, sampleRate: sampleRate)

        return BeatAnalysis(
            beatCount: rPeaks.count,
            heartRate: 60 / median,
            rhythmVariability: sqrt(variance) / mean,
            shapeConsistency: shape?.consistency,
            rPeaks: rPeaks,
            averageBeat: shape?.average
        )
    }

    /// The integrated peak lags the beat, so look back for the largest deflection.
    private static func alignToRPeak(_ peak: Int, samples: [Float], window: Int, sampleRate: Double) -> Int {
        let start = max(peak - window - Int(sampleRate * 0.05), 0)
        let end = min(peak, samples.count - 1)
        guard start < end else { return peak }
        let segment = samples[start...end]
        let mean = segment.reduce(0, +) / Float(segment.count)
        var best = start
        for index in start...end where abs(samples[index] - mean) > abs(samples[best] - mean) {
            best = index
        }
        return best
    }

    /// The average beat, and how closely each beat matches it.
    private static func beatShape(samples: [Float], rPeaks: [Int], sampleRate: Double) -> (average: [Double], consistency: Double)? {
        let before = Int(sampleRate * 0.1)
        let after = Int(sampleRate * 0.15)
        let beats: [[Double]] = rPeaks.compactMap { peak in
            guard peak - before >= 0, peak + after < samples.count else { return nil }
            return samples[(peak - before)...(peak + after)].map(Double.init)
        }
        guard beats.count >= 3 else { return nil }
        let length = beats[0].count
        var template = [Double](repeating: 0, count: length)
        for beat in beats {
            for index in 0..<length { template[index] += beat[index] / Double(beats.count) }
        }
        let correlations = beats.map { correlation($0, template) }
        return (template, correlations.reduce(0, +) / Double(correlations.count))
    }

    static func correlation(_ a: [Double], _ b: [Double]) -> Double {
        let count = Double(min(a.count, b.count))
        guard count > 1 else { return 0 }
        let meanA = a.reduce(0, +) / count
        let meanB = b.reduce(0, +) / count
        var covariance = 0.0
        var varianceA = 0.0
        var varianceB = 0.0
        for (x, y) in zip(a, b) {
            covariance += (x - meanA) * (y - meanB)
            varianceA += (x - meanA) * (x - meanA)
            varianceB += (y - meanB) * (y - meanB)
        }
        guard varianceA > 0, varianceB > 0 else { return 0 }
        return covariance / sqrt(varianceA * varianceB)
    }
}

/// Compares average beats recorded at different sample rates.
nonisolated enum BeatShape {
    /// Resamples a beat to `count` points by linear interpolation.
    static func resampled(_ beat: [Double], to count: Int) -> [Double] {
        guard beat.count > 1, count > 1 else { return beat }
        return (0..<count).map { index in
            let position = Double(index) * Double(beat.count - 1) / Double(count - 1)
            let lower = Int(position)
            let upper = min(lower + 1, beat.count - 1)
            let fraction = position - Double(lower)
            return beat[lower] * (1 - fraction) + beat[upper] * fraction
        }
    }

    /// Correlation (−1…1) of two average beats, after bringing them to the same length.
    static func similarity(_ a: [Double], _ b: [Double]) -> Double {
        BeatDetector.correlation(resampled(a, to: 64), resampled(b, to: 64))
    }
}
