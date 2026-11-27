import SwiftUI

/// "Don't miss": every major event across all sports, by date, so nothing slips past.
struct RadarView: View {
    @Environment(\.textScale) private var s
    @StateObject private var store = RadarStore()
    @AppStorage("winterURL") private var winterURL = ""
    @AppStorage(Reminders.autoKey) private var autoBig = true
    @AppStorage(SportInterest.key) private var interestRaw = ""
    @State private var sport = "All sports"
    @State private var bigOnly = false
    @State private var followed = Reminders.followed()

    private var feedURL: String {
        let t = winterURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "" : t.replacingOccurrences(of: "winter.json", with: "events.json")
    }

    private var sports: [String] { ["All sports"] + Array(Set(store.events.map(\.sport))).sorted() }

    private var shown: [RadarEvent] {
        store.events.filter {
            (sport == "All sports" || $0.sport == sport) && (!bigOnly || $0.big)
                && SportInterest.level($0.sport, raw: interestRaw) != "off"
        }
    }

    private var today: Date { Calendar.current.startOfDay(for: Date()) }

    private func days(_ n: Int) -> Date { Calendar.current.date(byAdding: .day, value: n, to: today) ?? today }

    private var happeningNow: [RadarEvent] { shown.filter { $0.startDate <= today && $0.endDate >= today } }
    private var thisWeek: [RadarEvent] { shown.filter { $0.startDate > today && $0.startDate < days(8) } }
    private var thisMonth: [RadarEvent] { shown.filter { $0.startDate >= days(8) && $0.startDate < days(31) } }
    private var later: [RadarEvent] { shown.filter { $0.startDate >= days(31) } }
    private var justHappened: [RadarEvent] {
        shown.filter { $0.endDate < today && $0.endDate >= days(-21) }.sorted { $0.endDate > $1.endDate }
    }

    var body: some View {
        PageScroll {
            Masthead(title: "Don't Miss", motto: "“Every big event, on the calendar before it starts.”")
            DoubleRule()
            HStack {
                Picker("Sport", selection: $sport) {
                    ForEach(sports, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.menu)
                .tint(Theme.accent)
                Spacer()
                Toggle("Big only", isOn: $bigOnly)
                    .font(.sans(12 * s, bold: true))
                    .fixedSize()
                    .tint(Theme.accent)
            }
            .padding(.vertical, 4)
            if !store.updated.isEmpty {
                StatusLine(text: "Compiled \(store.updated). Tap the bell to get a reminder the evening before and the morning of. Big events always remind you unless you switch that off in Settings.")
            }
            section("Happening now", happeningNow)
            section("This week", thisWeek)
            section("Next 30 days", thisMonth)
            section("Just happened", justHappened, past: true)
            section("Later", later)
            if shown.isEmpty && !store.loading {
                StatusLine(text: "Nothing matches. Clear the filters, or check the data URL in Settings.")
            }
        }
        .refreshable { await store.load(urlString: feedURL) }
        .task(id: winterURL) {
            if autoBig { Alerts.requestAuthorization() }
            await store.load(urlString: feedURL)
        }
    }

    @ViewBuilder private func section(_ title: String, _ list: [RadarEvent], past: Bool = false) -> some View {
        if !list.isEmpty {
            SportHeader(title: title)
            ForEach(list) { e in row(e, past: past) }
        }
    }

    private func monthDay(_ d: Date, _ fmt: String) -> String {
        let f = DateFormatter()
        f.dateFormat = fmt
        return f.string(from: d)
    }

    private func row(_ e: RadarEvent, past: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 0) {
                Text(monthDay(e.startDate, "MMM").uppercased())
                    .font(.sans(9.5 * s, bold: true))
                    .tracking(0.8)
                Text(monthDay(e.startDate, "d"))
                    .font(.head(20 * s, black: true))
            }
            .foregroundStyle(e.big ? Theme.accent : Theme.ink2)
            .frame(width: 34 * s)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(e.title)
                        .font(.head(15.5 * s, black: e.big))
                        .foregroundStyle(Theme.ink)
                    if e.big {
                        Text("BIG")
                            .font(.sans(8.5 * s, bold: true))
                            .tracking(0.8)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .overlay(Rectangle().stroke(Theme.accent, lineWidth: 0.5))
                            .foregroundStyle(Theme.accent)
                    }
                }
                Text(([e.sport] + [e.place ?? ""]).filter { !$0.isEmpty }.joined(separator: " · ") + "  ·  " + e.whenLabel)
                    .font(.sans(11 * s))
                    .foregroundStyle(Theme.muted)
                if let r = e.result, past {
                    Text(r).font(.line(13 * s, bold: true)).foregroundStyle(Theme.ink)
                } else if past {
                    Text("Result not compiled yet. Ask for a refresh.")
                        .font(.sans(11 * s)).italic().foregroundStyle(Theme.muted)
                }
                if let n = e.note, !n.isEmpty {
                    Text(n).font(.sans(11 * s)).italic().foregroundStyle(Theme.muted)
                }
            }
            .padding(.leading, e.big ? 8 : 0)
            .overlay(alignment: .leading) {
                if e.big { Rectangle().fill(Theme.accent).frame(width: 2) }
            }
            Spacer(minLength: 4)
            if !past {
                Button {
                    if followed.contains(e.id) { followed.remove(e.id) } else { followed.insert(e.id) }
                    Reminders.setFollowed(followed)
                    Alerts.requestAuthorization()
                    Reminders.schedule(store.events)
                } label: {
                    Image(systemName: followed.contains(e.id) ? "bell.fill" : "bell")
                        .foregroundStyle(followed.contains(e.id) || (e.big && autoBig) ? Theme.accent : Theme.muted)
                        .padding(6)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 5)
        .overlay(alignment: .bottom) { Rule(height: 0.5, color: Theme.rule) }
    }
}

/// The Calendar tab: the don't-miss list first, the game calendar second.
struct CalendarHub: View {
    @State private var page = 0
    var body: some View {
        VStack(spacing: 0) {
            Picker("Section", selection: $page) {
                Text("Don't miss").tag(0)
                Text("Games").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Theme.paper)
            if page == 0 { RadarView() } else { CalendarView() }
        }
        .background(Theme.paper.ignoresSafeArea())
    }
}
