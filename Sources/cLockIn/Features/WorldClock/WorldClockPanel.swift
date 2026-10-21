import CLockInCore
import SwiftUI

struct WorldClockPanel: View {
    let model: AppModel
    /// The clocks only tick while the panel is on screen.
    let isVisible: Bool

    static let maxShown = 4

    private var cities: [WorldClockCity] { Array(model.worldClocks.prefix(Self.maxShown)) }
    private var hasRoom: Bool { model.worldClocks.count < Self.maxShown }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1, paused: !isVisible)) { context in
            ZStack {
                switch model.settings.worldClockStyle {
                case .analog:
                    HStack(alignment: .top, spacing: 0) {
                        ForEach(cities) { city in
                            CityClock(city: city, date: context.date)
                                .frame(maxWidth: .infinity)
                        }
                        if hasRoom {
                            AddCityButton(model: model)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
                case .digital:
                    Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                        ForEach(Array(stride(from: 0, to: cities.count + (hasRoom ? 1 : 0), by: 2)), id: \.self) { row in
                            GridRow {
                                digitalCell(at: row, date: context.date)
                                digitalCell(at: row + 1, date: context.date)
                            }
                        }
                    }
                    .frame(maxHeight: .infinity, alignment: .top)
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
                }
            }
            .animation(Motion.content, value: model.settings.worldClockStyle)
        }
        .overlay(alignment: .bottomTrailing) {
            if model.worldClocks.count > Self.maxShown {
                Button("+\(model.worldClocks.count - Self.maxShown) more") {
                    SettingsWindowController.shared.show(model: model)
                }
                .buttonStyle(PillButtonStyle(tint: .white, compact: true))
            }
        }
        .padding(.top, 6)
    }
}

extension WorldClockPanel {
    @ViewBuilder
    private func digitalCell(at index: Int, date: Date) -> some View {
        if index < cities.count {
            DigitalCityClock(city: cities[index], date: date)
        } else if index == cities.count && hasRoom {
            AddCityTile(model: model)
        } else {
            Color.clear.frame(height: 1)
        }
    }
}

/// A wide tile: day or night symbol, city and offset on the left, the time large on the right.
private struct DigitalCityClock: View {
    let city: WorldClockCity
    let date: Date

    var body: some View {
        let zone = city.timeZone
        let isDay = WorldClock.isDaytime(in: zone, at: date)
        HStack(spacing: 10) {
            Image(systemName: isDay ? "sun.max.fill" : "moon.stars.fill")
                .font(.system(size: 15))
                .foregroundStyle(isDay ? Theme.timer : Theme.worldClock)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(city.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(WorldClock.relation(of: zone, at: date))
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                AnimatedTime(text: time(in: zone), size: 26)
                if let period = period(in: zone) {
                    Text(period)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.secondaryText)
                }
            }
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 62)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.07)))
    }

    private func time(in zone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let hour = parts.hour ?? 0
        return NotchViewModel.uses12HourClock
            ? String(format: "%d:%02d", hour % 12 == 0 ? 12 : hour % 12, parts.minute ?? 0)
            : String(format: "%02d:%02d", hour, parts.minute ?? 0)
    }

    private func period(in zone: TimeZone) -> String? {
        guard NotchViewModel.uses12HourClock else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar.component(.hour, from: date) < 12 ? Calendar.current.amSymbol : Calendar.current.pmSymbol
    }
}

private struct AddCityTile: View {
    let model: AppModel

    var body: some View {
        Button {
            SettingsWindowController.shared.show(model: model, section: .worldClock)
        } label: {
            Label("Add city", systemImage: "plus")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.secondaryText)
                .frame(maxWidth: .infinity, minHeight: 62)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color.white.opacity(0.2), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Analog or digital, switched from the panel's top bar.
struct WorldClockStyleToggle: View {
    let settings: AppSettings

    var body: some View {
        HStack(spacing: 2) {
            ForEach(WorldClockStyle.allCases) { style in
                let isOn = settings.worldClockStyle == style
                Button {
                    settings.worldClockStyle = style
                } label: {
                    Image(systemName: style.symbol)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(isOn ? .white : Theme.secondaryText)
                        .frame(width: 24, height: 20)
                        .background(Capsule().fill(Color.white.opacity(isOn ? 0.16 : 0)))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(style.title)
            }
        }
        .padding(2)
        .background(Capsule().fill(Color.white.opacity(0.06)))
        .animation(Motion.press, value: settings.worldClockStyle)
    }
}

private struct CityClock: View {
    let city: WorldClockCity
    let date: Date

    var body: some View {
        let zone = city.timeZone
        VStack(spacing: 6) {
            AnalogClock(date: date, timeZone: zone, isDaytime: WorldClock.isDaytime(in: zone, at: date))
                .frame(width: 70, height: 70)
            VStack(spacing: 1) {
                Text(city.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(timeText(in: zone))
                    .font(.system(size: 11, weight: .medium, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.8))
                Text(WorldClock.relation(of: zone, at: date))
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
            }
        }
    }

    private func timeText(in zone: TimeZone) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        style.timeZone = zone
        return date.formatted(style)
    }
}

private struct AddCityButton: View {
    let model: AppModel

    var body: some View {
        Button {
            SettingsWindowController.shared.show(model: model, section: .worldClock)
        } label: {
            VStack(spacing: 6) {
                Circle()
                    .strokeBorder(Color.white.opacity(0.2), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                    .frame(width: 70, height: 70)
                    .overlay {
                        Image(systemName: "plus")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(Theme.secondaryText)
                    }
                Text("Add city")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.secondaryText)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A small analog face: light during the day, dark at night, like the Clock widget.
struct AnalogClock: View {
    let date: Date
    let timeZone: TimeZone
    let isDaytime: Bool

    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            let center = CGPoint(x: rect.midX, y: rect.midY)
            let radius = min(size.width, size.height) / 2
            let face = isDaytime ? Color.white : Color(white: 0.16)
            let ink = isDaytime ? Color.black : Color.white

            context.fill(Path(ellipseIn: rect), with: .color(face))

            // Hour marks.
            for index in 0..<12 {
                let angle = Angle.degrees(Double(index) * 30)
                let outer = point(center, radius * 0.88, angle)
                let inner = point(center, radius * (index % 3 == 0 ? 0.72 : 0.78), angle)
                var mark = Path()
                mark.move(to: inner)
                mark.addLine(to: outer)
                context.stroke(mark, with: .color(ink.opacity(index % 3 == 0 ? 0.8 : 0.35)), lineWidth: index % 3 == 0 ? 1.6 : 1)
            }

            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = timeZone
            let parts = calendar.dateComponents([.hour, .minute, .second], from: date)
            let seconds = Double(parts.second ?? 0)
            let minutes = Double(parts.minute ?? 0) + seconds / 60
            let hours = Double((parts.hour ?? 0) % 12) + minutes / 60

            hand(context, center, length: radius * 0.5, width: 2.6, angle: .degrees(hours * 30), color: ink)
            hand(context, center, length: radius * 0.74, width: 1.8, angle: .degrees(minutes * 6), color: ink)
            hand(context, center, length: radius * 0.8, width: 0.9, angle: .degrees(seconds * 6), color: Theme.timer)
            context.fill(Path(ellipseIn: CGRect(x: center.x - 2.2, y: center.y - 2.2, width: 4.4, height: 4.4)), with: .color(Theme.timer))
        }
    }

    private func point(_ center: CGPoint, _ distance: CGFloat, _ angle: Angle) -> CGPoint {
        CGPoint(x: center.x + distance * CGFloat(Foundation.sin(angle.radians)), y: center.y - distance * CGFloat(Foundation.cos(angle.radians)))
    }

    private func hand(_ context: GraphicsContext, _ center: CGPoint, length: CGFloat, width: CGFloat, angle: Angle, color: Color) {
        var path = Path()
        path.move(to: point(center, -length * 0.15, angle))
        path.addLine(to: point(center, length, angle))
        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round))
    }
}
