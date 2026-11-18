import CoreFoundation
import Foundation
import UniformTypeIdentifiers

/// A baseline file the doctor picked. `recording` is ready for `BaselineVersion.addVersion`.
nonisolated struct ImportedBaseline: Equatable, Sendable {
    var fileName: String
    var recordedAt: Date
    var recording: StoredECGPayload
}

nonisolated enum BaselineFileError: Error, Equatable, LocalizedError {
    case unreadable
    case noUsableLead
    case missingSampleRate
    case missingRecordedDate
    case invalidSampleRate(String)
    case invalidRecordedDate(String)
    case unevenRow(line: Int)
    case notANumber(line: Int)
    case unknownUnits(String)

    var errorDescription: String? {
        switch self {
        case .unreadable:
            "This file could not be read as an ECG recording."
        case .noUsableLead:
            "This file has no usable lead. Use I, II, III, aVR, aVL, aVF, or V1–V6."
        case .missingSampleRate:
            "Add a sample-rate header, such as # sampleRate=500."
        case .missingRecordedDate:
            "Add a recorded-at header, such as # recordedAt=2026-11-12T08:00:00Z."
        case .invalidSampleRate(let value):
            "The sample rate \"\(value)\" could not be read. Use a header such as # sampleRate=500."
        case .invalidRecordedDate(let value):
            "The recorded date \"\(value)\" could not be read. Use an ISO-8601 date, such as 2026-11-12T08:00:00Z."
        case .unevenRow(let line):
            "Line \(line) has a different number of values than the header."
        case .notANumber(let line):
            "Line \(line) has a value that is not a number."
        case .unknownUnits(let units):
            "Unknown units \"\(units)\". Use mV, uV, or V."
        }
    }
}

/// Reads a baseline file into `StoredECGPayload`.
///
/// JSON may be a parent-style recording (`channels` of lead name plus float samples in millivolts
/// and `sampleRate`, or a `waveform` with those fields), a `StoredECGPayload` (`leads`), or a
/// LocalArchive-like document that contains a recording under `baseline`, `baselines`, `recordings`,
/// `signal`, or `link.baseline`. Packed samples are little-endian Float32, base64, the way the
/// parent app stores a waveform.
///
/// CSV needs a sample-rate header, a recorded-at header, and one column per standard lead.
/// `# sampleRate=500` and `# recordedAt=2026-11-12T08:00:00Z` (or `# start=`) are the headers.
/// `# units=` may be mV, uV, or V. Samples are stored in millivolts.
nonisolated enum BaselineFileParser {
    static let contentTypes: [UTType] = {
        var types: [UTType] = [.json, .plainText, .commaSeparatedText]
        if let csv = UTType(filenameExtension: "csv", conformingTo: .commaSeparatedText) {
            types.append(csv)
        }
        return types
    }()

    static func load(from url: URL) throws -> ImportedBaseline {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }
        let data = try Data(contentsOf: url)
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        let name = url.lastPathComponent
        let fileName = name.isEmpty || name == "/" ? "Baseline" : name
        return try parse(data: data, fileName: fileName, fallbackDate: modified ?? .now)
    }

    /// `fallbackDate` is used when JSON has leads but no recorded date. CSV must include its own date.
    static func parse(data: Data, fileName: String, fallbackDate: Date = .now) throws -> ImportedBaseline {
        let payload = strippingBOM(data)
        if looksLikeJSON(payload) {
            return try parseJSON(payload, fileName: fileName, fallbackDate: fallbackDate)
        }
        guard let text = decodeText(payload) else { throw BaselineFileError.unreadable }
        return try parseCSV(text, fileName: fileName)
    }

    /// Turns a file-importer result into a baseline, or an error string. Cancellation changes nothing.
    static func importing(_ result: Result<[URL], Error>) -> (baseline: ImportedBaseline?, error: String?) {
        switch result {
        case .failure(let error):
            if isCancellation(error) { return (nil, nil) }
            return (nil, error.localizedDescription)
        case .success(let urls):
            guard let url = urls.first else {
                return (nil, BaselineFileError.unreadable.localizedDescription)
            }
            do {
                return (try load(from: url), nil)
            } catch {
                return (nil, error.localizedDescription)
            }
        }
    }

    private struct Found {
        var leads: [StoredECGLead]
        var recordedAt: Date?
    }

    private struct Attempt {
        var found: Found?
        var missingRate = false
        var corrupt = false

        mutating func mergeFailure(_ other: Attempt) {
            missingRate = missingRate || other.missingRate
            corrupt = corrupt || other.corrupt
        }
    }

    private static func parseJSON(_ data: Data, fileName: String, fallbackDate: Date) throws -> ImportedBaseline {
        let json: Any
        do {
            json = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw BaselineFileError.unreadable
        }
        if let object = json as? [String: Any] {
            return try finish(attempt: attempt(in: object), fileName: fileName, fallbackDate: fallbackDate)
        }
        if let array = json as? [Any] {
            var failure = Attempt()
            for item in array {
                guard let object = item as? [String: Any] else { continue }
                let attempt = attempt(in: object)
                if let found = usable(attempt) {
                    return try finish(attempt: Attempt(found: found), fileName: fileName, fallbackDate: fallbackDate)
                }
                failure.mergeFailure(attempt)
            }
            return try finish(attempt: failure, fileName: fileName, fallbackDate: fallbackDate)
        }
        throw BaselineFileError.unreadable
    }

    private static func attempt(in object: [String: Any]) -> Attempt {
        if object["channels"] != nil || object["leads"] != nil {
            return readRecording(object)
        }
        var failure = Attempt()
        func take(_ source: [String: Any]?, date: Date? = nil) -> Found? {
            guard let source else { return nil }
            let attempt = readRecording(source, extraDate: date)
            if let found = usable(attempt) { return found }
            failure.mergeFailure(attempt)
            return nil
        }
        func baselineObject(_ wrapper: [String: Any]) -> Found? {
            let recorded = date(wrapper["recordedAt"]) ?? date(wrapper["createdAt"]) ?? date(wrapper["startDate"])
            let source = (wrapper["recording"] as? [String: Any]) ?? wrapper
            return take(source, date: recorded)
        }

        if let link = object["link"] as? [String: Any],
           let baseline = link["baseline"] as? [String: Any],
           let found = baselineObject(baseline) {
            return Attempt(found: found)
        }
        if let baseline = object["baseline"] as? [String: Any], let found = baselineObject(baseline) {
            return Attempt(found: found)
        }
        if let profile = object["profile"] as? [String: Any],
           let baseline = profile["baseline"] as? [String: Any],
           let found = baselineObject(baseline) {
            return Attempt(found: found)
        }
        if let baselines = object["baselines"] as? [Any] {
            let ordered = baselines.compactMap { $0 as? [String: Any] }.sorted { version($0) < version($1) }
            var best: Found?
            for baseline in ordered {
                if let found = baselineObject(baseline) {
                    best = found
                }
            }
            if let best { return Attempt(found: best) }
        }
        if let recording = object["recording"] as? [String: Any] {
            let recorded = date(object["recordedAt"]) ?? date(object["startDate"])
            if let found = take(recording, date: recorded) {
                return Attempt(found: found)
            }
        }
        if let signal = object["signal"] as? [String: Any], let found = take(signal) {
            return Attempt(found: found)
        }
        if let recordings = object["recordings"] as? [Any] {
            for item in recordings {
                guard let recording = item as? [String: Any] else { continue }
                let entryDate = (recording["entry"] as? [String: Any]).flatMap { date($0["date"]) }
                let signal = (recording["signal"] as? [String: Any]) ?? recording
                if let found = take(signal, date: entryDate) {
                    return Attempt(found: found)
                }
            }
        }
        return failure
    }

    private static func usable(_ attempt: Attempt) -> Found? {
        guard let found = attempt.found, !found.leads.isEmpty, !attempt.corrupt, !attempt.missingRate else {
            return nil
        }
        return found
    }

    private static func finish(attempt: Attempt, fileName: String, fallbackDate: Date) throws -> ImportedBaseline {
        if let found = usable(attempt) {
            return ImportedBaseline(
                fileName: fileName,
                recordedAt: found.recordedAt ?? fallbackDate,
                recording: StoredECGPayload(leads: found.leads)
            )
        }
        if attempt.corrupt { throw BaselineFileError.unreadable }
        if attempt.missingRate { throw BaselineFileError.missingSampleRate }
        throw BaselineFileError.noUsableLead
    }

    private static func readRecording(_ object: [String: Any], extraDate: Date? = nil) -> Attempt {
        let channelValues = (object["channels"] as? [Any]) ?? (object["leads"] as? [Any])
        guard let channelValues else { return Attempt() }
        let sharedRate = double(object["sampleRate"])
        let recorded = date(object["startDate"]) ?? date(object["recordedAt"]) ?? extraDate
        var leads: [StoredECGLead] = []
        var seen = Set<String>()
        var missingRate = false
        var corrupt = false

        for value in channelValues {
            guard let channel = value as? [String: Any] else { continue }
            let leadValue = (channel["lead"] as? String) ?? (channel["name"] as? String)
            guard let name = canonicalLead(leadValue) else { continue }
            if seen.contains(name) { continue }
            let waveform = channel["waveform"] as? [String: Any]
            let samplesValue = waveform?["samples"] ?? channel["samples"]
            guard let samplesValue else { continue }
            guard let samples = floats(from: samplesValue) else {
                corrupt = true
                continue
            }
            guard !samples.isEmpty else { continue }
            let rate = double(waveform?["sampleRate"]) ?? double(channel["sampleRate"]) ?? sharedRate
            guard let rate, rate > 0 else {
                missingRate = true
                continue
            }
            seen.insert(name)
            leads.append(StoredECGLead(name: name, sampleRate: rate, samples: samples))
        }

        if !leads.isEmpty && !corrupt && !missingRate {
            return Attempt(found: Found(leads: leads, recordedAt: recorded))
        }
        return Attempt(missingRate: missingRate, corrupt: corrupt)
    }

    private static func version(_ object: [String: Any]) -> Int {
        (object["version"] as? NSNumber)?.intValue ?? 0
    }

    private static func floats(from value: Any) -> [Float]? {
        if let items = value as? [Any] {
            var samples: [Float] = []
            samples.reserveCapacity(items.count)
            for item in items {
                guard let number = jsonNumber(item) else { return nil }
                samples.append(Float(number))
            }
            return samples
        }
        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return [] }
            guard let data = Data(base64Encoded: trimmed, options: .ignoreUnknownCharacters) else { return nil }
            return packedFloats(data)
        }
        return nil
    }

    /// Parent waveforms store samples as raw little-endian Float32 bytes.
    private static func packedFloats(_ data: Data) -> [Float]? {
        let size = MemoryLayout<Float>.size
        guard data.count % size == 0 else { return nil }
        if data.isEmpty { return [] }
        var samples = [Float](repeating: 0, count: data.count / size)
        _ = samples.withUnsafeMutableBytes { data.copyBytes(to: $0) }
        guard samples.allSatisfy(\.isFinite) else { return nil }
        return samples
    }

    private static func double(_ value: Any?) -> Double? {
        if let number = jsonNumber(value) { return number }
        if let string = value as? String {
            return Double(string).flatMap { $0.isFinite ? $0 : nil }
        }
        return nil
    }

    /// JSON booleans bridge as `NSNumber`, and so do sample values 0 and 1. Reject only real booleans.
    private static func jsonNumber(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber else { return nil }
        if CFGetTypeID(number) == CFBooleanGetTypeID() { return nil }
        let double = number.doubleValue
        return double.isFinite ? double : nil
    }

    private static func date(_ value: Any?) -> Date? {
        guard let value, !(value is NSNull) else { return nil }
        if let string = value as? String {
            return date(from: string)
        }
        if let seconds = jsonNumber(value) {
            if abs(seconds) > 1_000_000_000_000 {
                return Date(timeIntervalSince1970: seconds / 1000)
            }
            if seconds > 1_200_000_000 {
                return Date(timeIntervalSince1970: seconds)
            }
            return Date(timeIntervalSinceReferenceDate: seconds)
        }
        return nil
    }

    private static func date(from string: String) -> Date? {
        let text = string.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        guard !text.isEmpty else { return nil }
        if !text.contains("T"), !text.contains(":") {
            let day = DateFormatter()
            day.locale = Locale(identifier: "en_US_POSIX")
            day.timeZone = .current
            day.dateFormat = "yyyy-MM-dd"
            if let date = day.date(from: text) { return date }
        }
        let iso = ISO8601DateFormatter()
        if let date = iso.date(from: text) { return date }
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: text) { return date }
        iso.formatOptions = [.withFullDate]
        if let date = iso.date(from: text) { return date }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        for format in ["yyyy-MM-dd'T'HH:mm:ssXXXXX", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: text) { return date }
        }
        return nil
    }

    static func canonicalLead(_ value: String?) -> String? {
        guard let value else { return nil }
        var key = value.uppercased().filter { $0.isLetter || $0.isNumber }
        if key.hasSuffix("RAW") {
            key.removeLast(3)
        }
        if key.hasPrefix("LEAD") {
            let rest = key.dropFirst(4)
            if !rest.isEmpty { key = String(rest) }
        }
        switch key {
        case "I", "MLI": return ECGLeadName.i
        case "II", "MLII": return ECGLeadName.ii
        case "III", "MLIII": return ECGLeadName.iii
        case "AVR": return ECGLeadName.aVR
        case "AVL": return ECGLeadName.aVL
        case "AVF": return ECGLeadName.aVF
        case "V1": return ECGLeadName.v1
        case "V2": return ECGLeadName.v2
        case "V3": return ECGLeadName.v3
        case "V4": return ECGLeadName.v4
        case "V5": return ECGLeadName.v5
        case "V6": return ECGLeadName.v6
        default: return nil
        }
    }

    private enum CSVColumn: Equatable {
        case time
        case lead(String)
        case electrode(String)
        case ignored
    }

    private static func parseCSV(_ text: String, fileName: String) throws -> ImportedBaseline {
        let normalized = text
            .replacingOccurrences(of: "\u{FEFF}", with: "")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        var sampleRate: Double?
        var sawSampleRate = false
        var fileScale = 1.0
        var recordedAt: Date?
        var sawRecordedDate = false
        var header: [CSVColumn]?
        var columnScales: [Double]?
        var delimiter: Character = ","
        var rows: [(line: Int, cells: [String])] = []

        for (offset, rawLine) in normalized.components(separatedBy: "\n").enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            if line.hasPrefix("#") {
                guard let setting = headerSetting(from: line) else { continue }
                let key = setting.key.lowercased().filter { $0.isLetter || $0.isNumber }
                let value = clean(setting.value)
                switch key {
                case "samplerate":
                    sawSampleRate = true
                    guard let rate = Double(value), rate.isFinite, rate > 0 else {
                        throw BaselineFileError.invalidSampleRate(value)
                    }
                    sampleRate = rate
                case "recordedat", "recorded", "start", "startdate":
                    sawRecordedDate = true
                    guard let date = date(from: value) else {
                        throw BaselineFileError.invalidRecordedDate(value)
                    }
                    if recordedAt == nil { recordedAt = date }
                case "units":
                    guard let scale = unitScale(value) else { throw BaselineFileError.unknownUnits(value) }
                    fileScale = scale
                default:
                    break
                }
                continue
            }
            if header == nil {
                delimiter = line.contains(";") ? ";" : (line.contains("\t") ? "\t" : ",")
                header = cells(of: line, delimiter: delimiter).map(columnKind)
                continue
            }
            let lineCells = cells(of: line, delimiter: delimiter)
            let isUnitsRow = rows.isEmpty && columnScales == nil
                && lineCells.contains { unitScale($0) != nil }
                && lineCells.allSatisfy { number($0, delimiter: delimiter) == nil && seconds(fromTime: $0) == nil }
            if isUnitsRow {
                columnScales = lineCells.map { unitScale($0) ?? fileScale }
                continue
            }
            rows.append((offset + 1, lineCells))
        }

        guard sawSampleRate, let sampleRate else { throw BaselineFileError.missingSampleRate }
        guard sawRecordedDate, let recordedAt else { throw BaselineFileError.missingRecordedDate }
        guard let header, !rows.isEmpty else { throw BaselineFileError.noUsableLead }

        let electrodeMode = ["RA", "LA", "LL"].allSatisfy { electrode in
            header.contains(.electrode(electrode))
        }
        let hasLeads = header.contains { if case .lead = $0 { true } else { false } }
        guard electrodeMode || hasLeads else { throw BaselineFileError.noUsableLead }

        var columns = [[Double]](repeating: [], count: header.count)
        for (line, lineCells) in rows {
            guard lineCells.count == header.count else { throw BaselineFileError.unevenRow(line: line) }
            for (index, column) in header.enumerated() {
                switch column {
                case .ignored:
                    continue
                case .time:
                    guard number(lineCells[index], delimiter: delimiter) != nil || seconds(fromTime: lineCells[index]) != nil else {
                        throw BaselineFileError.notANumber(line: line)
                    }
                case .lead, .electrode:
                    guard let value = number(lineCells[index], delimiter: delimiter) else {
                        throw BaselineFileError.notANumber(line: line)
                    }
                    let scale = columnScales.flatMap { index < $0.count ? $0[index] : nil } ?? fileScale
                    columns[index].append(value * scale)
                }
            }
        }

        var leads: [StoredECGLead] = []
        func samples(for column: CSVColumn) -> [Double]? {
            header.firstIndex(of: column).map { columns[$0] }
        }
        func appendLead(_ name: String, _ values: [Double]) {
            guard !values.isEmpty, !leads.contains(where: { $0.name == name }) else { return }
            leads.append(StoredECGLead(name: name, sampleRate: sampleRate, samples: values.map { Float($0) }))
        }

        if electrodeMode,
           let ra = samples(for: .electrode("RA")),
           let la = samples(for: .electrode("LA")),
           let ll = samples(for: .electrode("LL")) {
            let count = min(ra.count, la.count, ll.count)
            if count > 0 {
                let leadI = (0..<count).map { la[$0] - ra[$0] }
                let leadII = (0..<count).map { ll[$0] - ra[$0] }
                appendLead(ECGLeadName.i, leadI)
                appendLead(ECGLeadName.ii, leadII)
                if let v1 = samples(for: .lead(ECGLeadName.v1)) {
                    let vCount = min(count, v1.count)
                    let derived = (0..<vCount).map { index in
                        Double(v1[index] - (ra[index] + la[index] + ll[index]) / 3)
                    }
                    appendLead(ECGLeadName.v1, derived)
                }
            }
            for (index, column) in header.enumerated() {
                guard case .lead(let name) = column, name != ECGLeadName.v1 else { continue }
                appendLead(name, columns[index])
            }
        } else {
            for (index, column) in header.enumerated() {
                guard case .lead(let name) = column else { continue }
                appendLead(name, columns[index])
            }
        }

        guard !leads.isEmpty else { throw BaselineFileError.noUsableLead }
        return ImportedBaseline(
            fileName: fileName,
            recordedAt: recordedAt,
            recording: StoredECGPayload(leads: leads)
        )
    }

    private static func columnKind(_ title: String) -> CSVColumn {
        let key = title.uppercased().filter { $0.isLetter || $0.isNumber }
        switch key {
        case "TIME", "T", "SECONDS", "ELAPSEDTIME":
            return .time
        case "RA":
            return .electrode("RA")
        case "LA":
            return .electrode("LA")
        case "LL":
            return .electrode("LL")
        default:
            break
        }
        if let lead = canonicalLead(title) {
            return .lead(lead)
        }
        return .ignored
    }

    private static func headerSetting(from line: String) -> (key: String, value: String)? {
        let body = line.dropFirst().trimmingCharacters(in: .whitespaces)
        let separator: Character = body.contains("=") ? "=" : ":"
        guard let index = body.firstIndex(of: separator) else { return nil }
        let key = body[..<index].trimmingCharacters(in: .whitespaces)
        let value = body[body.index(after: index)...].trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty, !value.isEmpty else { return nil }
        return (String(key), String(value))
    }

    private static func cells(of line: String, delimiter: Character) -> [String] {
        line.split(separator: delimiter, omittingEmptySubsequences: false).map {
            clean(String($0))
        }
    }

    private static func clean(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
    }

    private static func number(_ text: String, delimiter: Character) -> Double? {
        if let value = finite(text) { return value }
        guard delimiter == ";" else { return nil }
        return finite(text.replacingOccurrences(of: ",", with: "."))
    }

    private static func finite(_ text: String) -> Double? {
        Double(text).flatMap { $0.isFinite ? $0 : nil }
    }

    private static func unitScale(_ text: String) -> Double? {
        switch text.lowercased() {
        case "mv": 1
        case "uv", "µv", "μv": 0.001
        case "v": 1000
        default: nil
        }
    }

    private static func seconds(fromTime text: String) -> Double? {
        let parts = text.split(separator: ":")
        guard (2...3).contains(parts.count) else { return nil }
        var total = 0.0
        for part in parts {
            guard let value = finite(String(part)) else { return nil }
            total = total * 60 + value
        }
        return total
    }

    private static func looksLikeJSON(_ data: Data) -> Bool {
        guard let text = String(data: data.prefix(256), encoding: .utf8) ?? decodeText(data.prefix(256)) else {
            return false
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("{") || trimmed.hasPrefix("[")
    }

    private static func strippingBOM(_ data: Data) -> Data {
        let bom: [UInt8] = [0xEF, 0xBB, 0xBF]
        guard data.starts(with: bom) else { return data }
        return Data(data.dropFirst(bom.count))
    }

    private static func decodeText(_ data: Data) -> String? {
        if let text = String(data: data, encoding: .utf8) { return text }
        if let text = String(data: data, encoding: .utf16) { return text }
        return String(data: data, encoding: .isoLatin1)
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        let nsError = error as NSError
        return nsError.domain == NSCocoaErrorDomain && nsError.code == NSUserCancelledError
    }
}
