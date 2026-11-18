import Foundation

/// Draft band around the child's current baseline measurement.
///
/// Heart rate is changed when it is more than 20 bpm away.
/// QRS is changed when it is more than 15 ms away.
/// A missing number on either side is not a change, and it is not replaced with a guess.
nonisolated enum ECGChangeBand {
    static let heartRateBPM = 20
    static let qrsMilliseconds = 15

    static func heartRateChanged(_ heartRate: Int?, baseline: Int?) -> Bool {
        guard let heartRate, let baseline else { return false }
        return abs(heartRate - baseline) > heartRateBPM
    }

    static func qrsChanged(_ qrs: Int?, baseline: Int?) -> Bool {
        guard let qrs, let baseline else { return false }
        return abs(qrs - baseline) > qrsMilliseconds
    }

    static func sentence(
        heartRateChanged: Bool,
        qrsChanged: Bool,
        canCompareHeartRate: Bool,
        canCompareQRS: Bool,
        storedWithRecording: Bool
    ) -> String {
        var parts: [String] = []
        if heartRateChanged, qrsChanged {
            parts.append("Heart rate and QRS changed.")
        } else if heartRateChanged {
            parts.append("Heart rate changed.")
        } else if qrsChanged {
            parts.append("QRS changed.")
        } else if canCompareHeartRate, canCompareQRS {
            parts.append("Heart rate and QRS are unchanged.")
        } else if canCompareHeartRate {
            parts.append("Heart rate is unchanged.")
        } else if canCompareQRS {
            parts.append("QRS is unchanged.")
        }
        if storedWithRecording {
            parts.append("Heart rate, PR, and QRS were stored with the recording.")
        }
        if parts.isEmpty {
            return "Heart rate and QRS could not be compared with the baseline."
        }
        return parts.joined(separator: " ")
    }
}

/// Paper speed and gain for the clinic strip. The trace itself is only a few seconds.
nonisolated enum ECGPaper {
    static let millimetersPerSecond = 25.0
    static let millimetersPerMillivolt = 10.0
    /// Inside the 2.5–4 second strip. The calibration pulse sits in front of this.
    static let stripSeconds = 3.0
    static let calibrationSeconds = 0.2
    static let calibrationGapSeconds = 0.04
    static let calibrationMillivolts = 1.0
    static let heightMillimeters = 50.0
    static let maximumPointsPerMillimeter = 6.5

    static var originSeconds: Double { calibrationSeconds + calibrationGapSeconds }
    static var contentSeconds: Double { originSeconds + stripSeconds }
    static var widthMillimeters: Double { contentSeconds * millimetersPerSecond }
    static var maximumWidth: Double { widthMillimeters * maximumPointsPerMillimeter }
}

/// Heart rate, PR, and QRS saved on the clinic recording. Used only when `BeatIntervals` returns nil.
nonisolated struct ECGStoredIntervals: Sendable {
    var heartRate: Int?
    var prMS: Int?
    var qrsMS: Int?
}

/// One interval drawn on the recording strip. The width is the measured number of milliseconds.
nonisolated struct ECGCaliperMark: Equatable, Sendable {
    var start: TimeInterval
    var end: TimeInterval
    var milliseconds: Int
    var title: String
}

/// The few seconds of one lead that the paper draws.
nonisolated struct ECGStripDrawing: Equatable, Sendable {
    var waveform: Waveform
    /// Chosen R peak, in seconds from the start of `waveform`.
    var rOffset: TimeInterval?
    var pr: ECGCaliperMark?
    var qrs: ECGCaliperMark?

    static let empty = ECGStripDrawing(
        waveform: Waveform(samples: [], sampleRate: 0),
        rOffset: nil,
        pr: nil,
        qrs: nil
    )
}

/// Numbers and strips for one open recording. Heart rate, PR, and QRS come from `BeatIntervals` on lead II, else lead I.
nonisolated struct ECGReading: Equatable, Sendable {
    var recordingID: UUID?
    var lead: ECGLead
    var compareID: UUID?
    var heartRate: Int?
    var prMS: Int?
    var qrsMS: Int?
    var axisDegrees: Int?
    var baselineHeartRate: Int?
    var baselinePRMS: Int?
    var baselineQRSMS: Int?
    var baselineAxisDegrees: Int?
    var storedWithRecording: Bool
    var heartRateChanged: Bool
    var qrsChanged: Bool
    /// Lead II or lead I when `BeatIntervals` produced the row. Nil when the stored numbers are shown instead.
    var measurementLead: ECGLead?
    var strip: ECGStripDrawing
    var compareStrip: ECGStripDrawing?
    var compareMissingLead: Bool
    var sentence: String
    var isReady: Bool

    var changed: Bool { heartRateChanged || qrsChanged }

    static let placeholder = ECGReading(
        recordingID: nil,
        lead: .ii,
        compareID: nil,
        heartRate: nil,
        prMS: nil,
        qrsMS: nil,
        axisDegrees: nil,
        baselineHeartRate: nil,
        baselinePRMS: nil,
        baselineQRSMS: nil,
        baselineAxisDegrees: nil,
        storedWithRecording: false,
        heartRateChanged: false,
        qrsChanged: false,
        measurementLead: nil,
        strip: .empty,
        compareStrip: nil,
        compareMissingLead: false,
        sentence: "",
        isReady: false
    )
}

nonisolated enum ECGViewerMeasurement {
    static func reading(
        recordingID: UUID,
        payload: StoredECGPayload,
        stored: ECGStoredIntervals,
        baseline: StoredECGPayload,
        compare: StoredECGPayload?,
        compareID: UUID?,
        lead: ECGLead
    ) -> ECGReading {
        let trace = ECGRecording(payload: payload, id: recordingID)
        let intervals = intervals(of: trace, stored: stored)
        let axis = axisDegrees(of: trace)
        let baselineTrace = ECGRecording(payload: baseline)
        let baselineMeasured = measuredIntervals(baselineTrace)
        let baselineAxis = axisDegrees(of: baselineTrace)
        let heartRateChanged = ECGChangeBand.heartRateChanged(intervals.heartRate, baseline: baselineMeasured.heartRate)
        let qrsChanged = ECGChangeBand.qrsChanged(intervals.qrs, baseline: baselineMeasured.qrs)
        let measurementWaveform = trace.channel(.ii)?.waveform ?? trace.channel(.i)?.waveform
        let strip: ECGStripDrawing
        if let display = trace.channel(lead)?.waveform {
            strip = stripDrawing(
                display: display,
                anchor: measurementWaveform,
                pr: intervals.pr,
                qrs: intervals.qrs
            )
        } else {
            strip = .empty
        }

        var compareStrip: ECGStripDrawing?
        var compareMissingLead = false
        if compareID != nil {
            if let compare, let display = ECGRecording(payload: compare).channel(lead)?.waveform {
                compareStrip = stripDrawing(display: display, anchor: nil, pr: nil, qrs: nil)
            } else {
                compareMissingLead = true
            }
        }

        return ECGReading(
            recordingID: recordingID,
            lead: lead,
            compareID: compareID,
            heartRate: intervals.heartRate,
            prMS: intervals.pr,
            qrsMS: intervals.qrs,
            axisDegrees: axis,
            baselineHeartRate: baselineMeasured.heartRate,
            baselinePRMS: baselineMeasured.pr,
            baselineQRSMS: baselineMeasured.qrs,
            baselineAxisDegrees: baselineAxis,
            storedWithRecording: intervals.storedWithRecording,
            heartRateChanged: heartRateChanged,
            qrsChanged: qrsChanged,
            measurementLead: intervals.measurementLead,
            strip: strip,
            compareStrip: compareStrip,
            compareMissingLead: compareMissingLead,
            sentence: ECGChangeBand.sentence(
                heartRateChanged: heartRateChanged,
                qrsChanged: qrsChanged,
                canCompareHeartRate: intervals.heartRate != nil && baselineMeasured.heartRate != nil,
                canCompareQRS: intervals.qrs != nil && baselineMeasured.qrs != nil,
                storedWithRecording: intervals.storedWithRecording
            ),
            isReady: true
        )
    }

    /// Lead I against aVF when that lead is stored, otherwise lead II.
    /// One limb lead is not enough, so the result stays nil instead of a guessed angle.
    static func axisDegrees(of recording: ECGRecording) -> Int? {
        guard let horizontal = recording.channel(.i)?.waveform else { return nil }
        let vertical: Waveform?
        if recording.storedLeads.contains(.aVF) {
            vertical = recording.channel(.aVF)?.waveform
        } else {
            vertical = recording.channel(.ii)?.waveform
        }
        guard let vertical, let areaI = netQRSArea(horizontal), let areaVertical = netQRSArea(vertical) else { return nil }
        guard abs(areaI) > 1e-6 || abs(areaVertical) > 1e-6 else { return nil }
        let degrees = atan2(areaVertical, areaI) * 180 / .pi
        return Int(degrees.rounded())
    }

    private struct IntervalValues {
        var heartRate: Int?
        var pr: Int?
        var qrs: Int?
        var storedWithRecording: Bool
        var measurementLead: ECGLead?
    }

    /// `BeatIntervals` on lead II, else lead I. A nil result keeps the stored numbers.
    /// A result whose fields are nil stays nil: those stored numbers are not a substitute.
    private static func intervals(of recording: ECGRecording, stored: ECGStoredIntervals) -> IntervalValues {
        guard let measured = BeatIntervals.measure(recording) else {
            return IntervalValues(
                heartRate: stored.heartRate,
                pr: stored.prMS,
                qrs: stored.qrsMS,
                storedWithRecording: true,
                measurementLead: nil
            )
        }
        let lead: ECGLead = recording.channel(.ii) == nil ? .i : .ii
        return IntervalValues(
            heartRate: measured.heartRate,
            pr: measured.pr,
            qrs: measured.qrs,
            storedWithRecording: false,
            measurementLead: lead
        )
    }

    private static func measuredIntervals(_ recording: ECGRecording) -> (heartRate: Int?, pr: Int?, qrs: Int?) {
        guard let measured = BeatIntervals.measure(recording) else { return (nil, nil, nil) }
        return (measured.heartRate, measured.pr, measured.qrs)
    }

    // MARK: - Strip

    /// The whole lead, with calipers on the first detected beat so they sit at the opening of the paper.
    private static func stripDrawing(
        display: Waveform,
        anchor: Waveform?,
        pr: Int?,
        qrs: Int?
    ) -> ECGStripDrawing {
        let timing = anchor ?? display
        let rOffset = firstRTime(of: timing)
        let marks = calipers(on: timing, rOffset: rOffset, pr: pr, qrs: qrs)
        return ECGStripDrawing(waveform: display, rOffset: rOffset, pr: marks.pr, qrs: marks.qrs)
    }

    private static func firstRTime(of waveform: Waveform) -> TimeInterval? {
        let rate = waveform.sampleRate
        guard rate > 0, !waveform.samples.isEmpty else { return nil }
        let analysis = BeatDetector.analyze(waveform.samples, sampleRate: rate)
        guard let peak = analysis.rPeaks.first else { return nil }
        return Double(peak) / rate
    }

    /// Widths are the measured milliseconds. The QRS start comes from the average beat when that walk succeeds.
    private static func calipers(
        on waveform: Waveform,
        rOffset: TimeInterval?,
        pr: Int?,
        qrs: Int?
    ) -> (pr: ECGCaliperMark?, qrs: ECGCaliperMark?) {
        guard let rOffset, let qrs else { return (nil, nil) }
        let qrsWidth = Double(qrs) / 1000
        guard qrsWidth > 0 else { return (nil, nil) }
        let onset = qrsOnsetRelativeToR(waveform) ?? (-0.4 * qrsWidth)
        let qrsMark = ECGCaliperMark(
            start: rOffset + onset,
            end: rOffset + onset + qrsWidth,
            milliseconds: qrs,
            title: "QRS"
        )
        guard let pr else { return (nil, qrsMark) }
        let prWidth = Double(pr) / 1000
        guard prWidth > 0 else { return (nil, qrsMark) }
        let prMark = ECGCaliperMark(
            start: qrsMark.start - prWidth,
            end: qrsMark.start,
            milliseconds: pr,
            title: "PR"
        )
        return (prMark, qrsMark)
    }

    // MARK: - QRS area

    /// Net area in mV·s over the QRS of the long average beat. Nil when that QRS cannot be bounded.
    /// This does not report a QRS duration. Duration stays with `BeatIntervals`.
    private static func netQRSArea(_ waveform: Waveform) -> Double? {
        guard let qrs = averageQRS(waveform) else { return nil }
        var area = 0.0
        for index in qrs.onset...qrs.offset {
            area += qrs.beat[index] - qrs.baseline
        }
        return area / qrs.sampleRate
    }

    /// Seconds from R to QRS onset, negative when onset is before R.
    private static func qrsOnsetRelativeToR(_ waveform: Waveform) -> TimeInterval? {
        guard let qrs = averageQRS(waveform) else { return nil }
        return Double(qrs.onset - qrs.rIndex) / qrs.sampleRate
    }

    private struct AverageQRS {
        var beat: [Double]
        var sampleRate: Double
        var rIndex: Int
        var onset: Int
        var offset: Int
        var baseline: Double
    }

    /// QRS limits on the public long average, for area and caliper placement only.
    private static func averageQRS(_ waveform: Waveform) -> AverageQRS? {
        let rate = waveform.sampleRate
        guard BeatIntervals.measurableSampleRates.contains(rate) else { return nil }
        let analysis = BeatDetector.analyze(waveform.samples, sampleRate: rate)
        guard analysis.rPeaks.count >= BeatIntervals.minimumBeats,
              (analysis.shapeConsistency ?? 0) >= RecordingQualityCheck.minimumShapeConsistency,
              let beat = BeatIntervals.longAverageBeat(waveform.samples, sampleRate: rate, rPeaks: analysis.rPeaks)
        else { return nil }
        let rIndex = Int((BeatIntervals.averageBefore * rate).rounded())
        guard beat.indices.contains(rIndex) else { return nil }
        let slopeSpan = max(Int((0.004 * rate).rounded()), 1)
        guard beat.count > 2 * slopeSpan else { return nil }

        var slope = [Double](repeating: 0, count: beat.count)
        for index in slopeSpan..<(beat.count - slopeSpan) {
            slope[index] = (beat[index + slopeSpan] - beat[index - slopeSpan]) * rate / Double(2 * slopeSpan)
        }
        let spacings = zip(analysis.rPeaks.dropFirst(), analysis.rPeaks).map { $0 - $1 }.filter { $0 > 0 }.sorted()
        guard !spacings.isEmpty else { return nil }
        let middle = spacings.count / 2
        let medianSpacing = spacings.count.isMultiple(of: 2)
            ? Double(spacings[middle - 1] + spacings[middle]) / 2
            : Double(spacings[middle])
        let reach = max(Int(medianSpacing.rounded()) / 2, 1)
        let lower = max(rIndex - reach, slopeSpan)
        let upper = min(rIndex + reach, slope.count - 1 - slopeSpan)
        guard lower < rIndex, rIndex < upper else { return nil }
        let steepest = slope[lower...upper].map(abs).max() ?? 0
        let threshold = BeatIntervals.qrsSlopeFraction * steepest
        guard steepest > 0 else { return nil }
        let quiet = max(Int((0.010 * rate).rounded()), 2)
        guard let onset = edge(of: slope, from: rIndex, step: -1, limit: lower, threshold: threshold, quiet: quiet),
              let offset = edge(of: slope, from: rIndex, step: 1, limit: upper, threshold: threshold, quiet: quiet),
              onset < offset,
              BeatIntervals.plausibleQRS.contains(Double(offset - onset) / rate)
        else { return nil }

        let outside = beat.enumerated().compactMap { index, sample -> Double? in
            index < onset || index > offset ? sample : nil
        }
        let baseline = median(outside.isEmpty ? beat : outside)
        return AverageQRS(
            beat: beat,
            sampleRate: rate,
            rIndex: rIndex,
            onset: onset,
            offset: offset,
            baseline: baseline
        )
    }

    /// The last steep sample before `quiet` samples in a row fall below the threshold.
    private static func edge(
        of slope: [Double],
        from start: Int,
        step: Int,
        limit: Int,
        threshold: Double,
        quiet: Int
    ) -> Int? {
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

    private static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        return sorted[sorted.count / 2]
    }
}
