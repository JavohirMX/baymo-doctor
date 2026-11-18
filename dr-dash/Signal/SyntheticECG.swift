import Foundation

/// Deterministic lead built the same way as the parent interval tests.
/// P is a half-sine, QRS is piecewise linear, and T is a half-sine after the QRS.
nonisolated enum SyntheticECG {
    static func samples(
        pr: Int? = 120,
        qrs: Int = 60,
        heartRate: Double = 100,
        seconds: Double = 30,
        sampleRate: Double = 500,
        amplitude: Double = 1,
        tAfterQRS: Int = 120,
        tWidth: Int = 160
    ) -> [Float] {
        let count = Int(seconds * sampleRate)
        guard count > 0, sampleRate > 0, heartRate > 0 else { return [] }
        var values = [Double](repeating: 0, count: count)
        let qrsLength = Double(qrs) / 1000
        let corners: [(time: Double, millivolts: Double)] = [
            (0, 0),
            (0.010, -0.1),
            (qrsLength / 2, 1.2),
            (max(qrsLength - 0.010, qrsLength / 2), -0.25),
            (qrsLength, 0),
        ]

        func add(from start: Double, to end: Double, _ voltage: (Double) -> Double) {
            let first = max(Int((start * sampleRate).rounded(.up)), 0)
            let last = min(Int((end * sampleRate).rounded(.down)), count - 1)
            guard first <= last else { return }
            for index in first...last {
                values[index] += voltage(Double(index) / sampleRate - start)
            }
        }

        var onset = 0.35
        while onset - 0.3 < seconds {
            if let pr {
                let start = onset - Double(pr) / 1000
                add(from: start, to: start + 0.08) { 0.15 * sin(.pi * $0 / 0.08) }
            }
            add(from: onset, to: onset + qrsLength) { dt in
                for (left, right) in zip(corners, corners.dropFirst()) where dt <= right.time {
                    let span = right.time - left.time
                    guard span > 0 else { return right.millivolts }
                    return left.millivolts + (right.millivolts - left.millivolts) * (dt - left.time) / span
                }
                return 0
            }
            let tStart = onset + qrsLength + Double(tAfterQRS) / 1000
            let tLength = Double(tWidth) / 1000
            if tLength > 0 {
                add(from: tStart, to: tStart + tLength) { 0.3 * sin(.pi * $0 / tLength) }
            }
            onset += 60 / heartRate
        }

        let scale = amplitude == 0 ? 1 : amplitude
        return values.map { Float($0 * scale) }
    }

    /// Lead II plus a smaller lead I, so the limb leads can be derived.
    static func payload(
        pr: Int = 140,
        qrs: Int,
        heartRate: Double,
        seconds: Double = 20,
        sampleRate: Double = 500
    ) -> StoredECGPayload {
        let wide = qrs >= 110 || heartRate >= 120
        let leadII = samples(
            pr: pr,
            qrs: qrs,
            heartRate: heartRate,
            seconds: seconds,
            sampleRate: sampleRate,
            tAfterQRS: wide ? 40 : 120,
            tWidth: wide ? 80 : 160
        )
        let leadI = leadII.map { $0 * 0.55 }
        return StoredECGPayload(leads: [
            StoredECGLead(name: ECGLeadName.i, sampleRate: sampleRate, samples: leadI),
            StoredECGLead(name: ECGLeadName.ii, sampleRate: sampleRate, samples: leadII),
        ])
    }
}
