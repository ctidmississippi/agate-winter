import Foundation
import SwiftUI
import UserNotifications

/// One entry in the "don't miss" feed (Resources/events.json, hand-compiled, refreshed when asked).
struct RadarEvent: Decodable, Identifiable, Hashable {
    let start: String          // yyyy-MM-dd
    let end: String?           // yyyy-MM-dd, optional
    let sport: String
    let title: String
    let place: String?
    let tier: Int?             // 1 = don't miss, 2 = notable, 3 = minor
    let note: String?
    let result: String?        // filled in after the event happens

    var id: String { start + "|" + title }
    var big: Bool { (tier ?? 2) == 1 }

    var startDate: Date { RadarEvent.fmt.date(from: start) ?? .distantFuture }
    var endDate: Date { end.flatMap { RadarEvent.fmt.date(from: $0) } ?? startDate }

    static let fmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    var whenLabel: String {
        let df = DateFormatter()
        df.dateFormat = "MMM. d"
        let a = df.string(from: startDate)
        guard end != nil, end != start else { return a }
        let sameMonth = Calendar.current.isDate(startDate, equalTo: endDate, toGranularity: .month)
        df.dateFormat = sameMonth ? "d" : "MMM. d"
        return a + "–" + df.string(from: endDate)
    }
}

struct RadarFeed: Decodable {
    let updated: String?
    let events: [RadarEvent]
}

/// How much you want to hear about each sport: "all" events, "big" ones only (the default), or "off".
enum SportInterest {
    static let key = "sportInterest"

    static func dict(_ raw: String) -> [String: String] {
        var d: [String: String] = [:]
        for line in raw.components(separatedBy: "\n") {
            let parts = line.components(separatedBy: "=")
            if parts.count == 2 { d[parts[0]] = parts[1] }
        }
        return d
    }

    static func raw(_ d: [String: String]) -> String {
        d.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "\n")
    }

    static func level(_ sport: String, raw: String? = nil) -> String {
        dict(raw ?? UserDefaults.standard.string(forKey: key) ?? "")[sport] ?? "big"
    }

    static func knownSports() -> [String] {
        (UserDefaults.standard.string(forKey: "radarSports") ?? "").components(separatedBy: "\n").filter { !$0.isEmpty }
    }
}

@MainActor
final class RadarStore: ObservableObject {
    @Published var events: [RadarEvent] = []
    @Published var updated = ""
    @Published var loading = false

    func load(urlString: String) async {
        loading = true
        defer { loading = false }
        let defaults = UserDefaults.standard
        let cacheKey = "radarCache"
        // Show the last good copy (or the built-in one) right away, then refresh quietly.
        if events.isEmpty {
            var first: RadarFeed?
            if let data = defaults.data(forKey: cacheKey) { first = try? JSONDecoder().decode(RadarFeed.self, from: data) }
            if first == nil,
               let url = Bundle.main.url(forResource: "events", withExtension: "json"),
               let data = try? Data(contentsOf: url) {
                first = try? JSONDecoder().decode(RadarFeed.self, from: data)
            }
            if let first { apply(first) }
        }
        let t = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty, let url = URL(string: t),
           let (data, _) = try? await URLSession.shared.data(from: url),
           let feed = try? JSONDecoder().decode(RadarFeed.self, from: data) {
            defaults.set(data, forKey: cacheKey)
            apply(feed)
        }
        Reminders.schedule(events)
    }

    private func apply(_ feed: RadarFeed) {
        events = feed.events.sorted { $0.startDate < $1.startDate }
        updated = feed.updated ?? ""
        UserDefaults.standard.set(Set(events.map(\.sport)).sorted().joined(separator: "\n"), forKey: "radarSports")
    }
}

/// Local reminders: the evening before and the morning of each event you follow, plus every tier-1 event.
enum Reminders {
    static let followKey = "radarFollowed"
    static let autoKey = "radarAutoBig"

    static func followed() -> Set<String> {
        Set((UserDefaults.standard.string(forKey: followKey) ?? "").components(separatedBy: "\n").filter { !$0.isEmpty })
    }

    static func setFollowed(_ s: Set<String>) {
        UserDefaults.standard.set(s.sorted().joined(separator: "\n"), forKey: followKey)
    }

    static func schedule(_ events: [RadarEvent]) {
        let defaults = UserDefaults.standard
        let auto = defaults.object(forKey: autoKey) as? Bool ?? true
        let mine = followed()
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { pending in
            let old = pending.map(\.identifier).filter { $0.hasPrefix("radar|") }
            center.removePendingNotificationRequests(withIdentifiers: old)
            let now = Date()
            let chosen = events.filter { e in
                guard e.startDate > now.addingTimeInterval(-86_400) else { return false }
                if mine.contains(e.id) { return true }
                switch SportInterest.level(e.sport) {
                case "off": return false
                case "all": return true
                default: return auto && e.big
                }
            }
            var count = 0
            for e in chosen.sorted(by: { $0.startDate < $1.startDate }) {
                for (offsetDays, hour, lead) in [(-1, 18, "Tomorrow"), (0, 8, "Today")] {
                    guard count < 58 else { return }
                    guard let day = Calendar.current.date(byAdding: .day, value: offsetDays, to: e.startDate),
                          let fire = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: day),
                          fire > now else { continue }
                    let c = UNMutableNotificationContent()
                    c.title = "\(lead): \(e.title)"
                    c.body = [e.sport, e.place, e.whenLabel].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
                    c.sound = .default
                    let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
                    let trig = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
                    center.add(UNNotificationRequest(identifier: "radar|\(e.id)|\(offsetDays)", content: c, trigger: trig))
                    count += 1
                }
            }
        }
    }
}
