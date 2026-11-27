import Foundation

enum Fmt {
    private static func posix(_ format: String, tz: TimeZone? = nil) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        if let tz { f.timeZone = tz }
        f.dateFormat = format
        return f
    }

    private static let parser = posix("yyyy-MM-dd'T'HH:mm'Z'", tz: TimeZone(identifier: "UTC"))
    private static let parserSeconds = posix("yyyy-MM-dd'T'HH:mm:ss'Z'", tz: TimeZone(identifier: "UTC"))

    private static let clock: DateFormatter = {
        let f = posix("h:mm a")
        f.amSymbol = "a.m."
        f.pmSymbol = "p.m."
        return f
    }()

    private static let dayClock: DateFormatter = {
        let f = posix("EEE h:mm a")
        f.amSymbol = "a.m."
        f.pmSymbol = "p.m."
        return f
    }()

    private static let shortDate = posix("MMM d")
    private static let longDate = posix("EEEE · MMMM d, yyyy")
    private static let weekday = posix("EEEE")

    static func parse(_ s: String?) -> Date? {
        guard let s else { return nil }
        return parser.date(from: s) ?? parserSeconds.date(from: s)
    }

    static func time(_ d: Date?) -> String { d.map { clock.string(from: $0) } ?? "TBA" }
    static func dayTime(_ d: Date?) -> String { d.map { dayClock.string(from: $0) } ?? "TBA" }
    static func shortDay(_ d: Date?) -> String { d.map { shortDate.string(from: $0) } ?? "" }
    static func longDay(_ d: Date) -> String { longDate.string(from: d) }
    static func weekdayName(_ d: Date) -> String { weekday.string(from: d) }
}

extension Team {
    func label(for league: League) -> String {
        if league.useLocation {
            let loc = location ?? ""
            let ambiguous = ["LA", "Los Angeles", "New York", "NY", "Chicago"].contains(loc)
            if league.isProUS && ambiguous { return shortDisplayName ?? displayName ?? loc }
            if !loc.isEmpty { return loc }
        }
        return shortDisplayName ?? displayName ?? location ?? abbreviation ?? "?"
    }

    /// Everything we match favorites against.
    var searchText: String {
        [location, name, displayName, shortDisplayName].compactMap { $0 }.joined(separator: " ")
    }
}

extension Athlete {
    var label: String { shortName ?? displayName ?? fullName ?? "?" }
}

func isFavorite(_ text: String, favorites: [String]) -> Bool {
    let hay = text.lowercased()
    return favorites.contains { !$0.isEmpty && hay.contains($0) }
}

/// Favorite-team highlighting is switched off: only live games are colored.
func parseFavorites(_ raw: String) -> [String] { [] }
