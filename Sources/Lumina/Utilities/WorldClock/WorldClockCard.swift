import SwiftUI

/// A world clock the user added. Each one is its own half-width utility.
struct WorldClock: Codable, Hashable {
    /// Whether and how the clock also appears in the menu bar.
    enum MenuBarDisplay: String, Codable, CaseIterable {
        case off
        case time
        case codeAndTime
    }

    /// The utility ID, unique per clock so a city can be added more than once.
    let id: String
    let cityCode: String
    var menuBar: MenuBarDisplay

    init(id: String, cityCode: String, menuBar: MenuBarDisplay = .off) {
        self.id = id
        self.cityCode = cityCode
        self.menuBar = menuBar
    }

    // Clocks saved before the menu bar option existed decode as off.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        cityCode = try container.decode(String.self, forKey: .cityCode)
        menuBar = try container.decodeIfPresent(MenuBarDisplay.self, forKey: .menuBar) ?? .off
    }
}

extension Utility {
    /// The utility for a world clock, or nil if its city no longer exists.
    static func worldClock(_ clock: WorldClock) -> Utility? {
        guard let city = WorldClockCity.city(withCode: clock.cityCode) else { return nil }
        return Utility(
            id: clock.id,
            name: city.name,
            symbol: "clock",
            size: .half,
            content: { AnyView(WorldClockCard(city: city)) },
            settings: { AnyView(WorldClockSettings(clockID: clock.id, city: city)) },
            isRemovable: true
        )
    }
}

/// Shows a city's time large, with its flag and code above and how far ahead
/// or behind it is below.
struct WorldClockCard: View {
    let city: WorldClockCity

    var body: some View {
        TimelineView(.everyMinute) { context in
            let moment = WorldClockMoment(city: city, date: context.date)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(city.flag)
                        .font(.system(size: 13))
                    Text(city.code)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Image(systemName: moment.isNight ? "moon.fill" : "sun.max.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(moment.isNight ? Color.indigo : Color.orange)
                        .contentTransition(.symbolEffect(.replace))
                }

                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(moment.time)
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    if let period = moment.period {
                        Text(period)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.8)

                Text(moment.relativeDescription)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .animation(.smooth, value: moment.time)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(city.name)
            .accessibilityValue("\(moment.time) \(moment.period ?? ""), \(moment.relativeDescription)")
        }
    }
}

/// A city's time at a given moment, formatted for the clock card and picker.
struct WorldClockMoment {
    /// For example "10:26", or "22:26" with a 24-hour clock.
    let time: String
    /// "AM" or "PM" with a 12-hour clock, otherwise nil.
    let period: String?
    let isNight: Bool
    /// For example "Today, +8h" or "Tomorrow, +15h".
    let relativeDescription: String

    init(city: WorldClockCity, date: Date) {
        let zone = city.timeZone
        let uses12Hour = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current)?.contains("a") ?? false

        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.timeZone = zone
        formatter.dateFormat = uses12Hour ? "h:mm" : "HH:mm"
        time = formatter.string(from: date)
        if uses12Hour {
            formatter.dateFormat = "a"
            period = formatter.string(from: date)
        } else {
            period = nil
        }

        var cityCalendar = Calendar.current
        cityCalendar.timeZone = zone
        let hour = cityCalendar.component(.hour, from: date)
        isNight = hour < 6 || hour >= 20

        relativeDescription = "\(Self.day(in: cityCalendar, at: date)), \(Self.offset(of: zone, at: date))"
    }

    /// "Today", "Tomorrow" or "Yesterday", from the user's point of view.
    private static func day(in cityCalendar: Calendar, at date: Date) -> String {
        let local = Calendar.current
        let cityDay = cityCalendar.dateComponents([.year, .month, .day], from: date)
        let localDay = local.dateComponents([.year, .month, .day], from: date)
        guard let cityDate = local.date(from: cityDay), let localDate = local.date(from: localDay) else { return "Today" }
        switch local.dateComponents([.day], from: localDate, to: cityDate).day ?? 0 {
        case 1: return "Tomorrow"
        case -1: return "Yesterday"
        default: return "Today"
        }
    }

    /// How far ahead or behind the city is, like "+8h", "−5h" or "+5h 30m".
    private static func offset(of zone: TimeZone, at date: Date) -> String {
        let difference = zone.secondsFromGMT(for: date) - TimeZone.current.secondsFromGMT(for: date)
        guard difference != 0 else { return "Same time" }
        let sign = difference > 0 ? "+" : "−"
        let hours = abs(difference) / 3600
        let minutes = abs(difference) % 3600 / 60
        return minutes == 0 ? "\(sign)\(hours)h" : "\(sign)\(hours)h \(minutes)m"
    }
}
