import SwiftUI

/// One sheet of ECG paper: 1 mm and 5 mm grid, a 1 mV calibration pulse, and a short strip.
struct ECGPaperView: View {
    var title: String
    var leadName: String
    var primary: ECGStripDrawing
    var overlay: ECGStripDrawing?
    var emptyMessage: String?
    var showsProgress: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(ClinicPalette.primaryText)
                Spacer(minLength: 12)
                Text("25 mm/s · 10 mm/mV")
                    .font(.caption)
                    .foregroundStyle(ClinicPalette.secondaryText)
                Slider(value: $pointsPerMillimeter, in: zoomRange)
                    .frame(width: 120)
                    .controlSize(.small)
                    .accessibilityLabel("Zoom")
            }
            if overlay != nil {
                HStack(spacing: 16) {
                    legendItem("This ECG", recordingColor)
                    legendItem("Baseline", baselineColor)
                }
            }
            sheet
        }
    }

    private var sheet: some View {
        ScrollView(.horizontal) {
            paper
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: paperHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var paper: some View {
        Canvas { context, size in
            drawPaper(in: &context, size: size)
        }
        .frame(width: paperWidth, height: paperHeight)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(gridColor.opacity(0.45), lineWidth: 1)
            if showsProgress {
                ProgressView()
                    .tint(paperInk)
                    .padding(8)
                    .background(paperFill.opacity(0.92), in: RoundedRectangle(cornerRadius: 6))
            } else if let emptyMessage, primary.waveform.samples.count < 2 {
                Text(emptyMessage)
                    .font(.callout)
                    .foregroundStyle(paperInk)
                    .multilineTextAlignment(.center)
                    .padding(8)
                    .background(paperFill.opacity(0.92), in: RoundedRectangle(cornerRadius: 6))
            }
        }
        .overlay(alignment: .topLeading) {
            Text(leadName)
                .font(.caption.weight(.bold))
                .foregroundStyle(paperInk)
                .padding(8)
                .accessibilityHidden(true)
        }
    }

    private var traceSeconds: Double {
        max(primary.waveform.duration, overlay?.waveform.duration ?? 0)
    }

    /// Millimetres of paper per point. The slider changes this; the sheet stays 25 mm/s and 10 mm/mV.
    @State private var pointsPerMillimeter = 3.2

    private var zoomRange: ClosedRange<Double> { 1.6...8 }

    /// Calibration pulse, then the whole stored recording, at the clinical millimetre scale.
    private var paperSeconds: Double {
        let trace = traceSeconds
        if trace > 0 { return ECGPaper.originSeconds + trace }
        return ECGPaper.contentSeconds
    }

    /// Tall enough for the 50 mm sheet, and taller when a peak or the 1 mV pulse would leave the grid.
    private var sheetMillimeters: Double {
        let span = max(peakDeviation(primary.waveform), overlay.map { peakDeviation($0.waveform) } ?? 0)
        let half = max(span, ECGPaper.calibrationMillivolts) + 0.8
        return max(ECGPaper.heightMillimeters, half * 2 * ECGPaper.millimetersPerMillivolt)
    }

    private var paperWidth: CGFloat {
        CGFloat(paperSeconds * ECGPaper.millimetersPerSecond) * scale
    }

    private var paperHeight: CGFloat {
        CGFloat(sheetMillimeters) * scale
    }

    private var scale: CGFloat { CGFloat(pointsPerMillimeter) }

    private func peakDeviation(_ waveform: Waveform) -> Double {
        let samples = waveform.samples
        guard samples.count > 1 else { return 0 }
        let level = Double(median(samples))
        var peak = 0.0
        for sample in samples {
            peak = max(peak, abs(Double(sample) - level))
        }
        return peak
    }

    private var accessibilityText: String {
        let seconds = max(1, Int(traceSeconds.rounded()))
        var parts = ["Lead \(leadName), \(seconds) second ECG recording, 25 millimetres per second, 10 millimetres per millivolt"]
        if let pr = primary.pr {
            parts.append("PR \(pr.milliseconds) milliseconds")
        }
        if let qrs = primary.qrs {
            parts.append("QRS \(qrs.milliseconds) milliseconds")
        }
        return parts.joined(separator: ", ")
    }

    private func legendItem(_ title: String, _ color: Color) -> some View {
        HStack(spacing: 6) {
            Capsule()
                .fill(color)
                .frame(width: 16, height: 3)
            Text(title)
                .font(.caption)
                .foregroundStyle(ClinicPalette.secondaryText)
        }
    }

    /// Light Figma paper in both appearances: a pale sheet, a red grid, and a teal trace.
    private var paperFill: Color {
        Color(red: 1.0, green: 0.955, blue: 0.955)
    }

    private var recordingColor: Color {
        ClinicPalette.accent
    }

    private var baselineColor: Color {
        Color(red: 0.10, green: 0.35, blue: 0.66)
    }

    private var caliperColor: Color {
        Color(red: 0.05, green: 0.42, blue: 0.40)
    }

    private var paperInk: Color {
        Color(red: 0.36, green: 0.22, blue: 0.22)
    }

    private var gridColor: Color {
        Color(red: 0.78, green: 0.18, blue: 0.16)
    }

    private func drawPaper(in context: inout GraphicsContext, size: CGSize) {
        guard size.width > 1, size.height > 1 else { return }
        let scale = self.scale
        let paperHeight = CGFloat(sheetMillimeters) * scale
        let originY = max(0, (size.height - paperHeight) / 2)
        let rect = CGRect(x: 0, y: originY, width: size.width, height: paperHeight)
        context.fill(Path(rect), with: .color(paperFill))

        let small = scale
        var index = 0
        var position = 0.0
        while position <= size.width + 0.5 {
            strokeGridLine(
                in: &context,
                from: CGPoint(x: position, y: originY),
                to: CGPoint(x: position, y: originY + paperHeight),
                major: index % 5 == 0
            )
            position += small
            index += 1
        }
        index = 0
        position = 0
        while position <= paperHeight + 0.5 {
            strokeGridLine(
                in: &context,
                from: CGPoint(x: 0, y: originY + position),
                to: CGPoint(x: size.width, y: originY + position),
                major: index % 5 == 0
            )
            position += small
            index += 1
        }

        let midY = originY + paperHeight / 2
        let pointsPerSecond = CGFloat(ECGPaper.millimetersPerSecond) * scale
        let pointsPerMillivolt = CGFloat(ECGPaper.millimetersPerMillivolt) * scale
        let traceOrigin = CGFloat(ECGPaper.originSeconds) * pointsPerSecond
        drawCalibration(
            in: &context,
            midY: midY,
            pointsPerSecond: pointsPerSecond,
            pointsPerMillivolt: pointsPerMillivolt
        )
        if let overlay {
            let shift = overlayShift(primary: primary, overlay: overlay)
            drawTrace(
                overlay.waveform,
                shift: shift,
                color: baselineColor,
                in: &context,
                traceOrigin: traceOrigin,
                midY: midY,
                pointsPerSecond: pointsPerSecond,
                pointsPerMillivolt: pointsPerMillivolt
            )
        }
        drawTrace(
            primary.waveform,
            shift: 0,
            color: recordingColor,
            in: &context,
            traceOrigin: traceOrigin,
            midY: midY,
            pointsPerSecond: pointsPerSecond,
            pointsPerMillivolt: pointsPerMillivolt
        )
        let traceTop = originY + paperHeight * 0.16
        let traceNext = originY + paperHeight * 0.30
        if let pr = primary.pr {
            drawCaliper(
                pr,
                y: traceTop,
                in: &context,
                traceOrigin: traceOrigin,
                pointsPerSecond: pointsPerSecond,
                paperTop: originY,
                paperBottom: originY + paperHeight
            )
        }
        if let qrs = primary.qrs {
            drawCaliper(
                qrs,
                y: traceNext,
                in: &context,
                traceOrigin: traceOrigin,
                pointsPerSecond: pointsPerSecond,
                paperTop: originY,
                paperBottom: originY + paperHeight
            )
        }
    }

    private func overlayShift(primary: ECGStripDrawing, overlay: ECGStripDrawing) -> TimeInterval {
        guard let primaryR = primary.rOffset, let overlayR = overlay.rOffset else { return 0 }
        return primaryR - overlayR
    }

    private func strokeGridLine(
        in context: inout GraphicsContext,
        from start: CGPoint,
        to end: CGPoint,
        major: Bool
    ) {
        var line = Path()
        line.move(to: start)
        line.addLine(to: end)
        context.stroke(
            line,
            with: .color(gridColor.opacity(major ? 0.42 : 0.16)),
            lineWidth: major ? 1 : 0.5
        )
    }

    private func drawCalibration(
        in context: inout GraphicsContext,
        midY: CGFloat,
        pointsPerSecond: CGFloat,
        pointsPerMillivolt: CGFloat
    ) {
        let height = CGFloat(ECGPaper.calibrationMillivolts) * pointsPerMillivolt
        let width = CGFloat(ECGPaper.calibrationSeconds) * pointsPerSecond
        var pulse = Path()
        pulse.move(to: CGPoint(x: 0, y: midY))
        pulse.addLine(to: CGPoint(x: 0, y: midY - height))
        pulse.addLine(to: CGPoint(x: width, y: midY - height))
        pulse.addLine(to: CGPoint(x: width, y: midY))
        context.stroke(
            pulse,
            with: .color(recordingColor),
            style: StrokeStyle(lineWidth: 1.4, lineJoin: .miter)
        )
        context.draw(
            Text("1 mV").font(.caption2).foregroundStyle(paperInk),
            at: CGPoint(x: 4, y: midY - height - 4),
            anchor: .bottomLeading
        )
    }

    private func drawTrace(
        _ waveform: Waveform,
        shift: TimeInterval,
        color: Color,
        in context: inout GraphicsContext,
        traceOrigin: CGFloat,
        midY: CGFloat,
        pointsPerSecond: CGFloat,
        pointsPerMillivolt: CGFloat
    ) {
        let samples = waveform.samples
        let rate = waveform.sampleRate
        guard samples.count > 1, rate > 0 else { return }
        let level = median(samples)
        var path = Path()
        for (index, sample) in samples.enumerated() {
            let time = Double(index) / rate + shift
            let point = CGPoint(
                x: traceOrigin + CGFloat(time) * pointsPerSecond,
                y: midY - CGFloat(Double(sample) - Double(level)) * pointsPerMillivolt
            )
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        context.stroke(
            path,
            with: .color(color),
            style: StrokeStyle(lineWidth: 1.35, lineCap: .round, lineJoin: .round)
        )
    }

    private func drawCaliper(
        _ mark: ECGCaliperMark,
        y: CGFloat,
        in context: inout GraphicsContext,
        traceOrigin: CGFloat,
        pointsPerSecond: CGFloat,
        paperTop: CGFloat,
        paperBottom: CGFloat
    ) {
        let areaMin = traceOrigin
        let areaMax = traceOrigin + CGFloat(max(traceSeconds, 0)) * pointsPerSecond
        let rawLeft = traceOrigin + CGFloat(min(mark.start, mark.end)) * pointsPerSecond
        let rawRight = traceOrigin + CGFloat(max(mark.start, mark.end)) * pointsPerSecond
        let left = min(max(rawLeft, areaMin), areaMax)
        let right = min(max(rawRight, areaMin), areaMax)
        guard right - left > 0.5 else { return }
        let tick: CGFloat = 6
        var bracket = Path()
        bracket.move(to: CGPoint(x: left, y: y - tick))
        bracket.addLine(to: CGPoint(x: left, y: y + tick))
        bracket.move(to: CGPoint(x: left, y: y))
        bracket.addLine(to: CGPoint(x: right, y: y))
        bracket.move(to: CGPoint(x: right, y: y - tick))
        bracket.addLine(to: CGPoint(x: right, y: y + tick))
        context.stroke(bracket, with: .color(caliperColor), lineWidth: 1.25)
        let labelY = min(max(y - 8, paperTop + 10), paperBottom - 4)
        context.draw(
            Text("\(mark.title) \(mark.milliseconds) ms").font(.caption2).foregroundStyle(caliperColor),
            at: CGPoint(x: (left + right) / 2, y: labelY),
            anchor: .bottom
        )
    }

    private func median(_ samples: [Float]) -> Float {
        let sorted = samples.sorted()
        return sorted[sorted.count / 2]
    }
}
