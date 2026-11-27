import WidgetKit
import SwiftUI
import ActivityKit

// A "Don't Miss" widget: the next big events from events.json, a file of a few kilobytes.
// See README.txt in this folder for the Xcode steps.

private let feedURL = "https://raw.githubusercontent.com/ctidmississippi/agate-winter/main/events.json"
private let cacheKey = "widgetEventsCache"

struct MiniEvent: Decodable, Identifiable {
    let start: String
    let end: String?
    let sport: String
    let title: String
    let tier: Int?
    var id: String { start + "|" + title }
    var big: Bool { tier == 1 }

    private static let df: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    var startDate: Date { Self.df.date(from: start) ?? .distantFuture }
    var endDate: Date { Self.df.date(from: end ?? start) ?? startDate }

    func label(from now: Date) -> String {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        if startDate <= today && endDate >= today { return startDate == endDate ? "Today" : "Now" }
        let days = cal.dateComponents([.day], from: today, to: startDate).day ?? 0
        if days == 1 { return "Tomorrow" }
        if days < 7 { return "In \(days) days" }
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: startDate)
    }
}

private struct MiniFeed: Decodable { let events: [MiniEvent] }

struct Entry: TimelineEntry {
    let date: Date
    let events: [MiniEvent]
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry {
        Entry(date: Date(), events: [MiniEvent(start: "2027-04-19", end: nil, sport: "Running", title: "Boston Marathon", tier: 1)])
    }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        Task {
            let all = await load()
            let now = Date()
            let today = Calendar.current.startOfDay(for: now)
            let week = Calendar.current.date(byAdding: .day, value: 7, to: today) ?? today
            let upcoming = all
                .filter { $0.endDate >= today && ($0.big || $0.startDate < week) }
                .sorted { $0.startDate == $1.startDate ? ($0.big && !$1.big) : $0.startDate < $1.startDate }
            let next = Calendar.current.date(byAdding: .hour, value: 6, to: now) ?? now
            completion(Timeline(entries: [Entry(date: now, events: Array(upcoming.prefix(6)))], policy: .after(next)))
        }
    }

    private func load() async -> [MiniEvent] {
        let defaults = UserDefaults.standard
        if let url = URL(string: feedURL),
           let (data, _) = try? await URLSession.shared.data(from: url),
           let feed = try? JSONDecoder().decode(MiniFeed.self, from: data) {
            defaults.set(data, forKey: cacheKey)
            return feed.events
        }
        if let data = defaults.data(forKey: cacheKey),
           let feed = try? JSONDecoder().decode(MiniFeed.self, from: data) {
            return feed.events
        }
        return []
    }
}

struct AgateWidgetView: View {
    let entry: Entry
    private let ink = Color(red: 0.09, green: 0.09, blue: 0.09)
    private let accent = Color(red: 0.55, green: 0.10, blue: 0.10)

    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryInline:
            Text(entry.events.first.map { "\($0.label(from: entry.date)): \($0.title)" } ?? "Nothing big soon")
        case .accessoryCircular:
            let days = entry.events.first.map { max(0, Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: entry.date), to: $0.startDate).day ?? 0) }
            VStack(spacing: 0) {
                Text(days.map(String.init) ?? "–").font(.system(size: 20, weight: .bold))
                Text("days").font(.system(size: 9))
            }
            .containerBackground(.clear, for: .widget)
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                if entry.events.isEmpty { Text("Nothing big soon").font(.system(size: 12)) }
                ForEach(entry.events.prefix(3)) { e in
                    Text("\(e.label(from: entry.date)) · \(e.title)")
                        .font(.system(size: 11, weight: e.big ? .bold : .regular))
                        .lineLimit(1)
                }
            }
            .containerBackground(.clear, for: .widget)
        default:
            home
        }
    }

    private var home: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Don't Miss")
                .font(.system(size: 15, weight: .black, design: .serif))
            Rectangle().frame(height: 1)
            if entry.events.isEmpty {
                Text("Nothing big on the radar.")
                    .font(.system(size: 11, design: .serif)).italic().padding(.top, 4)
            }
            ForEach(entry.events.prefix(family == .systemSmall ? 3 : 5)) { e in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(e.label(from: entry.date))
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(e.big ? accent : .secondary)
                        .frame(width: family == .systemSmall ? 0 : 62, alignment: .leading)
                        .opacity(family == .systemSmall ? 0 : 1)
                    Text(e.title)
                        .font(.system(size: 12, weight: e.big ? .bold : .regular, design: .serif))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(ink)
        .containerBackground(Color(red: 0.945, green: 0.937, blue: 0.918), for: .widget)
    }
}

struct AgateWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AgateWidget", provider: Provider()) { entry in
            AgateWidgetView(entry: entry)
        }
        .configurationDisplayName("Don't Miss")
        .description("The next big events, from your Don't Miss list.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline, .accessoryCircular])
    }
}

// MARK: - Live Activity (lock screen and Dynamic Island)

struct AgateLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AgateGameAttributes.self) { context in
            VStack(alignment: .leading, spacing: 2) {
                Text(context.attributes.title.uppercased()).font(.system(size: 10, weight: .bold))
                Text(context.state.score).font(.system(size: 15, weight: .bold, design: .serif))
                Text(context.state.detail).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .padding(12)
            .activityBackgroundTint(Color(red: 0.945, green: 0.937, blue: 0.918))
            .foregroundStyle(Color(red: 0.09, green: 0.09, blue: 0.09))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.score).font(.system(size: 14, weight: .bold)).lineLimit(2)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.detail).font(.system(size: 12))
                }
            } compactLeading: {
                Text("LIVE").font(.system(size: 10, weight: .bold))
            } compactTrailing: {
                Text(context.state.detail).font(.system(size: 10)).lineLimit(1)
            } minimal: {
                Text("•")
            }
        }
    }
}

@main
struct AgateWidgetBundle: WidgetBundle {
    var body: some Widget {
        AgateWidget()
        AgateLiveActivity()
    }
}
