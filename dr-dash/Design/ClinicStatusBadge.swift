import SwiftUI

struct ClinicStatusBadge: View {
    var title: String
    var tone: ClinicTone

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(ClinicPalette.foreground(tone))
                .frame(width: 6, height: 6)
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(ClinicPalette.foreground(tone))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: true)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .fixedSize(horizontal: true, vertical: true)
        .background(ClinicPalette.background(tone), in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
    }
}
