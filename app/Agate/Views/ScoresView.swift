import SwiftUI

struct ScoresView: View {
    @Environment(\.textScale) private var s
    @StateObject private var store = ScoresStore()
    @State private var date = Date()
    @State private var byTime = false
    @State private var showSettings = false
    @State private var showShare = false
    @StateObject private var radar = RadarStore()
    @AppStorage("winterURL") private var winterURL = ""
    @AppStorage("dataSaver") private var dataSaver = false
    @AppStorage("favorites") private var favoritesRaw = "Ole Miss, Titans, Grizzlies, Predators"
    @AppStorage("disabledLeagues") private var disabledRaw = ""

    private var favorites: [String] { parseFavorites(favoritesRaw) }
    private var enabledLeagues: [League] {
        let off = DisabledLeagues.set(from: disabledRaw)
        return Catalog.all.filter { !off.contains($0.id) }
    }
    private var loadKey: String { "\(ESPNClient.ymd(date))|\(disabledRaw)" }
    private var isToday: Bool { Calendar.current.isDateInToday(date) }

    var body: some View {
        NavigationStack {
            PageScroll {
                Masthead()
                Rule(height: 1)
                dateline
                DoubleRule()
                dateBar
                Picker("View", selection: $byTime) {
                    Text("By league").tag(false)
                    Text("By time").tag(true)
                }
                .pickerStyle(.segmented)
                .padding(.bottom, 6)
                if !byTime && isToday {
                    TodayBrief(groups: store.groups, events: radar.events, favorites: favorites)
                }
                if !byTime && isToday && !closeRows.isEmpty {
                    BlockView(block: Block(id: "close", title: "Close games right now", rows: closeRows), favorites: favorites)
                }
                content
            }
            // Swipe left for the next day, right for the previous day (ignores mostly-vertical drags).
            .simultaneousGesture(
                DragGesture(minimumDistance: 50).onEnded { v in
                    guard abs(v.translation.width) > abs(v.translation.height) * 2 else { return }
                    shift(v.translation.width < 0 ? 1 : -1)
                }
            )
            .refreshable { await store.load(date: date, leagues: enabledLeagues) }
            .task(id: loadKey) {
                if isToday { store.loadSaved() }
                await store.load(date: date, leagues: enabledLeagues)
                // Keep refreshing while today's page is open and a game is live. Only leagues
                // with a live game are reloaded, which keeps the data use small.
                while !Task.isCancelled && isToday && store.hasLive {
                    try? await Task.sleep(nanoseconds: (dataSaver ? 120 : 45) * 1_000_000_000)
                    if Task.isCancelled { break }
                    let live = store.liveLeagueIDs
                    await store.load(date: date, leagues: enabledLeagues, only: live.isEmpty ? nil : live)
                }
            }
            .task(id: winterURL) {
                let t = winterURL.trimmingCharacters(in: .whitespacesAndNewlines)
                await radar.load(urlString: t.isEmpty ? "" : t.replacingOccurrences(of: "winter.json", with: "events.json"))
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sheet(isPresented: $showShare) { DayShareSheet(date: date, groups: store.groups) }
        }
    }

    private var dateline: some View {
        HStack {
            Text("\(Fmt.weekdayName(date).capitalized) Edition")
                .font(.sans(11.5 * s, bold: true))
            Spacer()
            Text(Fmt.longDay(date).components(separatedBy: " · ").last ?? "")
                .font(.sans(11.5 * s))
        }
        .foregroundStyle(Theme.ink)
        .padding(.vertical, 6)
    }

    private var dateBar: some View {
        HStack(spacing: 14) {
            Button { shift(-1) } label: { Image(systemName: "chevron.left") }
            Button { shift(1) } label: { Image(systemName: "chevron.right") }
            if !isToday {
                Button("Today") { date = Date() }
                    .font(.sans(12 * s, bold: true))
            }
            Spacer()
            if store.isLoading { ProgressView().controlSize(.small) }
            Button { showShare = true } label: { Image(systemName: "square.and.arrow.up") }
                .accessibilityLabel("Share the day")
            Button { showSettings = true } label: { Image(systemName: "gearshape") }
                .accessibilityLabel("Settings")
            DatePicker("", selection: $date, displayedComponents: .date)
                .labelsHidden()
        }
        .tint(Theme.accent)
        .foregroundStyle(Theme.accent)
        .padding(.vertical, 8)
    }

    /// Live games that are tight late in the game.
    private var closeRows: [Row] {
        store.groups.flatMap { g in
            g.blocks.flatMap { b in
                b.rows.filter { $0.close }.map { r in
                    Row(kind: .live, left: "\(b.title.leagueTag): \(r.left)", right: r.right, search: r.search, game: r.game, art: r.art)
                }
            }
        }
    }

    /// Every game across leagues, by status then start time.
    private var slate: Block? {
        var live: [(Date, Row)] = [], next: [(Date, Row)] = [], done: [(Date, Row)] = []
        for g in store.groups {
            for b in g.blocks {
                for r in b.rows where r.kind == .line || r.kind == .live {
                    guard let start = r.start else { continue }
                    let row = Row(kind: r.kind, left: "\(b.title.leagueTag) · \(r.left)", right: r.right, search: r.search, game: r.game, start: start, art: r.art)
                    if r.kind == .live { live.append((start, row)) }
                    else if r.game != nil || r.isFinal { done.append((start, row)) }
                    else { next.append((start, row)) }
                }
            }
        }
        var rows: [Row] = []
        if !live.isEmpty { rows.append(Row(kind: .sub, left: "Live now")); rows += live.sorted { $0.0 < $1.0 }.map { $0.1 } }
        if !next.isEmpty { rows.append(Row(kind: .sub, left: "Up next")); rows += next.sorted { $0.0 < $1.0 }.map { $0.1 } }
        if !done.isEmpty { rows.append(Row(kind: .sub, left: "Final")); rows += done.sorted { $0.0 > $1.0 }.map { $0.1 } }
        return rows.isEmpty ? nil : Block(id: "slate", title: "Today's slate", rows: rows)
    }

    @ViewBuilder private var content: some View {
        if byTime {
            if let slate { BlockView(block: slate, favorites: favorites) }
        } else {
            ForEach(store.groups) { group in
                SportHeader(title: group.title, sport: group.blocks.first?.sport ?? "")
                ForEach(group.blocks) { block in
                    BlockView(block: block, favorites: favorites)
                }
            }
        }
        if store.groups.isEmpty && !store.isLoading {
            StatusLine(text: "No games found for this date.")
        }
        if store.offline || store.showingSaved {
            StatusLine(text: store.offline
                       ? "Can't reach the score feeds. Showing saved scores from \(Fmt.time(store.updated ?? Date()))."
                       : "Showing saved scores from \(Fmt.time(store.updated ?? Date())) while the feeds respond.")
        }
        if !store.failures.isEmpty && !store.offline {
            StatusLine(text: "No response from: " + store.failures.joined(separator: ", ") + ".")
        }
        if store.offline || !store.failures.isEmpty {
            Button("Try again") {
                Task { await store.load(date: date, leagues: enabledLeagues) }
            }
            .font(.sans(13 * s, bold: true))
            .foregroundStyle(Theme.accent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        if let updated = store.updated {
            StatusLine(text: "Via ESPN, NHL, MLB · refreshed \(Fmt.time(updated))")
        }
    }

    private func shift(_ days: Int) {
        date = Calendar.current.date(byAdding: .day, value: days, to: date) ?? date
    }
}
