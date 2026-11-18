import Foundation

/// Standard ECG lead names. Adapters map a device's channels onto these.
nonisolated enum ECGLead: String, Codable, CaseIterable, Identifiable, Sendable {
    case i = "I"
    case ii = "II"
    case iii = "III"
    case aVR
    case aVL
    case aVF
    case v1 = "V1"
    case v2 = "V2"
    case v3 = "V3"
    case v4 = "V4"
    case v5 = "V5"
    case v6 = "V6"

    var id: Self { self }

    /// Judged first when looking for a loose electrode.
    static let limbLeads: Set<ECGLead> = [.i, .ii, .iii]

    /// Preferred order for the quality check's best lead and the baseline comparison.
    /// `ECGRecording.primaryChannel` is a simpler rule: II, else I, else the first channel.
    static let preference: [ECGLead] = [.ii, .i, .v1, .iii, .aVF, .aVL, .aVR, .v2, .v3, .v4, .v5, .v6]

    /// Matches `ECGLeadName` and `StoredECGLead.name`, ignoring case and surrounding space.
    static func named(_ name: String) -> ECGLead? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return allCases.first { $0.rawValue.caseInsensitiveCompare(trimmed) == .orderedSame }
    }
}

/// One channel of a recording: a lead and its trace.
nonisolated struct ECGChannel: Codable, Equatable, Sendable {
    var lead: ECGLead
    var waveform: Waveform
}

/// A trace built from stored millivolt samples.
///
/// Channel access and limb-lead derivation match the parent `ECGRecording`.
/// Device, origin, and acquisition stay on the phone.
nonisolated struct ECGRecording: Identifiable, Equatable, Sendable {
    var id = UUID()
    var startDate: Date
    /// Only the channels the file gave. Other limb leads are derived on demand.
    var channels: [ECGChannel]

    init(id: UUID = UUID(), startDate: Date = .distantPast, channels: [ECGChannel]) {
        self.id = id
        self.startDate = startDate
        self.channels = channels
    }

    /// Samples stay in the stored order, oldest first. An empty lead is left out.
    init(payload: StoredECGPayload, id: UUID = UUID(), startDate: Date = .distantPast) {
        let channels = payload.leads.compactMap { lead -> ECGChannel? in
            guard let name = ECGLead.named(lead.name), lead.sampleRate > 0, !lead.samples.isEmpty else { return nil }
            return ECGChannel(lead: name, waveform: Waveform(samples: lead.samples, sampleRate: lead.sampleRate))
        }
        self.init(id: id, startDate: startDate, channels: channels)
    }

    var duration: TimeInterval {
        channels.map(\.waveform.duration).max() ?? 0
    }

    var storedLeads: [ECGLead] { channels.map(\.lead) }

    /// The stored leads plus the limb leads that can be derived, in standard order.
    var availableLeads: [ECGLead] {
        let stored = Set(storedLeads)
        let canDerive = stored.intersection(ECGLead.limbLeads).count >= 2
        return ECGLead.allCases.filter { lead in
            switch lead {
            case .i, .ii, .iii, .aVR, .aVL, .aVF: stored.contains(lead) || canDerive
            default: stored.contains(lead)
            }
        }
    }

    /// The channel the doctor's first strip shows: stored II, else stored I, else the first channel.
    /// The quality check picks its best lead with `ECGLead.preference` instead.
    var primaryChannel: ECGChannel? {
        storedChannel(.ii) ?? storedChannel(.i) ?? channels.first
    }

    /// A stored channel, or a limb lead derived from two others (Einthoven and Goldberger).
    func channel(_ lead: ECGLead) -> ECGChannel? {
        if let stored = storedChannel(lead) { return stored }
        guard let i = limbLead(.i), let ii = limbLead(.ii) else { return nil }
        let derived: Waveform? = switch lead {
        case .i: i
        case .ii: ii
        case .iii: i.combined(with: ii) { i, ii in ii - i }
        case .aVR: i.combined(with: ii) { i, ii in -(i + ii) / 2 }
        case .aVL: i.combined(with: ii) { i, ii in i - ii / 2 }
        case .aVF: i.combined(with: ii) { i, ii in ii - i / 2 }
        default: nil
        }
        return derived.map { ECGChannel(lead: lead, waveform: $0) }
    }

    private func storedChannel(_ lead: ECGLead) -> ECGChannel? {
        channels.first { $0.lead == lead }
    }

    /// Lead I or II, stored or derived from the other two limb leads.
    private func limbLead(_ lead: ECGLead) -> Waveform? {
        if let stored = storedChannel(lead) { return stored.waveform }
        switch lead {
        case .i:
            guard let ii = storedChannel(.ii)?.waveform, let iii = storedChannel(.iii)?.waveform else { return nil }
            return ii.combined(with: iii) { ii, iii in ii - iii }
        case .ii:
            guard let i = storedChannel(.i)?.waveform, let iii = storedChannel(.iii)?.waveform else { return nil }
            return i.combined(with: iii) { i, iii in i + iii }
        default:
            return nil
        }
    }
}

nonisolated extension Waveform {
    /// Combines two traces sample by sample. Uses the shorter length and this trace's sample rate.
    func combined(with other: Waveform, _ combine: (Float, Float) -> Float) -> Waveform {
        let count = min(samples.count, other.samples.count)
        var result: [Float] = []
        result.reserveCapacity(count)
        for index in 0..<count {
            result.append(combine(samples[index], other.samples[index]))
        }
        return Waveform(samples: result, sampleRate: sampleRate)
    }
}
