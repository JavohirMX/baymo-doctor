import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(ClinicLibrary.self) private var library
    @Query(sort: \Child.fullName) private var children: [Child]
    @State private var search = ""
    @State private var sort: ClinicSort = .needsAttention
    @State private var section: ClinicSidebarSection = .allPatients
    @State private var patientsExpanded = true
    @State private var selectedChildID: ClinicChildSummary.ID?
    @State private var activeSheet: ClinicSheet?
    /// Set when Add patient saves, then presented once that sheet has closed.
    @State private var pendingLinkID: UUID?

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .navigationSplitViewStyle(.balanced)
        .sheet(item: $activeSheet) { sheet in
            ClinicSheetHost(sheet: sheet, selectedChildID: $selectedChildID) { childID in
                pendingLinkID = childID
            }
        }
        .onChange(of: activeSheet) { _, sheet in
            guard sheet == nil, let childID = pendingLinkID else { return }
            pendingLinkID = nil
            Task { @MainActor in
                activeSheet = .linkPhone(childID)
            }
        }
        .onChange(of: section) { _, _ in
            selectedChildID = nil
        }
    }

    private var detail: some View {
        Group {
            if let selectedChild {
                ChildDetailView(
                    child: selectedChild,
                    backTitle: section.title,
                    onBack: { selectedChildID = nil }
                )
                .id(selectedChild.id)
            } else {
                PatientListView(
                    title: section.title,
                    children: listed,
                    hasPatients: !children.isEmpty,
                    childCount: childCountSubtitle,
                    search: $search,
                    sort: $sort,
                    selection: $selectedChildID,
                    onAddPatient: { activeSheet = .addPatient },
                    onSync: { activeSheet = .syncPhone }
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ClinicPalette.canvas)
    }

    private var sidebar: some View {
        List(selection: $section) {
            Section("Clinic") {
                ForEach(ClinicSidebarSection.allCases) { item in
                    Label(item.title, systemImage: item.systemImage)
                        .badge(count(item))
                        .tag(item)
                        .accessibilityIdentifier(identifier(for: item))
                }
            }
            Section("Patients", isExpanded: $patientsExpanded) {
                ForEach(sidebarChildren) { child in
                    Button {
                        selectedChildID = child.id
                    } label: {
                        Text(sidebarName(child))
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 300)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            sidebarFooter
        }
    }

    private var sidebarFooter: some View {
        VStack(alignment: .leading, spacing: 6) {
            if library.showsDemoClinic {
                Text("Demo clinic")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ClinicPalette.accentInk)
                    .accessibilityHidden(true)
            }
            Label("Stored on this Mac only", systemImage: "lock")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var selectedChild: Child? {
        guard let selectedChildID else { return nil }
        return children.first { $0.id == selectedChildID }
    }

    private var sidebarChildren: [Child] {
        children.sorted {
            sidebarName($0).localizedStandardCompare(sidebarName($1)) == .orderedAscending
        }
    }

    /// The same primary name the patient table shows.
    private func sidebarName(_ child: Child) -> String {
        let nickname = child.nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        let fullName = child.fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !nickname.isEmpty, nickname.localizedStandardCompare(fullName) != .orderedSame {
            return nickname
        }
        return fullName.isEmpty ? nickname : fullName
    }

    private var summaries: [ClinicChildSummary] {
        children.map { $0.listSummary() }
    }

    private var listed: [ClinicChildSummary] {
        summaries.filter { ClinicListLogic.inSection($0, section) }
    }

    private var childCountSubtitle: String {
        switch listed.count {
        case 0: "0 children"
        case 1: "1 child"
        default: "\(listed.count) children"
        }
    }

    private func count(_ item: ClinicSidebarSection) -> Int {
        summaries.filter { ClinicListLogic.inSection($0, item) }.count
    }

    private func identifier(for item: ClinicSidebarSection) -> String {
        item == .allPatients ? "sidebar.allPatients" : "sidebar.\(item.rawValue)"
    }
}

#Preview {
    let library = ClinicLibrary(showsDemoClinic: false, inMemory: true)
    ContentView()
        .environment(library)
        .modelContainer(library.container)
        .frame(width: 1440, height: 900)
}
