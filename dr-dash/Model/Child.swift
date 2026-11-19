import Foundation
import SwiftData

/// One child in the open clinic. Real and demo children never share a store.
@Model
final class Child {
    @Attribute(.unique) var id: UUID
    var fullName: String
    var nickname: String
    var birthDate: Date
    var sexRaw: String
    var conditionText: String
    var setupNotes: String
    var linkStateRaw: String
    var lastSyncDate: Date?
    /// Exclusive start of Since last sync after a live sync. Nil with `hasLatestSyncBound` means the whole history.
    var latestSyncLowerBound: Date?
    /// True after a live sync has recorded its window. Demo children leave this false.
    var hasLatestSyncBound: Bool = false
    /// Mirrors `linkState == .linked`. Prefer `setLinkState` so the two stay together.
    var phoneLinked: Bool

    @Relationship(deleteRule: .cascade, inverse: \Schedule.child)
    var schedule: Schedule?

    @Relationship(deleteRule: .cascade, inverse: \BaselineVersion.child)
    var baselines: [BaselineVersion] = []

    @Relationship(deleteRule: .cascade, inverse: \ClinicRecording.child)
    var recordings: [ClinicRecording] = []

    @Relationship(deleteRule: .cascade, inverse: \DiaryEvent.child)
    var diaryEvents: [DiaryEvent] = []

    init(
        id: UUID = UUID(),
        fullName: String,
        nickname: String = "",
        birthDate: Date,
        sex: ChildSex,
        conditionText: String = "",
        setupNotes: String = "",
        linkState: LinkState = .notLinked,
        lastSyncDate: Date? = nil,
        latestSyncLowerBound: Date? = nil,
        hasLatestSyncBound: Bool = false,
        phoneLinked: Bool? = nil
    ) {
        self.id = id
        self.fullName = fullName
        self.nickname = nickname
        self.birthDate = birthDate
        self.sexRaw = sex.rawValue
        self.conditionText = conditionText
        self.setupNotes = setupNotes
        self.linkStateRaw = linkState.rawValue
        self.lastSyncDate = lastSyncDate
        self.latestSyncLowerBound = latestSyncLowerBound
        self.hasLatestSyncBound = hasLatestSyncBound
        self.phoneLinked = phoneLinked ?? (linkState == .linked)
        self.baselines = []
        self.recordings = []
        self.diaryEvents = []
    }

    var sex: ChildSex {
        get { ChildSex(rawValue: sexRaw) ?? .other }
        set { sexRaw = newValue.rawValue }
    }

    var linkState: LinkState {
        get { LinkState(rawValue: linkStateRaw) ?? .notLinked }
        set { setLinkState(newValue) }
    }

    func setLinkState(_ state: LinkState) {
        linkStateRaw = state.rawValue
        phoneLinked = state == .linked
    }

    /// Highest version number, then the latest creation time.
    var currentBaseline: BaselineVersion? {
        baselines.max { lhs, rhs in
            if lhs.version != rhs.version { return lhs.version < rhs.version }
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    func ageYears(on date: Date = .now, calendar: Calendar = .current) -> Int {
        ClinicListLogic.ageYears(born: birthDate, on: date, calendar: calendar)
    }

    func listSummary() -> ClinicChildSummary {
        ClinicChildSummary(
            id: id,
            fullName: fullName,
            nickname: nickname,
            birthDate: birthDate,
            conditionText: conditionText,
            lastSyncDate: lastSyncDate,
            latestSyncLowerBound: latestSyncLowerBound,
            hasLatestSyncBound: hasLatestSyncBound,
            phoneLinked: phoneLinked,
            recordings: recordings.map(\.attentionRecording)
        )
    }

    @discardableResult
    static func add(
        to context: ModelContext,
        id: UUID = UUID(),
        fullName: String,
        nickname: String = "",
        birthDate: Date,
        sex: ChildSex,
        conditionText: String = "",
        setupNotes: String = "",
        schedule: Schedule = Schedule(),
        linkState: LinkState = .notLinked,
        lastSyncDate: Date? = nil,
        latestSyncLowerBound: Date? = nil,
        hasLatestSyncBound: Bool = false,
        phoneLinked: Bool? = nil
    ) -> Child {
        let child = Child(
            id: id,
            fullName: fullName,
            nickname: nickname,
            birthDate: birthDate,
            sex: sex,
            conditionText: conditionText,
            setupNotes: setupNotes,
            linkState: linkState,
            lastSyncDate: lastSyncDate,
            latestSyncLowerBound: latestSyncLowerBound,
            hasLatestSyncBound: hasLatestSyncBound,
            phoneLinked: phoneLinked
        )
        context.insert(child)
        child.schedule = schedule
        return child
    }
}
