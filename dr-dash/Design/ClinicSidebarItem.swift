import SwiftUI

struct ClinicSidebarItem: View {
    var title: String
    var systemImage: String
    var isSelected: Bool

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.body.weight(isSelected ? .semibold : .regular))
            .foregroundStyle(isSelected ? ClinicPalette.accentInk : ClinicPalette.primaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? ClinicPalette.accentInk.opacity(0.16) : Color.clear)
            }
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
