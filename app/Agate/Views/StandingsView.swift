import SwiftUI

struct StandingsView: View {
    @Environment(\.textScale) private var s
    @AppStorage("favorites") private var favoritesRaw = "Ole Miss, Titans, Grizzlies, Predators"
    @State private var leagueID = "cfb-fbs"
    @State private var tables: [TableData] = []
    @State private var loading = false
    @State private var failed = false

    private var league: League { Catalog.withStandings.first { $0.id == leagueID } ?? Catalog.withStandings[0] }

    var body: some View {
        NavigationStack {
            PageScroll {
                Masthead(title: "Standings", motto: "“Where everyone stands, in small type.”")
                Rule(height: 1)
                HStack {
                    Picker("League", selection: $leagueID) {
                        ForEach(Catalog.withStandings) { Text($0.title).tag($0.id) }
                    }
                    .pickerStyle(.menu)
                    .tint(Theme.accent)
                    Spacer()
                    if loading { ProgressView().controlSize(.small) }
                }
                .padding(.vertical, 6)
                DoubleRule()
                ForEach(tables) { AgateTable(table: $0, favorites: parseFavorites(favoritesRaw)) }
                if failed { StatusLine(text: "Couldn't load standings. Pull down to retry.") }
                else if tables.isEmpty && !loading { StatusLine(text: "No standings available.") }
                StatusLine(text: league.id == "f1" ? "Via Jolpica (Ergast)" : "Via ESPN")
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
            if league.id == "f1" {
                let t = try await F1Client.tables()
                if Task.isCancelled { return }
                tables = t
            } else {
                let root = try await ESPNClient.standings(league)
                if Task.isCancelled { return }
                tables = StandingsBuilder.tables(root: root, league: league)
            }
        } catch {
            if Task.isCancelled { return }
            tables = []
            failed = true
        }
    }
}

enum StandingsBuilder {
    /// Column spec: header and the ESPN stat `type` it reads.
    private static func columns(for league: League) -> [(String, String)] {
        switch league.sport {
        case "hockey":
            return [("GP", "gamesplayed"), ("W", "wins"), ("L", "losses"), ("OTL", "otlosses"), ("PTS", "points")]
        case "soccer":
            return [("GP", "gamesplayed"), ("W", "wins"), ("D", "ties"), ("L", "losses"), ("GD", "pointdifferential"), ("PTS", "points")]
        case "baseball":
            return [("W-L", "total"), ("PCT", "winpercent"), ("GB", "gamesbehind")]
        default:
            if league.id == "nfl" {
                return [("W-L", "total"), ("DIV", "vsdiv"), ("CONF", "vsconf"), ("PF", "pointsfor"), ("PA", "pointsagainst"), ("STRK", "streak")]
            }
            if league.id.hasPrefix("cfb") || league.id.hasPrefix("cbb") {
                return [("REC", "total"), ("CONF", "vsconf"), ("STRK", "streak")]
            }
            return [("W-L", "total"), ("PCT", "winpercent"), ("STRK", "streak")]
        }
    }

    private static func stat(_ entry: StandingsEntry, _ type: String) -> String {
        entry.stats?.first { $0.type == type }?.displayValue ?? "—"
    }

    private static func sortKey(_ entry: StandingsEntry) -> Double? {
        for type in ["playoffseed", "rank"] {
            if let v = entry.stats?.first(where: { $0.type == type })?.displayValue, let d = Double(v), d > 0 { return d }
        }
        return nil
    }

    private static func flatten(_ node: StandingsNode, path: [String], lastOnly: Bool = false) -> [(String, [StandingsEntry])] {
        let here = path + [node.name].compactMap { $0 }
        var out: [(String, [StandingsEntry])] = []
        if let entries = node.standings?.entries, !entries.isEmpty {
            let title = lastOnly ? (here.last ?? "") : here.dropFirst().suffix(2).joined(separator: " · ")
            out.append((title.isEmpty ? (here.first ?? "Standings") : title, entries))
        }
        for child in node.children ?? [] { out += flatten(child, path: here, lastOnly: lastOnly) }
        return out
    }

    static func tables(root: StandingsNode, league: League) -> [TableData] {
        let cols = columns(for: league)
        return flatten(root, path: [], lastOnly: league.standingsQuery?.contains("level=3") == true).map { title, entries in
            var sorted = entries
            if sorted.allSatisfy({ sortKey($0) != nil }) {
                sorted.sort { (sortKey($0) ?? 0) < (sortKey($1) ?? 0) }
            }
            let rows = sorted.enumerated().map { i, e -> [String] in
                [String(i + 1), e.team?.label(for: league) ?? "?"] + cols.map { stat(e, $0.1) }
            }
            return TableData(caption: title, headers: ["", "TEAM"] + cols.map { $0.0 }, rows: rows)
        }
    }
}
