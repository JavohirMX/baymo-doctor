import SwiftData
import SwiftUI

struct PatientListView: View {
    var title: String
    var children: [ClinicChildSummary]
    var hasPatients: Bool
    var childCount: String
    @Binding var search: String
    @Binding var sort: ClinicSort
    @Binding var selection: ClinicChildSummary.ID?
    var onAddPatient: () -> Void
    var onSync: () -> Void

    @Query(sort: \Child.fullName) private var storedChildren: [Child]
    @State private var editor: ChildEditor?

    private var rows: [ClinicChildSummary] {
        ClinicListLogic.filtered(children, query: search, sort: sort)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text("Flagged results and missed recordings are listed first.")
                    .font(.callout)
                    .foregroundStyle(ClinicPalette.secondaryText)
                Spacer(minLength: 12)
                sortMenu
            }
            .padding(.horizontal, 24)
            .padding(.top, 14)
            .padding(.bottom, 8)

            columnHeader
                .padding(.horizontal, 24)

            Rectangle().fill(ClinicPalette.separator).frame(height: 1)
                .padding(.horizontal, 24)

            if rows.isEmpty {
                emptyState
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(rows) { child in
                            patientRow(child)
                            Rectangle().fill(ClinicPalette.separator).frame(height: 1)
                        }
                    }
                    .padding(.horizontal, 24)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(ClinicPalette.canvas)
        .searchable(text: $search, placement: .toolbar, prompt: "Search patients")
        .toolbar {
            ToolbarItem(placement: .navigation) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.headline)
                    Text(childCount)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
            .sharedBackgroundVisibility(.hidden)
            ToolbarSpacer(.flexible)
            ToolbarItem {
                Button("Sync phone", action: onSync)
                    .buttonStyle(.glass)
            }
            ToolbarItem {
                Button("Add patient", action: onAddPatient)
                    .buttonStyle(.glassProminent)
            }
        }
        .sheet(item: $editor) { editor in
            EditChildSheet(child: editor.child)
        }
    }

    private var columnHeader: some View {
        HStack(spacing: 0) {
            Text("Name").frame(width: 280, alignment: .leading)
            Text("Age").frame(width: 72, alignment: .leading)
            Text("Condition").frame(maxWidth: .infinity, alignment: .leading)
            Text("Last sync").frame(width: 110, alignment: .leading)
            Text("Status").frame(width: 280, alignment: .leading)
        }
        .font(.caption)
        .foregroundStyle(ClinicPalette.secondaryText)
        .padding(.vertical, 8)
    }

    private func patientRow(_ child: ClinicChildSummary) -> some View {
        let lines = nameLines(for: child)
        return Button {
            selection = child.id
        } label: {
            HStack(spacing: 0) {
                HStack(spacing: 10) {
                    Text(ChildDetailLogic.initials(nickname: child.nickname, fullName: child.fullName))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ClinicPalette.accentInk)
                        .frame(width: 32, height: 32)
                        .background(ClinicPalette.accentInk.opacity(0.14), in: Circle())
                    VStack(alignment: .leading, spacing: 1) {
                        Text(lines.primary)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(ClinicPalette.primaryText)
                            .lineLimit(1)
                        if let secondary = lines.secondary {
                            Text(secondary)
                                .font(.caption)
                                .foregroundStyle(ClinicPalette.secondaryText)
                                .lineLimit(1)
                        }
                    }
                }
                .frame(width: 280, alignment: .leading)

                Text(ClinicListLogic.ageCompact(born: child.birthDate))
                    .font(.body)
                    .foregroundStyle(ClinicPalette.primaryText)
                    .frame(width: 72, alignment: .leading)

                Text(child.conditionText.isEmpty ? "—" : child.conditionText)
                    .font(.body)
                    .foregroundStyle(child.conditionText.isEmpty ? ClinicPalette.secondaryText : ClinicPalette.primaryText)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(syncText(child.lastSyncDate))
                    .font(.body)
                    .foregroundStyle(child.lastSyncDate == nil ? ClinicPalette.secondaryText : ClinicPalette.primaryText)
                    .frame(width: 110, alignment: .leading)

                HStack(spacing: 6) {
                    ForEach(ClinicListLogic.listBadges(for: child), id: \.title) { badge in
                        ClinicStatusBadge(title: badge.title, tone: badge.tone)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ClinicPalette.secondaryText)
                }
                .frame(width: 280, alignment: .leading)
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("patient.\(lines.primary)")
        .contextMenu {
            Button("Edit child") {
                guard let stored = storedChildren.first(where: { $0.id == child.id }) else { return }
                editor = ChildEditor(id: stored.id, child: stored)
            }
        }
    }

    private func syncText(_ date: Date?) -> String {
        guard let date else { return "Not yet" }
        return date.formatted(.dateTime.day().month(.abbreviated))
    }

    private var sortMenu: some View {
        Picker("Sort", selection: $sort) {
            ForEach(ClinicSort.allCases) { item in
                Text(item.title).tag(item)
            }
        }
        .pickerStyle(.menu)
        .fixedSize()
    }

    @ViewBuilder
    private var emptyState: some View {
        if hasPatients, !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            ContentUnavailableView {
                Label("No matching patients", systemImage: "magnifyingglass")
            } description: {
                Text("Search matches the child's full name or nickname.")
            }
        } else if hasPatients {
            ContentUnavailableView {
                Label("Nothing in \(title)", systemImage: "person.2")
            } description: {
                Text("Choose another list in the sidebar to see more children.")
            }
        } else {
            ContentUnavailableView {
                Label("No patients yet", systemImage: "person.2")
            } description: {
                Text("Add a patient to start a record on this Mac.")
            } actions: {
                ClinicPrimaryButton(title: "Add patient", systemImage: "plus", action: onAddPatient)
            }
            .accessibilityIdentifier("clinic.empty")
        }
    }

    private func nameLines(for child: ClinicChildSummary) -> (primary: String, secondary: String?) {
        let nickname = child.nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        let fullName = child.fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !nickname.isEmpty, nickname.localizedStandardCompare(fullName) != .orderedSame {
            return (nickname, fullName.isEmpty ? nil : fullName)
        }
        return (fullName.isEmpty ? nickname : fullName, nil)
    }
}

private struct ChildEditor: Identifiable {
    var id: UUID
    var child: Child
}
