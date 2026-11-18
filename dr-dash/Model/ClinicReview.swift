import Foundation
import SwiftData

/// Review flags are per recording. A child stays in Needs attention while any flagged recording is unreviewed.
enum ClinicReview {
    static func markReviewed(_ recording: ClinicRecording) {
        recording.reviewed = true
    }

    /// Marks every still-unreviewed recording whose start falls inside `filter`.
    /// Recordings outside the filter are left unchanged.
    static func markReviewed(_ recordings: [ClinicRecording], in filter: ClinicDateFilter) {
        let ids = Set(
            ClinicListLogic.unreviewedIDs(recordings.map(\.attentionRecording), in: filter)
        )
        for recording in recordings where ids.contains(recording.id) {
            recording.reviewed = true
        }
    }
}
