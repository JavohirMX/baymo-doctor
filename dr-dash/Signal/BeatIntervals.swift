import Foundation

/// Heart rate, RR, PR and QRS of one lead. A nil number shows as "—": the app would rather say nothing than guess.
///
/// R peaks come from `BeatDetector`. RR is their median spacing. PR and QRS are measured once, on a long average
/// beat (−0.30 s to +0.40 s around R): QRS onset and offset where its slope falls below a share of the steepest
/// slope, and P as the last deflection above noise in the 300 ms before QRS onset.
nonisolated struct BeatIntervals: Equatable, Sendable {
    var lead: ECGLead
    /// Beats per minute, from the median RR.
    var heartRate: Int?
    /// Milliseconds, median.
    var rr: Int?
    /// Milliseconds; nil when no consistent P wave is found, which is common during SVT.
    var pr: Int?
    /// Milliseconds.
    var qrs: Int?

    /// Draft, ask RSAB. Fewer beats than this measures nothing.
    static let minimumBeats = 10
    /// Draft, ask RSAB. Above this heart rate, in bpm, PR and QRS are nil: the waves of neighbouring beats
    /// overlap too much to measure on an average beat. Heart rate and RR are still reported.
    static let maxRateForIntervals = 180
    /// The long average beat, in seconds before and after R.
    static let averageBefore = 0.30
    static let averageAfter = 0.40
    /// How far before QRS onset to look for P, in seconds.
    static let pSearch = 0.30
    /// Draft, ask RSAB. QRS onset and offset are where the slope falls below this share of the steepest QRS slope.
    static let qrsSlopeFraction = 0.10
    /// Draft, ask RSAB. How far from the baseline the trace may be just before QRS onset, in mV. Further, the
    /// QRS starts on another wave and its start can't be placed.
    static let qrsStartTolerance = 0.05
    /// Draft, ask RSAB. How far from the baseline QRS offset (the J point) may be, in mV. It allows for ST
    /// elevation or depression; further, the QRS end has run on up the next wave.
    static let qrsEndTolerance = 0.20
    /// Draft, ask RSAB. A QRS outside this, in seconds, is a failed measurement rather than a finding.
    static let plausibleQRS = 0.03...0.20
    /// Draft, ask RSAB. The smallest P wave that counts, in mV.
    static let minimumPAmplitude = 0.03
    /// Draft, ask RSAB. A deflection outside this, in seconds, isn't a P wave on its own (a P merged with a T wave is longer).
    static let plausiblePDuration = 0.03...0.12
    /// Draft, ask RSAB. How long the trace must stay flat at the baseline just before P onset, in seconds.
    static let flatBeforeP = 0.02
    /// Draft, ask RSAB. The beats' QRS complexes must match the average this closely (median correlation)
    /// for PR and QRS to be measured.
    static let minimumQRSAgreement = 0.9
    /// A wave, or a slope, must be this many times the noise of the average beat.
    static let noiseMargin = 5.0
    /// Sample rates the measurement accepts, in Hz. The vest records at 500 and Apple Watch at 512; far
    /// outside this the numbers would mean nothing.
    static let measurableSampleRates = 100.0...10_000

    /// Lead II, else lead I; nil when the recording has neither.
    static func measure(_ recording: ECGRecording) -> BeatIntervals? {
        guard let channel = recording.channel(.ii) ?? recording.channel(.i) else { return nil }
        return measure(channel.waveform, lead: channel.lead)
    }

    static func measure(_ waveform: Waveform, lead: ECGLead) -> BeatIntervals {
        var result = BeatIntervals(lead: lead)
        let sampleRate = waveform.sampleRate
        guard measurableSampleRates.contains(sampleRate) else { return result }

        let beats = BeatDetector.analyze(waveform.samples, sampleRate: sampleRate)
        // Too few beats, or "beats" that don't look alike (noise, movement): nothing to measure.
        guard beats.rPeaks.count >= minimumBeats,
              (beats.shapeConsistency ?? 0) >= RecordingQualityCheck.minimumShapeConsistency else { return result }
        let intervals = zip(beats.rPeaks.dropFirst(), beats.rPeaks).map { $0 - $1 }.filter { $0 > 0 }.sorted()
        guard !intervals.isEmpty else { return result }
        let middle = intervals.count / 2
        let medianRR = intervals.count.isMultiple(of: 2)
            ? Double(intervals[middle - 1] + intervals[middle]) / 2
            : Double(intervals[middle])
        result.rr = milliseconds(medianRR, sampleRate)
        let heartRate = Int((60 * sampleRate / medianRR).rounded())
        result.heartRate = heartRate
        guard heartRate <= maxRateForIntervals else { return result }

        guard let average = LongAverage(waveform.samples, sampleRate: sampleRate, rPeaks: beats.rPeaks) else { return result }
        let rr = Int(medianRR.rounded())
        guard let qrs = qrsBounds(average, rr: rr) else { return result }
        result.qrs = milliseconds(Double(qrs.offset - qrs.onset), sampleRate)
        if let pOnset = pOnset(average, qrs: qrs, rr: rr) {
            result.pr = milliseconds(Double(qrs.onset - pOnset), sampleRate)
        }
        return result
    }

    /// The mean beat from -0.30 s to +0.40 s around each R peak; nil with fewer than 3 usable beats.
    /// Also nil outside `measurableSampleRates`. Peaks are first aligned on one wave of the QRS (see `LongAverage.aligned`).
    static func longAverageBeat(_ samples: [Float], sampleRate: Double, rPeaks: [Int]) -> [Double]? {
        LongAverage(samples, sampleRate: sampleRate, rPeaks: rPeaks)?.beat
    }

    private static func milliseconds(_ samples: Double, _ sampleRate: Double) -> Int {
        Int((samples / sampleRate * 1000).rounded())
    }

    private static func samples(_ seconds: Double, _ sampleRate: Double) -> Int {
        Int((seconds * sampleRate).rounded())
    }

    // MARK: QRS

    /// QRS onset and offset as indices into the average beat.
    ///
    /// At a child's fast rate (RR down to about 330 ms) the +0.40 s window holds the next beat's QRS, and the
    /// −0.30 s side the previous beat's T wave. So the search stays within half an RR of R: the steepest slope
    /// is this beat's own, and the offset search can't run on into the next beat. Finding no quiet stretch
    /// within that reach gives nil, never the reach itself.
    private static func qrsBounds(_ average: LongAverage, rr: Int) -> (onset: Int, offset: Int)? {
        let slope = average.slope
        let r = average.rIndex
        let reach = max(rr / 2, 1)
        let lower = max(r - reach, average.slopeSpan)
        let upper = min(r + reach, slope.count - 1 - average.slopeSpan)
        guard lower < r, r < upper else { return nil }

        // Beats whose QRS doesn't match the average (still misaligned, or changing shape) give no QRS.
        guard average.qrsAgreement >= minimumQRSAgreement else { return nil }

        let steepest = slope[lower...upper].map(abs).max() ?? 0
        let threshold = qrsSlopeFraction * steepest
        // Too noisy to tell where the QRS starts and ends.
        guard steepest > 0, noiseMargin * average.slopeNoise < threshold else { return nil }

        let quiet = max(samples(0.010, average.sampleRate), 2)
        guard let onset = edge(of: slope, from: r, step: -1, limit: lower, threshold: threshold, quiet: quiet),
              let offset = edge(of: slope, from: r, step: 1, limit: upper, threshold: threshold, quiet: quiet)
        else { return nil }
        // The QRS must start from the baseline: the 10 ms before it sit at the baseline. When they don't, another
        // wave runs into this QRS (the previous T wave at a fast rate, or a P wave with no PR segment) and the
        // walk may have gone up that wave.
        let junction = average.beat[max(onset - quiet, 0)..<onset]
        guard !junction.isEmpty,
              abs(junction.reduce(0, +) / Double(junction.count) - average.baseline) <= qrsStartTolerance else { return nil }
        // Likewise the QRS must end near the baseline. Ending far off it, the walk has run on up the next wave.
        guard abs(average.beat[offset] - average.baseline) <= qrsEndTolerance else { return nil }
        // A QRS can't take up more than half the cycle; when it seems to, a T wave has merged into it.
        guard 2 * (offset - onset) <= rr, plausibleQRS.contains(Double(offset - onset) / average.sampleRate) else { return nil }
        return (onset, offset)
    }

    /// Walks out from R and returns the last steep sample (slope at or above the threshold) before `quiet`
    /// samples in a row below it. The quiet run only counts once a steep sample has been passed, so a
    /// flat-topped R doesn't end the QRS.
    private static func edge(of slope: [Double], from start: Int, step: Int, limit: Int, threshold: Double, quiet: Int) -> Int? {
        var lastSteep: Int?
        var quietCount = 0
        var index = start
        while step < 0 ? index >= limit : index <= limit {
            if abs(slope[index]) >= threshold {
                lastSteep = index
                quietCount = 0
            } else if lastSteep != nil {
                quietCount += 1
                if quietCount == quiet { return lastSteep }
            }
            index += step
        }
        return nil
    }

    // MARK: P

    /// P onset as an index into the average beat, or nil when there's no clear P wave on its own.
    ///
    /// P is the last deflection from the baseline before the QRS, searched from 300 ms before QRS onset but
    /// never before the previous beat's T wave has ended (this beat's T end, one RR earlier). At a fast rate
    /// that leaves no room, and a P buried in the T wave gives nil. So does a deflection that runs into the
    /// QRS, doesn't rise from a flat baseline, or is too short or too long for a P wave.
    private static func pOnset(_ average: LongAverage, qrs: (onset: Int, offset: Int), rr: Int) -> Int? {
        let beat = average.beat
        let sampleRate = average.sampleRate
        let deviation = beat.map { abs($0 - average.baseline) }
        let threshold = average.smallestWave

        var start = max(0, qrs.onset - samples(pSearch, sampleRate), qrs.offset - rr + 1)
        if let tEnd = tEnd(deviation, qrs: qrs, rr: rr, threshold: threshold, noise: average.noise) {
            start = max(start, tEnd - rr + 1)
        }
        // The 10 ms before QRS onset can hold the very start of a smooth QRS, so P must end before them.
        let end = qrs.onset - 1 - samples(0.010, sampleRate)
        guard end - start >= samples(plausiblePDuration.lowerBound, sampleRate) else { return nil }

        // Join the last deflection with any just before it, so a biphasic P counts as one wave.
        let runs = deflections(deviation, in: start...end, above: threshold)
        guard var wave = runs.last else { return nil }
        let gap = samples(0.020, sampleRate)
        for run in runs.dropLast().reversed() {
            guard wave.lowerBound - run.upperBound <= gap else { break }
            wave = run.lowerBound...wave.upperBound
        }
        // A deflection running into the QRS isn't a P wave on its own.
        guard wave.upperBound < end else { return nil }

        // Widen to where the wave fades to a tenth of its height, or to the noise.
        let peak = deviation[wave].max() ?? 0
        let fade = max(0.1 * peak, 2 * average.noise)
        var onset = wave.lowerBound
        while onset > start, deviation[onset - 1] > fade { onset -= 1 }
        var offset = wave.upperBound
        while offset < end, deviation[offset + 1] > fade { offset += 1 }

        // P must rise from a flat stretch of baseline. A deflection already under way where the search starts,
        // or riding on the previous T wave, isn't a P wave on its own.
        let flat = samples(flatBeforeP, sampleRate)
        guard onset - flat >= start else { return nil }
        let before = (onset - flat)..<onset
        guard deviation[before].allSatisfy({ $0 <= threshold }),
              let low = beat[before].min(), let high = beat[before].max(), high - low <= threshold else { return nil }

        let duration = Double(offset - onset) / sampleRate
        return plausiblePDuration.contains(duration) ? onset : nil
    }

    /// Where this beat's T wave ends: the end of the largest deflection between QRS offset and the next beat's
    /// QRS onset, so the next QRS isn't taken for it. Nil when there's no deflection there.
    private static func tEnd(_ deviation: [Double], qrs: (onset: Int, offset: Int), rr: Int, threshold: Double, noise: Double) -> Int? {
        let start = qrs.offset + 1
        let end = min(deviation.count - 1, qrs.onset + rr - 1)
        guard start < end else { return nil }
        let runs = deflections(deviation, in: start...end, above: threshold)
        guard let wave = runs.max(by: { (deviation[$0].max() ?? 0) < (deviation[$1].max() ?? 0) }) else { return nil }
        let fade = max(0.1 * (deviation[wave].max() ?? 0), 2 * noise)
        var offset = wave.upperBound
        while offset < end, deviation[offset + 1] > fade { offset += 1 }
        return offset
    }

    /// Runs of samples above the threshold, in order.
    private static func deflections(_ deviation: [Double], in range: ClosedRange<Int>, above threshold: Double) -> [ClosedRange<Int>] {
        var runs: [ClosedRange<Int>] = []
        var runStart: Int?
        for index in range {
            if deviation[index] > threshold {
                if runStart == nil { runStart = index }
            } else if let first = runStart {
                runs.append(first...(index - 1))
                runStart = nil
            }
        }
        if let first = runStart { runs.append(first...range.upperBound) }
        return runs
    }
}

/// The long average beat, its slope, its baseline, and how noisy it is.
private nonisolated struct LongAverage {
    let sampleRate: Double
    /// Mean of the beats, in mV. R is at `rIndex`.
    let beat: [Double]
    let rIndex: Int
    /// Slope of `beat` in mV/s, as a central difference over ±`slopeSpan` samples. Zero at the ends.
    let slope: [Double]
    let slopeSpan: Int
    /// Standard error of the mean, in mV, and of the slope, in mV/s: the median over the window.
    let noise: Double
    let slopeNoise: Double
    /// The smallest deflection that counts as a wave, in mV: the smallest P wave, or more when it's noisy.
    let smallestWave: Double
    /// The level the trace spends the most time at, within ±`smallestWave`, in mV.
    let baseline: Double
    /// The median correlation (−1…1) of each beat's QRS, R ± 60 ms, with the average's.
    let qrsAgreement: Double

    init?(_ samples: [Float], sampleRate: Double, rPeaks: [Int]) {
        guard BeatIntervals.measurableSampleRates.contains(sampleRate) else { return nil }
        let before = Int((BeatIntervals.averageBefore * sampleRate).rounded())
        let after = Int((BeatIntervals.averageAfter * sampleRate).rounded())
        let reach = Int((Self.alignmentReach * sampleRate).rounded())
        let peaks = Self.aligned(rPeaks, in: samples, reach: reach).filter { $0 - before >= 0 && $0 + after < samples.count }
        guard peaks.count >= 3 else { return nil }
        let length = before + after + 1
        let span = max(Int((0.004 * sampleRate).rounded()), 1)
        guard length > 2 * span else { return nil }
        let count = Double(peaks.count)

        var mean = [Double](repeating: 0, count: length)
        for peak in peaks {
            let first = peak - before
            for index in 0..<length { mean[index] += Double(samples[first + index]) }
        }
        for index in 0..<length { mean[index] /= count }

        func centralDifference(_ value: (Int) -> Double, at index: Int) -> Double {
            (value(index + span) - value(index - span)) * sampleRate / Double(2 * span)
        }
        var meanSlope = [Double](repeating: 0, count: length)
        for index in span..<(length - span) { meanSlope[index] = centralDifference({ mean[$0] }, at: index) }

        // Spread of the beats around the mean, sample by sample.
        var squares = [Double](repeating: 0, count: length)
        var slopeSquares = [Double](repeating: 0, count: length)
        for peak in peaks {
            let first = peak - before
            func value(_ index: Int) -> Double { Double(samples[first + index]) }
            for index in 0..<length {
                let difference = value(index) - mean[index]
                squares[index] += difference * difference
            }
            for index in span..<(length - span) {
                let difference = centralDifference(value, at: index) - meanSlope[index]
                slopeSquares[index] += difference * difference
            }
        }
        func medianStandardError(_ squares: ArraySlice<Double>) -> Double {
            let errors = squares.map { ($0 / (count - 1) / count).squareRoot() }.sorted()
            return errors[errors.count / 2]
        }

        self.sampleRate = sampleRate
        beat = mean
        rIndex = before
        slope = meanSlope
        slopeSpan = span
        noise = medianStandardError(squares[...])
        slopeNoise = medianStandardError(slopeSquares[span..<(length - span)])
        smallestWave = max(BeatIntervals.minimumPAmplitude, BeatIntervals.noiseMargin * noise)

        // The most-held level: the band ±smallestWave wide that holds the most samples.
        let ordered = mean.sorted()
        var best = 0...0
        var low = 0
        for high in ordered.indices {
            while ordered[high] - ordered[low] > 2 * smallestWave { low += 1 }
            if high - low > best.count - 1 { best = low...high }
        }
        baseline = ordered[(best.lowerBound + best.upperBound) / 2]

        // How alike the beats' QRS complexes are, around R: the median correlation of each with the average.
        let qrsRegion = max(before - reach, 0)...min(before + reach, length - 1)
        let averageQRS = Array(mean[qrsRegion])
        let correlations = peaks.map { peak in
            BeatDetector.correlation(qrsRegion.map { Double(samples[peak - before + $0]) }, averageQRS)
        }.sorted()
        qrsAgreement = correlations[correlations.count / 2]
    }

    /// How far a peak may move when it's aligned, in seconds: more than the gap between a QRS's R and S waves.
    static let alignmentReach = 0.06

    /// `BeatDetector` puts each peak on the QRS wave furthest from the local mean. When the up and down waves
    /// are about the same size (R ≈ S, or q ≈ R, common in a child's lead I) that choice flips from beat to beat,
    /// and averaging both would give two QRS complexes side by side, measured as one wide one. So every peak
    /// moves to the highest point within `reach` samples if most peaks are on an upward wave, or the lowest if
    /// most are on a downward one. Peaks outside the samples are dropped.
    static func aligned(_ peaks: [Int], in samples: [Float], reach: Int) -> [Int] {
        let windows = peaks.filter { samples.indices.contains($0) }.map { peak in
            (peak: peak, window: max(peak - reach, 0)...min(peak + reach, samples.count - 1))
        }
        let upward = windows.filter { entry in
            let mean = samples[entry.window].reduce(0, +) / Float(entry.window.count)
            return samples[entry.peak] >= mean
        }.count
        let mostlyUpward = 2 * upward >= windows.count
        return windows.map { entry in
            entry.window.max { mostlyUpward ? samples[$0] < samples[$1] : samples[$0] > samples[$1] } ?? entry.peak
        }
    }
}
