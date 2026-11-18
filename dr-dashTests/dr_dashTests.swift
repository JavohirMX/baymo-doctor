import AppKit
import Foundation
import SwiftData
import SwiftUI
import Testing
@testable import dr_dash

@MainActor
struct ClinicLogicTests {
    @Test func ageCountsCompletedYears() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let born = date(2019, 2, 4, calendar: calendar)
        #expect(ClinicListLogic.ageYears(born: born, on: date(2026, 2, 4, calendar: calendar), calendar: calendar) == 7)
        #expect(ClinicListLogic.ageYears(born: born, on: date(2026, 2, 3, calendar: calendar), calendar: calendar) == 6)
        #expect(ClinicListLogic.ageLabel(born: born, on: date(2026, 11, 17, calendar: calendar), calendar: calendar) == "7 years")
    }

    @Test func needsAttentionSortsFirstAndSearchMatchesNickname() {
        let now = date(2026, 11, 17)
        let flagged = summary(
            fullName: "Muhammad Rizky Pratama",
            nickname: "Rizky",
            lastSync: date(2026, 10, 1),
            recordings: [attention(.changeDetected, on: date(2026, 11, 8), reviewed: false)]
        )
        let calm = summary(
            fullName: "Adinda Nadia Rahmawati",
            nickname: "Adinda",
            lastSync: date(2026, 11, 12),
            recordings: [attention(.noChange, on: date(2026, 11, 10), reviewed: true)]
        )
        let sorted = ClinicListLogic.sorted([calm, flagged], by: .needsAttention, now: now)
        #expect(sorted.map(\.nickname) == ["Rizky", "Adinda"])
        #expect(ClinicListLogic.matches(flagged, query: "rizky"))
        #expect(ClinicListLogic.filtered([calm, flagged], query: "Rizky", sort: .name, now: now).map(\.nickname) == ["Rizky"])
        #expect(ClinicListLogic.filtered([calm, flagged], query: "Adinda", sort: .name, now: now).map(\.nickname) == ["Adinda"])
    }

    @Test func markingOneRecordingLeavesAnotherFlagged() throws {
        let library = ClinicLibrary(showsDemoClinic: false, inMemory: true)
        let child = sampleChild(in: library.container.mainContext)
        let early = ClinicRecording.add(
            to: child,
            startDate: date(2026, 11, 8, 19, 5),
            duration: 300,
            parentStatus: .changeDetected,
            heartRate: 128,
            qrsMS: 142
        )
        let later = ClinicRecording.add(
            to: child,
            startDate: date(2026, 11, 11, 18, 0),
            duration: 300,
            parentStatus: .urgent,
            heartRate: 150
        )
        ClinicReview.markReviewed(early)
        #expect(early.reviewed)
        #expect(!later.reviewed)
        #expect(ClinicListLogic.needsAttention(child.listSummary()))
    }

    @Test func markingAFilterClearsOnlyRecordingsInsideIt() throws {
        let library = ClinicLibrary(showsDemoClinic: false, inMemory: true)
        let child = sampleChild(in: library.container.mainContext)
        let inside = ClinicRecording.add(
            to: child,
            startDate: date(2026, 11, 8, 19, 5),
            duration: 300,
            parentStatus: .changeDetected
        )
        let outside = ClinicRecording.add(
            to: child,
            startDate: date(2026, 11, 11, 18, 0),
            duration: 300,
            parentStatus: .changeDetected
        )
        let day = date(2026, 11, 8)
        let filter = ClinicDateFilter(
            start: day,
            end: date(2026, 11, 9).addingTimeInterval(-1)
        )
        ClinicReview.markReviewed(Array(child.recordings), in: filter)
        #expect(inside.reviewed)
        #expect(!outside.reviewed)
        #expect(ClinicListLogic.needsAttention(child.listSummary()))
    }

    private func sampleChild(in context: ModelContext) -> Child {
        Child.add(
            to: context,
            fullName: "Muhammad Rizky Pratama",
            nickname: "Rizky",
            birthDate: date(2019, 2, 4),
            sex: .male,
            lastSyncDate: date(2026, 10, 30, 8, 0)
        )
    }

    private func summary(
        fullName: String,
        nickname: String,
        lastSync: Date,
        recordings: [ClinicAttentionRecording]
    ) -> ClinicChildSummary {
        ClinicChildSummary(
            id: UUID(),
            fullName: fullName,
            nickname: nickname,
            birthDate: date(2019, 2, 4),
            conditionText: "",
            lastSyncDate: lastSync,
            phoneLinked: true,
            recordings: recordings
        )
    }

    private func attention(
        _ status: ParentRecordingStatus,
        on start: Date,
        reviewed: Bool
    ) -> ClinicAttentionRecording {
        ClinicAttentionRecording(id: UUID(), startDate: start, parentStatus: status, reviewed: reviewed)
    }
}

@MainActor
struct ClinicMergeTests {
    @Test func importingTheSameIDKeepsTheMacReviewAndDoesNotMoveTheCursor() throws {
        let library = ClinicLibrary(showsDemoClinic: false, inMemory: true)
        let context = library.container.mainContext
        let cursor = date(2026, 10, 30, 8, 0)
        let child = Child.add(
            to: context,
            fullName: "Muhammad Rizky Pratama",
            nickname: "Rizky",
            birthDate: date(2019, 2, 4),
            sex: .male,
            lastSyncDate: cursor
        )
        let original = ClinicRecording(
            id: UUID(),
            startDate: date(2026, 11, 8, 19, 5),
            duration: 300,
            parentStatus: .noChange,
            heartRate: 96,
            prMS: 140,
            qrsMS: 128,
            signalQuality: "Good"
        )
        var payload = ClinicRecordingPayload(recording: original)
        let first = ClinicSyncPayload(childID: child.id, newerThan: nil, recordings: [payload], diary: [])
        let merged = try ClinicSyncImport.merge(first, in: context)
        #expect(merged.recordings.count == 1)
        #expect(merged.lastSyncDate == cursor)

        merged.recordings[0].reviewed = true
        merged.recordings[0].doctorNote = "Watch the QRS"
        payload.heartRate = 128
        payload.qrsMS = 142
        payload.parentStatus = .changeDetected
        let second = ClinicSyncPayload(childID: child.id, newerThan: cursor, recordings: [payload], diary: [])
        try ClinicSyncImport.merge(second, in: context)
        #expect(merged.recordings.count == 1)
        #expect(merged.recordings[0].reviewed)
        #expect(merged.recordings[0].doctorNote == "Watch the QRS")
        #expect(merged.recordings[0].heartRate == 128)
        #expect(merged.recordings[0].parentStatus == .changeDetected)
        #expect(merged.lastSyncDate == cursor)
    }

    @Test func codeExpiresAtFiveMinutes() {
        let issued = date(2026, 11, 8, 19, 0)
        #expect(!ClinicTransfer.codeIsExpired(issuedAt: issued, now: issued.addingTimeInterval(4 * 60)))
        #expect(ClinicTransfer.codeIsExpired(issuedAt: issued, now: issued.addingTimeInterval(5 * 60)))
        #expect(ClinicTransfer.codeIsExpired(issuedAt: issued, now: issued.addingTimeInterval(5 * 60 + 1)))
    }
}

struct BaselineAndIntervalTests {
    @Test func csvWithoutALeadIsRejected() {
        let csv = """
        # sampleRate=500
        # recordedAt=2026-03-14T00:00:00Z
        time
        0
        0.002
        """
        #expect(throws: BaselineFileError.noUsableLead) {
            try BaselineFileParser.parse(data: Data(csv.utf8), fileName: "nolead.csv")
        }
    }

    @Test func tinyLeadCSVIsAccepted() throws {
        let csv = """
        # sampleRate=500
        # recordedAt=2026-03-14T00:00:00Z
        I,II
        0.0,0.1
        0.2,-0.1
        """
        let parsed = try BaselineFileParser.parse(data: Data(csv.utf8), fileName: "tiny.csv")
        #expect(parsed.recording.lead("I")?.samples == [0, 0.2] as [Float])
        #expect(parsed.recording.lead("II")?.samples == [0.1, -0.1] as [Float])
        #expect(parsed.recording.lead("II")?.sampleRate == 500)
        let recorded = try #require(ISO8601DateFormatter().date(from: "2026-03-14T00:00:00Z"))
        #expect(parsed.recordedAt == recorded)
    }

    @Test func syntheticLeadMeasuresPRAndQRSWithinTenMilliseconds() throws {
        let waveform = Waveform(
            samples: SyntheticECG.samples(pr: 120, qrs: 60, heartRate: 100, seconds: 30),
            sampleRate: 500
        )
        let intervals = BeatIntervals.measure(waveform, lead: .ii)
        let pr = try #require(intervals.pr)
        let qrs = try #require(intervals.qrs)
        #expect(abs(pr - 120) <= 10, "PR \(pr) ms")
        #expect(abs(qrs - 60) <= 10, "QRS \(qrs) ms")
    }

    @Test func rizkyBaselineAndChangeTracesMeasureNearTheTruth() throws {
        let baseline = try measured(pr: 140, qrs: 128, heartRate: 96)
        #expect(abs((baseline.heartRate ?? 0) - 96) <= 2)
        #expect(abs((baseline.qrs ?? 0) - 128) <= 10, "QRS \(baseline.qrs ?? -1)")

        let changed = try measured(pr: 120, qrs: 142, heartRate: 128)
        #expect(abs((changed.heartRate ?? 0) - 128) <= 2)
        #expect(abs((changed.qrs ?? 0) - 142) <= 10, "QRS \(changed.qrs ?? -1)")
    }

    private func measured(pr: Int, qrs: Int, heartRate: Double) throws -> BeatIntervals {
        let payload = SyntheticECG.payload(pr: pr, qrs: qrs, heartRate: heartRate)
        return try #require(BeatIntervals.measure(ECGRecording(payload: payload)))
    }
}

@MainActor
struct DemoClinicTests {
    @Test func demoChildrenStayOutOfTheRealStore() throws {
        let demo = ClinicLibrary(showsDemoClinic: true, inMemory: true)
        let real = ClinicLibrary(showsDemoClinic: false, inMemory: true)
        let demoContext = demo.container.mainContext
        let children = try demoContext.fetch(FetchDescriptor<Child>())
        #expect(children.count == 8)
        #expect(try real.container.mainContext.fetchCount(FetchDescriptor<Child>()) == 0)

        DemoClinic.seedIfNeeded(in: demoContext)
        #expect(try demoContext.fetchCount(FetchDescriptor<Child>()) == 8)

        let names = Set(children.map(\.fullName))
        #expect(names == [
            "Siti Aisyah Putri Lestari",
            "Muhammad Rizky Pratama",
            "Adinda Nadia Rahmawati",
            "Sekar Ayu Maharani",
            "Kirana Dewi Wulandari",
            "Bima Arya Santoso",
            "Dimas Aditya Nugraha",
            "Muhammad Fajar Nugroho",
        ])

        let rizky = try #require(children.first { $0.nickname == "Rizky" })
        #expect(rizky.sex == .male)
        #expect(rizky.conditionText == DemoClinic.rizkyCondition)
        let born = Calendar.current.dateComponents([.year, .month, .day], from: rizky.birthDate)
        #expect(born.year == 2019)
        #expect(born.month == 2)
        #expect(born.day == 4)
        let schedule = try #require(rizky.schedule)
        #expect(schedule.cadence == .specificWeekdays)
        #expect(Set(schedule.weekdays) == [1, 2, 4, 6])
        #expect(schedule.durationMinutes == 5)
        #expect(schedule.reminderHour == 18)
        #expect(schedule.reminderMinute == 0)

        let change = try #require(rizky.recordings.first { $0.parentStatus == .changeDetected })
        #expect(!change.reviewed)
        #expect(change.heartRate == DemoClinic.changeHeartRate)
        #expect(change.qrsMS == DemoClinic.changeQRS)
        #expect(change.samples.lead(ECGLeadName.i)?.samples.isEmpty == false)
        let changeLead = try #require(change.samples.lead(ECGLeadName.ii))
        #expect(changeLead.samples.count > 14_000)
        let when = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: change.startDate)
        #expect(when.year == 2026)
        #expect(when.month == 11)
        #expect(when.day == 8)
        #expect(when.hour == 19)
        #expect(when.minute == 5)
        #expect(rizky.recordings.filter { $0.parentStatus == .missed && !$0.reviewed }.count == 2)
        #expect(rizky.recordings.contains { $0.parentStatus == .noChange })

        let sameDay = rizky.diaryEvents.filter { Calendar.current.isDate($0.startedAt, inSameDayAs: change.startDate) }
        #expect(sameDay.contains { $0.kind == .activity && $0.text == "Football" })
        #expect(sameDay.contains { $0.kind == .journal })
        #expect(!sameDay.contains { $0.kind == .symptom })
        #expect(rizky.diaryEvents.contains { $0.kind == .symptom })

        let baseline = try #require(rizky.currentBaseline)
        let recorded = Calendar.current.dateComponents([.year, .month, .day], from: baseline.recordedAt)
        #expect(recorded.year == 2026)
        #expect(recorded.month == 3)
        #expect(recorded.day == 14)
        #expect((baseline.recording.lead(ECGLeadName.ii)?.samples.count ?? 0) > 14_000)
        let ica = try #require(children.first { $0.nickname == "Ica" })
        let urgent = try #require(ica.recordings.first { $0.parentStatus == .urgent })
        #expect(urgent.heartRate == 150)
        let urgentCount = urgent.samples.lead(ECGLeadName.ii)?.samples.count ?? 0
        #expect(urgentCount > 8_000)
        #expect(urgentCount < 10_000)

        let kirana = try #require(children.first { $0.fullName == "Kirana Dewi Wulandari" })
        #expect(kirana.nickname == "Kiki")
        #expect(kirana.linkState == .linked)
        #expect(kirana.recordings.filter { $0.parentStatus == .missed }.count == 4)
        #expect(children.contains { $0.nickname == "Ica" && $0.conditionText == "VSD (after surgery)" })

        let summaries = children.map { $0.listSummary() }
        #expect(summaries.contains { ClinicListLogic.needsAttention($0) })
        #expect(summaries.contains { !$0.recordings.isEmpty && !ClinicListLogic.needsAttention($0) })
    }
}

@MainActor
struct ClinicAppearanceTests {
    @Test func missingPreferenceMatchesTheSystem() {
        let defaults = UserDefaults(suiteName: "ClinicAppearanceTests.\(UUID().uuidString)")!
        #expect(ClinicAppearance.stored(in: defaults) == .system)
        #expect(ClinicAppearance.system.colorScheme == nil)
        #expect(ClinicAppearance.light.colorScheme == .light)
        #expect(ClinicAppearance.dark.colorScheme == .dark)

        defaults.set(ClinicAppearance.dark.rawValue, forKey: ClinicAppearance.storageKey)
        #expect(ClinicAppearance.stored(in: defaults) == .dark)
        defaults.set("nope", forKey: ClinicAppearance.storageKey)
        #expect(ClinicAppearance.stored(in: defaults) == .system)
    }

    @Test func paletteFollowsLightAndDark() {
        let lightCanvas = components(ClinicPalette.canvas, .aqua)
        let darkCanvas = components(ClinicPalette.canvas, .darkAqua)
        #expect(lightCanvas.red > 0.98)
        #expect(abs(darkCanvas.red - 0.14) < 0.02)
        #expect(abs(darkCanvas.green - 0.15) < 0.02)
        #expect(abs(darkCanvas.blue - 0.16) < 0.02)

        let darkSidebar = components(ClinicPalette.sidebar, .darkAqua)
        #expect(darkSidebar.red < darkCanvas.red)

        let lightInk = components(ClinicPalette.accentInk, .aqua)
        let darkInk = components(ClinicPalette.accentInk, .darkAqua)
        #expect(abs(lightInk.red - 0.12) < 0.02)
        #expect(abs(lightInk.green - 0.45) < 0.02)
        #expect(darkInk.green > lightInk.green)

        let lightAccent = components(ClinicPalette.accent, .aqua)
        let darkAccent = components(ClinicPalette.accent, .darkAqua)
        #expect(abs(lightAccent.red - 0.12) < 0.02)
        #expect(abs(darkAccent.green - 0.45) < 0.02)
        #expect(abs(darkAccent.blue - 0.42) < 0.02)

        let darkText = components(ClinicPalette.primaryText, .darkAqua)
        #expect(darkText.red > 0.9)
        let darkSecondary = components(ClinicPalette.secondaryText, .darkAqua)
        #expect(darkSecondary.red < darkText.red)
    }

    private func components(_ color: Color, _ name: NSAppearance.Name) -> (red: CGFloat, green: CGFloat, blue: CGFloat) {
        let appearance = NSAppearance(named: name)!
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        appearance.performAsCurrentDrawingAppearance {
            let resolved = NSColor(color).usingColorSpace(.sRGB) ?? NSColor(color)
            resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        }
        return (red, green, blue)
    }
}

@MainActor
struct ClinicReceiptTests {
    @Test func lastSyncStaysPutUntilCompleteCoversTheManifest() {
        let existing = date(2026, 11, 1, 8, 0)
        #expect(!ClinicTransferCommit.mayAdvanceLastSync(completeCoversManifest: false, droppedBeforeComplete: false))
        #expect(!ClinicTransferCommit.mayAdvanceLastSync(completeCoversManifest: true, droppedBeforeComplete: true))
        #expect(ClinicTransferCommit.mayAdvanceLastSync(completeCoversManifest: true, droppedBeforeComplete: false))
        let unchanged = ClinicSyncClock.advanced(existing: existing, payload: ClinicSyncPayload(
            childID: UUID(), newerThan: nil, recordings: [], diary: []
        ), completedAt: existing.addingTimeInterval(-30))
        #expect(unchanged == existing)
    }

    @Test func aChildIsMarkedLinkedOnlyAfterReceipt() {
        var dropped = ClinicTransferCommit()
        dropped.noteLocalComplete()
        dropped.noteCancelledOrDropped()
        let lateReceipt = dropped.noteReceipt()
        #expect(!lateReceipt)
        #expect(!dropped.committed)

        var linked = ClinicTransferCommit()
        linked.noteLocalComplete()
        #expect(!linked.committed)
        let firstReceipt = linked.noteReceipt()
        #expect(firstReceipt)
        #expect(linked.committed)
        let secondReceipt = linked.noteReceipt()
        #expect(!secondReceipt)
    }
}

private func date(
    _ year: Int,
    _ month: Int,
    _ day: Int,
    _ hour: Int = 0,
    _ minute: Int = 0,
    calendar: Calendar = .current
) -> Date {
    return calendar.date(from: DateComponents(
        calendar: calendar,
        timeZone: calendar.timeZone,
        year: year,
        month: month,
        day: day,
        hour: hour,
        minute: minute
    )) ?? .now
}
