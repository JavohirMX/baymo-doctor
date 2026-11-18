import Foundation
import SwiftData

/// A symptom, activity, or journal entry. `id` is the parent's id and is the sync merge key.
@Model
final class DiaryEvent {
    @Attribute(.unique) var id: UUID
    var kindRaw: String
    var startedAt: Date
    var text: String
    var symptomName: String?

    var child: Child?

    init(
        id: UUID = UUID(),
        kind: DiaryEventKind,
        startedAt: Date,
        text: String,
        symptomName: String? = nil
    ) {
        self.id = id
        self.kindRaw = kind.rawValue
        self.startedAt = startedAt
        self.text = text
        self.symptomName = symptomName
    }

    var kind: DiaryEventKind {
        get { DiaryEventKind(rawValue: kindRaw) ?? .journal }
        set { kindRaw = newValue.rawValue }
    }

    func applyPhoneFields(from payload: ClinicDiaryPayload) {
        kind = payload.kind
        startedAt = payload.startedAt
        text = payload.text
        symptomName = payload.symptomName
    }

    @discardableResult
    static func add(
        to child: Child,
        id: UUID = UUID(),
        kind: DiaryEventKind,
        startedAt: Date,
        text: String,
        symptomName: String? = nil
    ) -> DiaryEvent {
        let event = DiaryEvent(
            id: id,
            kind: kind,
            startedAt: startedAt,
            text: text,
            symptomName: symptomName
        )
        child.modelContext?.insert(event)
        event.child = child
        return event
    }
}
