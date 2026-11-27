import SwiftUI

/// A week of games for one league, with results for past days and the schedule for the rest.
struct CalendarView: View {
    @Environment(\.textScale) private var s
    @AppStorage("favorites") private var favoritesRaw = "Ole Miss, Titans, Grizzlies, Predators"
    @State private var leagueID = "nfl"
    @State private var weekStart = Calendar.current.startOfDay(for: Date())
    @State private var days: [(Date, [Block])] = []
    @State private var loading = false

    private var league: League { Catalog.all.first { $0.id == leagueID } ?? Catalog.all[0] }
    private var teamLeagues: [League] { Catalog.all }
    private var isTeam: Bool { league.kind == .team }
    @State private var tourney: [Block] = []

    var body: some View {
        NavigationStack {
            PageScroll {
                Masthead(title: "The Calendar", motto: "“A week at a time.”")
                Rule(height: 1)
                HStack {
                    Picker("League", selection: $leagueID) {
                        ForEach(teamLeagues) { Text($0.title + " · " + shortGroup($0)).tag($0.id) }
                    }
                    .pickerStyle(.menu)
                    .tint(Theme.accent)
                    Spacer()
                    if loading { ProgressView().controlSize(.small) }
                }
                .padding(.top, 6)
                HStack(spacing: 14) {
                    Button { shift(-7) } label: { Image(systemName: "chevron.left") }
                    Text(rangeLabel)
                        .font(.sans(12 * s, bold: true))
                        .foregroundStyle(Theme.ink)
                    Button { shift(7) } label: { Image(systemName: "chevron.right") }
                    Spacer()
                    Button("This week") { weekStart = Calendar.current.startOfDay(for: Date()) }
                        .font(.sans(12 * s, bold: true))
                }
                .foregroundStyle(Theme.accent)
                .padding(.vertical, 8)
                DoubleRule()

                if !isTeam {
                    ForEach(tourney) { BlockView(block: $0, favorites: parseFavorites(favoritesRaw)) }
                    if tourney.isEmpty && !loading {
                        StatusLine(text: "Nothing scheduled in these four weeks for \(league.title).")
                    }
                }
                ForEach(days, id: \.0) { day, blocks in
                    SportHeader(title: "\(Fmt.weekdayName(day)) · \(Fmt.shortDay(day))")
                    ForEach(blocks) { BlockView(block: $0, favorites: parseFavorites(favoritesRaw)) }
                }
                if isTeam && days.isEmpty && !loading {
                    StatusLine(text: "No games this week for \(league.title).")
                }
                StatusLine(text: "Via ESPN")
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 50).onEnded { v in
                    guard abs(v.translation.width) > abs(v.translation.height) * 2 else { return }
                    shift(v.translation.width < 0 ? 7 : -7)
                }
            )
            .refreshable { await load() }
            .task(id: "\(leagueID)|\(weekStart)") { await load() }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private func shortGroup(_ l: League) -> String { l.group }

    private var rangeLabel: String {
        let end = Calendar.current.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
        let span = isTeam ? 6 : 27
        let last = Calendar.current.date(byAdding: .day, value: span, to: weekStart) ?? end
        return "\(Fmt.shortDay(weekStart)) – \(Fmt.shortDay(last))"
    }

    private func shift(_ days: Int) {
        weekStart = Calendar.current.date(byAdding: .day, value: days, to: weekStart) ?? weekStart
    }

    @MainActor private func load() async {
        loading = true
        defer { loading = false }
        let lg = league
        let start = weekStart
        if lg.kind != .team {
            // Golf, racing, tennis and fights: list the next four weeks of events.
            days = []
            let end = Calendar.current.date(byAdding: .day, value: 27, to: start) ?? start
            let events = (try? await ESPNClient.scoreboardRange(lg, from: start, to: end)) ?? []
            if Task.isCancelled { return }
            tourney = BlockBuilder.tourneyBlocks(for: lg, events: events)
            return
        }
        tourney = []
        var results: [Int: [Block]] = [:]
        await withTaskGroup(of: (Int, [Block]).self) { group in
            for i in 0..<7 {
                guard let day = Calendar.current.date(byAdding: .day, value: i, to: start) else { continue }
                group.addTask {
                    let events = (try? await ESPNClient.scoreboard(lg, date: day)) ?? []
                    return (i, BlockBuilder.blocks(for: lg, events: events, day: day))
                }
            }
            for await (i, blocks) in group { results[i] = blocks }
        }
        if Task.isCancelled { return }
        var out: [(Date, [Block])] = []
        for i in 0..<7 {
            guard let day = Calendar.current.date(byAdding: .day, value: i, to: start),
                  let blocks = results[i], !blocks.isEmpty else { continue }
            out.append((day, blocks))
        }
        days = out
    }
}
