import CLockInCore
import SwiftUI

/// Another app's tab in the expanded notch, drawn from the rows it sent.
struct IslandPanelView: View {
    let panel: IslandPanel
    let client: IslandClient
    let hub: IslandHub

    private var tint: Color { Color(islandHex: panel.tint) ?? client.color }
    private var isEmpty: Bool { panel.sections.allSatisfy(\.rows.isEmpty) }

    var body: some View {
        VStack(spacing: 8) {
            if isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: panel.symbol ?? client.symbol)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(tint.opacity(0.7))
                    Text(panel.emptyText ?? "Nothing here right now")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.secondaryText)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(panel.sections.enumerated()), id: \.offset) { _, section in
                            if !section.rows.isEmpty {
                                if let title = section.title {
                                    Text(title.uppercased())
                                        .font(.system(size: 9.5, weight: .semibold))
                                        .tracking(0.6)
                                        .foregroundStyle(Theme.tertiaryText)
                                        .padding(.top, 2)
                                }
                                ForEach(section.rows) { row in
                                    IslandRowView(row: row, tint: Color(islandHex: row.tint) ?? tint,
                                                  fallbackSymbol: panel.symbol ?? client.symbol) { button in
                                        hub.pressed(button, app: client.app, row: row.id)
                                    } open: {
                                        hub.open(row.url)
                                    }
                                }
                            }
                        }
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }

            if let footer = panel.footer, !footer.isEmpty {
                HStack(spacing: 8) {
                    Spacer()
                    ForEach(footer) { button in
                        Button(button.label) { hub.pressed(button, app: client.app, row: nil) }
                            .buttonStyle(PillButtonStyle(tint: tint, prominent: button.prominent ?? false, compact: true))
                    }
                }
            }
        }
    }
}

private struct IslandRowView: View {
    let row: IslandRow
    let tint: Color
    let fallbackSymbol: String
    let press: (IslandButton) -> Void
    let open: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(tint.opacity(0.18))
                .frame(width: 26, height: 26)
                .overlay {
                    Image(systemName: row.symbol ?? fallbackSymbol)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(tint)
                }
            VStack(alignment: .leading, spacing: 1) {
                Text(row.title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if let subtitle = row.subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 6)
            if let detail = row.detail {
                Text(detail)
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .fixedSize()
            }
            ForEach(row.buttons ?? []) { button in
                Button(button.label) { press(button) }
                    .buttonStyle(PillButtonStyle(tint: tint, prominent: button.prominent ?? false, compact: true))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(hovering && row.url != nil ? 0.07 : 0)))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { if row.url != nil { open() } }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}
