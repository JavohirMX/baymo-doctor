import Foundation
import SwiftData

/// The eight designed children. Written only into an empty demo store.
@MainActor
enum DemoClinic {
    static let rizkyNickname = "Rizky"
    static let rizkyCondition = "Repaired tetralogy of Fallot (2021). Under Dr. Eki."
    static let baselineHeartRate = 96
    static let baselineQRS = 128
    static let changeHeartRate = 128
    static let changeQRS = 142

    static func seedIfNeeded(in context: ModelContext) {
        let count = (try? context.fetchCount(FetchDescriptor<Child>())) ?? 0
        guard count == 0 else { return }

        let calm = bundledTrace(named: "NormalECG")
            ?? trace(heartRate: baselineHeartRate, qrs: baselineQRS, pr: 140)
        let changed = bundledTrace(named: "AtrialFibrillation")
            ?? trace(heartRate: changeHeartRate, qrs: changeQRS, pr: 120)
        let routine = trace(heartRate: 90, qrs: 80, pr: 140)
        let septalDefect = bundledTrace(named: "VentricularSeptalDefect")
            ?? trace(heartRate: 150, qrs: 88, pr: 110)

        seedRizky(in: context, calm: calm, changed: changed)
        seed(
            in: context,
            fullName: "Siti Aisyah Putri Lestari",
            nickname: "Ica",
            born: day(2021, 6, 21),
            sex: .female,
            condition: "VSD (after surgery)",
            link: .linked,
            lastSync: day(2026, 11, 6, 8, 0),
            baseline: routine,
            recordings: [
                RecordingSpec(
                    at: day(2026, 11, 6, 18, 0),
                    status: .urgent,
                    trace: septalDefect,
                    heartRate: 150,
                    pr: 110,
                    qrs: 88,
                    duration: septalDefect.duration
                )
            ]
        )
        seed(
            in: context,
            fullName: "Adinda Nadia Rahmawati",
            nickname: "Dinda",
            born: day(2022, 5, 2),
            sex: .female,
            condition: "Repaired AVSD",
            link: .linked,
            lastSync: day(2026, 11, 1, 8, 0),
            baseline: routine,
            recordings: [
                RecordingSpec(at: day(2026, 11, 8, 18, 0), status: .changeDetected, trace: changed, heartRate: 118, pr: 130, qrs: 140),
                RecordingSpec(at: day(2026, 11, 2, 18, 0), status: .missed, trace: .empty, heartRate: nil, pr: nil, qrs: nil),
                RecordingSpec(at: day(2026, 11, 4, 18, 0), status: .missed, trace: .empty, heartRate: nil, pr: nil, qrs: nil),
                RecordingSpec(at: day(2026, 11, 6, 18, 0), status: .missed, trace: .empty, heartRate: nil, pr: nil, qrs: nil)
            ]
        )
        seed(
            in: context,
            fullName: "Sekar Ayu Maharani",
            nickname: "Ayu",
            born: day(2023, 3, 28),
            sex: .female,
            condition: "Ebstein anomaly",
            link: .linked,
            lastSync: day(2026, 11, 9, 8, 0),
            baseline: routine,
            recordings: [
                RecordingSpec(at: day(2026, 11, 9, 18, 0), status: .changeDetected, trace: changed, heartRate: 112, pr: 150, qrs: 140),
                RecordingSpec(at: day(2026, 11, 7, 18, 0), status: .noChange, trace: routine, heartRate: 90, pr: 140, qrs: 80)
            ]
        )
        seed(
            in: context,
            fullName: "Kirana Dewi Wulandari",
            nickname: "Kiki",
            born: day(2020, 9, 14),
            sex: .female,
            condition: "Pulmonary valve stenosis",
            link: .linked,
            lastSync: day(2026, 11, 4, 8, 0),
            baseline: routine,
            recordings: [4, 6, 8, 11].map { dayNumber in
                RecordingSpec(at: day(2026, 11, dayNumber, 18, 0), status: .missed, trace: .empty, heartRate: nil, pr: nil, qrs: nil)
            }
        )
        seed(
            in: context,
            fullName: "Bima Arya Santoso",
            nickname: "Bima",
            born: day(2017, 1, 12),
            sex: .male,
            condition: "Repaired coarctation of the aorta",
            link: .linked,
            lastSync: day(2026, 11, 8, 8, 0),
            baseline: routine,
            recordings: [
                RecordingSpec(at: day(2026, 11, 8, 18, 0), status: .noChange, trace: routine, heartRate: 90, pr: 140, qrs: 80)
            ]
        )
        seed(
            in: context,
            fullName: "Dimas Aditya Nugraha",
            nickname: "Adit",
            born: day(2016, 1, 30),
            sex: .male,
            condition: "Fontan circulation",
            link: .linked,
            lastSync: day(2026, 11, 10, 8, 0),
            baseline: routine,
            recordings: [
                RecordingSpec(at: day(2026, 11, 10, 18, 0), status: .noChange, trace: routine, heartRate: 90, pr: 140, qrs: 80, reviewed: true)
            ]
        )
        seed(
            in: context,
            fullName: "Muhammad Fajar Nugroho",
            nickname: "Fajar",
            born: day(2018, 1, 9),
            sex: .male,
            condition: "ASD (device closure)",
            link: .linked,
            lastSync: day(2026, 11, 11, 8, 0),
            baseline: routine,
            recordings: [
                RecordingSpec(
                    at: day(2026, 11, 11, 18, 0),
                    status: .noChange,
                    trace: routine,
                    heartRate: 90,
                    pr: 140,
                    qrs: 80,
                    reviewed: true
                )
            ]
        )

        try? context.save()
    }

    private struct RecordingSpec {
        var at: Date
        var status: ParentRecordingStatus
        var trace: StoredECGPayload
        var heartRate: Int?
        var pr: Int?
        var qrs: Int?
        var reviewed: Bool = false
        var duration: TimeInterval?
    }

    private static func seedRizky(in context: ModelContext, calm: StoredECGPayload, changed: StoredECGPayload) {
        let schedule = Schedule(
            cadence: .specificWeekdays,
            weekdays: [1, 2, 4, 6],
            durationMinutes: 5,
            reminderHour: 18,
            reminderMinute: 0
        )
        let child = Child.add(
            to: context,
            fullName: "Muhammad Rizky Pratama",
            nickname: rizkyNickname,
            birthDate: day(2019, 2, 4),
            sex: .male,
            conditionText: rizkyCondition,
            schedule: schedule,
            linkState: .linked,
            lastSyncDate: day(2026, 10, 30, 8, 0)
        )
        BaselineVersion.addVersion(
            to: child,
            fileName: "rizky-baseline.csv",
            recordedAt: day(2026, 3, 14, 9, 0),
            recording: calm
        )

        let calmSpec = (trace: calm, heartRate: baselineHeartRate, pr: 140, qrs: baselineQRS)
        home(child, at: day(2026, 10, 30, 18, 10), status: .noChange, spec: calmSpec, duration: calm.duration)
        home(child, at: day(2026, 11, 1, 18, 5), status: .noChange, spec: calmSpec, duration: calm.duration)
        missed(child, at: day(2026, 11, 2, 18, 0))
        home(child, at: day(2026, 11, 4, 18, 12), status: .noChange, spec: calmSpec, duration: calm.duration)
        home(child, at: day(2026, 11, 6, 18, 8), status: .noChange, spec: calmSpec, duration: calm.duration)
        home(
            child,
            at: day(2026, 11, 8, 19, 5),
            status: .changeDetected,
            spec: (trace: changed, heartRate: changeHeartRate, pr: 120, qrs: changeQRS),
            duration: changed.duration
        )
        missed(child, at: day(2026, 11, 9, 18, 0))
        home(child, at: day(2026, 11, 11, 18, 15), status: .noChange, spec: calmSpec, duration: calm.duration)
        home(child, at: day(2026, 11, 12, 18, 20), status: .noChange, spec: calmSpec, duration: calm.duration)

        DiaryEvent.add(
            to: child,
            kind: .symptom,
            startedAt: day(2026, 11, 4, 17, 10),
            text: "More tired than usual after school.",
            symptomName: "Unusual tiredness"
        )
        DiaryEvent.add(
            to: child,
            kind: .activity,
            startedAt: day(2026, 11, 8, 16, 0),
            text: "Football"
        )
        DiaryEvent.add(
            to: child,
            kind: .journal,
            startedAt: day(2026, 11, 8, 18, 40),
            text: "Felt settled after football. No symptoms tonight."
        )
        DiaryEvent.add(
            to: child,
            kind: .symptom,
            startedAt: day(2026, 11, 11, 17, 40),
            text: "A short run of palpitations while sitting down.",
            symptomName: "Palpitations"
        )
    }

    private static func home(
        _ child: Child,
        at start: Date,
        status: ParentRecordingStatus,
        spec: (trace: StoredECGPayload, heartRate: Int, pr: Int, qrs: Int),
        duration: TimeInterval = 5 * 60
    ) {
        let axis = ECGViewerMeasurement.axisDegrees(of: ECGRecording(payload: spec.trace, startDate: start))
        ClinicRecording.add(
            to: child,
            startDate: start,
            duration: duration > 0 ? duration : 5 * 60,
            parentStatus: status,
            heartRate: spec.heartRate,
            prMS: spec.pr,
            qrsMS: spec.qrs,
            axisDegrees: axis,
            signalQuality: "Good",
            samples: spec.trace
        )
    }

    private static func missed(_ child: Child, at start: Date) {
        ClinicRecording.add(
            to: child,
            startDate: start,
            duration: 0,
            parentStatus: .missed,
            signalQuality: ""
        )
    }

    private static func seed(
        in context: ModelContext,
        fullName: String,
        nickname: String,
        born: Date,
        sex: ChildSex,
        condition: String,
        link: LinkState,
        lastSync: Date?,
        baseline: StoredECGPayload,
        recordings: [RecordingSpec]
    ) {
        let child = Child.add(
            to: context,
            fullName: fullName,
            nickname: nickname,
            birthDate: born,
            sex: sex,
            conditionText: condition,
            schedule: Schedule(cadence: .everyDay, durationMinutes: 5, reminderHour: 18, reminderMinute: 0),
            linkState: link,
            lastSyncDate: lastSync
        )
        BaselineVersion.addVersion(
            to: child,
            fileName: "baseline.csv",
            recordedAt: day(2026, 3, 14, 9, 0),
            recording: baseline
        )
        for recording in recordings {
            let axis = recording.status == .missed
                ? nil
                : ECGViewerMeasurement.axisDegrees(of: ECGRecording(payload: recording.trace, startDate: recording.at))
            ClinicRecording.add(
                to: child,
                startDate: recording.at,
                duration: recording.status == .missed ? 0 : (recording.duration ?? 5 * 60),
                parentStatus: recording.status,
                heartRate: recording.heartRate,
                prMS: recording.pr,
                qrsMS: recording.qrs,
                axisDegrees: axis,
                signalQuality: recording.status == .missed ? "" : "Good",
                reviewed: recording.reviewed,
                samples: recording.trace
            )
        }
    }

    /// Full pediatric recording bundled with the app. A missing file falls back to a synthetic trace.
    private static func bundledTrace(named name: String) -> StoredECGPayload? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "csv"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }
        let stamped = text.localizedStandardContains("recordedat")
            ? text
            : "# recordedAt=2026-03-14T09:00:00Z\n\(text)"
        return try? BaselineFileParser.parse(data: Data(stamped.utf8), fileName: "\(name).csv").recording
    }

    private static func trace(heartRate: Int, qrs: Int, pr: Int) -> StoredECGPayload {
        SyntheticECG.payload(pr: pr, qrs: qrs, heartRate: Double(heartRate))
    }

    private static func day(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))
            ?? .now
    }
}
