import CLockInCore
import SwiftUI

/// Another app's tab in the expanded notch, drawn from the rows it sent.
struct IslandPanelView: View {
    let panel: IslandPanel
    let client: IslandClient
    let viewModel: NotchViewModel

    private var hub: IslandHub { viewModel.model.island }
    private var tint: Color { Color(islandHex: panel.tint) ?? client.color }

    /// Section titles and rows as one list, so the tab can scroll through them a line at a time.
    private enum Item: Identifiable {
        case title(String, index: Int)
        case row(IslandRow)

        var id: String {
            switch self {
            case .title(_, let index): "title-\(index)"
            case .row(let row): "row-\(row.id)"
            }
        }
    }

    private var items: [Item] {
        panel.sections.enumerated().flatMap { index, section -> [Item] in
            guard !section.rows.isEmpty else { return [] }
            return (section.title.map { [.title($0, index: index)] } ?? []) + section.rows.map(Item.row)
        }
    }

    var body: some View {
        let items = items
        let first = min(viewModel.islandFirstRow, max(items.count - 1, 0))
        VStack(spacing: 8) {
            if items.isEmpty {
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
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(items[first...]) { item in
                        switch item {
                        case .title(let title, _):
                            Text(title.uppercased())
                                .font(.system(size: 9.5, weight: .semibold))
                                .tracking(0.6)
                                .foregroundStyle(Theme.tertiaryText)
                                .padding(.top, 2)
                        case .row(let row):
                            IslandRowView(row: row, tint: Color(islandHex: row.tint) ?? tint,
                                          fallbackSymbol: panel.symbol ?? client.symbol) { button in
                                hub.pressed(button, app: client.app, row: row.id)
                            } open: {
                                hub.open(row.url)
                            }
                        }
                    }
                }
                // Rows give way to the footer; whatever doesn't fit is a scroll away.
                .frame(maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
                .clipped()
                .contentShape(Rectangle())
                .animation(.snappy(duration: 0.2), value: first)
            }

            HStack(spacing: 8) {
                if items.count > 4 {
                    // A hint that there's more below, or that you've scrolled down.
                    Image(systemName: first > 0 ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.tertiaryText)
                }
                Spacer()
                ForEach(panel.footer ?? []) { button in
                    Button(button.label) { hub.pressed(button, app: client.app, row: nil) }
                        .buttonStyle(PillButtonStyle(tint: tint, prominent: button.prominent ?? false, compact: true))
                }
            }
            .layoutPriority(1)
            // Takes clicks across the whole strip, so a row cut off underneath can't.
            .contentShape(Rectangle())
        }
        .onAppear { viewModel.islandRowCount = items.count }
        .onChange(of: items.count) { _, count in viewModel.islandRowCount = count }
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
            // The row's text is its own button, so it never competes with the action buttons for a click.
            Button(action: open) { label }
                .buttonStyle(.plain)
            ForEach(row.buttons ?? []) { button in
                Button(button.label) { press(button) }
                    .buttonStyle(PillButtonStyle(tint: tint, prominent: button.prominent ?? false, compact: true))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(hovering && row.url != nil ? 0.07 : 0)))
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }

    private var label: some View {
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
        }
        .contentShape(Rectangle())
    }
}
