import SwiftUI

struct PollsView: View {
    @Environment(\.textScale) private var s
    @AppStorage("favorites") private var favoritesRaw = "Ole Miss, Titans, Grizzlies, Predators"
    @State private var leagueID = "cfb-fbs"
    @State private var tables: [TableData] = []
    @State private var loading = false
    @State private var failed = false

    private var league: League { Catalog.withRankings.first { $0.id == leagueID } ?? Catalog.withRankings[0] }

    var body: some View {
        NavigationStack {
            PageScroll {
                Masthead(title: "The Polls", motto: "“Ranked, ranked again, and ranked once more.”")
                Rule(height: 1)
                HStack {
                    Picker("Sport", selection: $leagueID) {
                        ForEach(Catalog.withRankings) { Text($0.title).tag($0.id) }
                    }
                    .pickerStyle(.menu)
                    .tint(Theme.accent)
                    Spacer()
                    if loading { ProgressView().controlSize(.small) }
                }
                .padding(.vertical, 6)
                DoubleRule()
                ForEach(tables) { AgateTable(table: $0, favorites: parseFavorites(favoritesRaw)) }
                if failed { StatusLine(text: "Couldn't load polls. Pull down to retry.") }
                else if tables.isEmpty && !loading { StatusLine(text: "No polls available.") }
                StatusLine(text: "Via ESPN")
            }
            .refreshable { await load() }
            .task(id: leagueID) { await load() }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private func load() async {
        loading = true
        failed = false
        defer { loading = false }
        do {
            let polls = try await ESPNClient.rankings(league)
            if Task.isCancelled { return }
            tables = polls.compactMap { Self.table(from: $0, league: league) }
        } catch {
            if Task.isCancelled { return }
            tables = []
            failed = true
        }
    }

    private static func table(from poll: Poll, league: League) -> TableData? {
        guard let ranks = poll.ranks, !ranks.isEmpty else { return nil }
        let hasPoints = ranks.contains { ($0.points ?? 0) > 0 }
        var headers = ["", "TEAM", "REC"]
        if hasPoints { headers.append("PTS") }
        headers.append("PRV")
        let rows = ranks.map { r -> [String] in
            var cells = [
                r.current.map(String.init) ?? "",
                r.team?.location ?? r.team?.shortDisplayName ?? r.team?.displayName ?? "?",
                r.recordSummary ?? "",
            ]
            if hasPoints { cells.append(Self.points(r.points)) }
            cells.append((r.previous ?? 0) > 0 ? String(r.previous ?? 0) : "—")
            return cells
        }
        return TableData(caption: poll.name ?? poll.headline ?? "Poll", headers: headers, rows: rows)
    }

    private static func points(_ p: Double?) -> String {
        guard let p, p > 0 else { return "" }
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: p)) ?? String(Int(p))
    }
}
