import Foundation
import Observation
import SwiftData

/// Which clinic file is open. The two stores are never copied into each other.
nonisolated enum ClinicStoreKind: String, Sendable, Equatable {
    case real
    case demo

    var storeName: String {
        switch self {
        case .real: "RealClinic"
        case .demo: "DemoClinic"
        }
    }

    var fileName: String { "\(storeName).store" }
}

/// Opens either the real clinic or the demo clinic. Default is the empty real clinic.
@MainActor
@Observable
final class ClinicLibrary {
    static let demoDefaultsKey = "clinic.showsDemoClinic"
    /// Bump when the designed demo children change, so an old demo file is replaced.
    private static let demoRevision = 3

    private(set) var showsDemoClinic: Bool
    private(set) var container: ModelContainer
    private let inMemory: Bool

    var storeKind: ClinicStoreKind { showsDemoClinic ? .demo : .real }

    init(showsDemoClinic: Bool? = nil, inMemory: Bool = false) {
        let enabled = showsDemoClinic ?? Self.preferenceFromLaunch()
        self.inMemory = inMemory
        self.showsDemoClinic = enabled
        self.container = Self.makeContainer(kind: enabled ? .demo : .real, inMemory: inMemory)
    }

    /// `-demoClinic` opens the demo store for this launch. `-realClinic` opens the real store.
    /// Neither argument writes the Settings preference. With no argument, the toggle decides.
    private static func preferenceFromLaunch() -> Bool {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-realClinic") { return false }
        if arguments.contains("-demoClinic") { return true }
        return UserDefaults.standard.bool(forKey: demoDefaultsKey)
    }

    /// Swaps the open container. Does not copy, merge, or delete the other store.
    func setShowsDemoClinic(_ enabled: Bool) {
        guard enabled != showsDemoClinic else { return }
        showsDemoClinic = enabled
        UserDefaults.standard.set(enabled, forKey: Self.demoDefaultsKey)
        container = Self.makeContainer(kind: enabled ? .demo : .real, inMemory: inMemory)
    }

    /// Application Support file for one clinic. Demo and real use different file names.
    static func storeURL(kind: ClinicStoreKind) throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let folder = base.appending(path: storeDirectoryName(), directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appending(path: kind.fileName)
    }

    private static func makeContainer(kind: ClinicStoreKind, inMemory: Bool) -> ModelContainer {
        do {
            let configuration: ModelConfiguration
            if inMemory {
                configuration = ModelConfiguration(isStoredInMemoryOnly: true)
            } else {
                if kind == .demo {
                    try replaceDemoStoreIfStale()
                }
                configuration = ModelConfiguration(
                    url: try storeURL(kind: kind),
                    cloudKitDatabase: .none
                )
            }
            let container = try ModelContainer(
                for: Child.self,
                Schedule.self,
                BaselineVersion.self,
                ClinicRecording.self,
                DiaryEvent.self,
                configurations: configuration
            )
            if kind == .demo {
                DemoClinic.seedIfNeeded(in: container.mainContext)
                UserDefaults.standard.set(demoRevision, forKey: demoRevisionKey())
            }
            return container
        } catch {
            fatalError("Could not open the \(kind.storeName) clinic store: \(error)")
        }
    }

    private static func demoRevisionKey() -> String {
        "clinic.demoRevision.\(storeDirectoryName())"
    }

    /// Deletes a demo file from an older design so the next open seeds the current children.
    private static func replaceDemoStoreIfStale() throws {
        let key = demoRevisionKey()
        guard UserDefaults.standard.integer(forKey: key) != demoRevision else { return }
        let url = try storeURL(kind: .demo)
        let manager = FileManager.default
        for suffix in ["", "-shm", "-wal"] {
            let sidecar = URL(filePath: url.path() + suffix)
            if manager.fileExists(atPath: sidecar.path()) {
                try manager.removeItem(at: sidecar)
            }
        }
    }

    /// `-clinicStoreName name` keeps a launch, such as a UI test, in its own folder.
    private static func storeDirectoryName() -> String {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-clinicStoreName"),
              index + 1 < arguments.count else {
            return "Clinic"
        }
        let raw = arguments[index + 1]
        guard !raw.hasPrefix("-") else { return "Clinic" }
        let cleaned = raw.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        guard !cleaned.isEmpty else { return "Clinic" }
        return "Clinic-\(cleaned)"
    }
}
