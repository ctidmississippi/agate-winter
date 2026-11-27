import SwiftUI

// MARK: - Live power indexes from ESPN

private struct PowerIndex: Decodable {
    struct Ref: Decodable { let ref: String; enum CodingKeys: String, CodingKey { case ref = "$ref" } }
    struct Stat: Decodable { let name: String; let displayValue: String? }
    struct Item: Decodable {
        let team: Ref
        let predictives: [Stat]?
        let stats: [Stat]?
        var all: [String: String] {
            var d: [String: String] = [:]
            for s in (predictives ?? []) + (stats ?? []) { d[s.name] = s.displayValue ?? "" }
            return d
        }
        var teamID: String {
            guard let r = team.ref.range(of: "/teams/") else { return "" }
            return String(team.ref[r.upperBound...].prefix { $0.isNumber })
        }
    }
    let items: [Item]
}

private struct TeamList: Decodable {
    struct T: Decodable { let id: String; let shortDisplayName: String?; let displayName: String? }
    struct W: Decodable { let team: T }
    struct L: Decodable { let teams: [W] }
    struct S: Decodable { let leagues: [L] }
    let sports: [S]
}

@MainActor
final class RatingsStore: ObservableObject {
    @Published var tables: [TableData] = []
    @Published var loading = false
    @Published var failed = false
    private var loaded = false

    func load(force: Bool = false) async {
        if loaded && !force { return }
        loading = true
        defer { loading = false }
        async let fpi = build(sport: "football", slug: "college-football", season: Self.footballSeason(),
                              caption: "College football · FPI (ESPN)",
                              headers: ["#", "TEAM", "FPI", "PROJ W", "CONF %", "CFP %"],
                              cells: { d in [d["fpirank"].map(Self.num) ?? "", d["fpi"] ?? "", d["projectedw"].map { $0 } ?? "",
                                             d["probwinconf"] ?? "", d["probmakeplayoffs"] ?? ""] })
        async let bpi = build(sport: "basketball", slug: "mens-college-basketball", season: Self.basketballSeason(),
                              caption: "Men's basketball · BPI (ESPN)",
                              headers: ["#", "TEAM", "BPI", "OFF", "DEF", "REC"],
                              cells: { d in [d["bpirank"].map(Self.num) ?? "", d["bpi"] ?? "", d["bpioffense"] ?? "", d["bpidefense"] ?? "",
                                             "\(d["wins"] ?? "0")-\(d["losses"] ?? "0")"] })
        let result = await [fpi, bpi].compactMap { $0 }
        tables = result
        failed = result.isEmpty
        loaded = !result.isEmpty
    }

    private static func num(_ s: String) -> String { s.filter(\.isNumber) }

    private static func footballSeason() -> Int {
        let c = Calendar.current.dateComponents([.year, .month], from: Date())
        return (c.month ?? 1) <= 2 ? (c.year ?? 2026) - 1 : (c.year ?? 2026)
    }
    private static func basketballSeason() -> Int {
        let c = Calendar.current.dateComponents([.year, .month], from: Date())
        return (c.month ?? 1) >= 10 ? (c.year ?? 2026) + 1 : (c.year ?? 2026)
    }

    private func build(sport: String, slug: String, season: Int, caption: String, headers: [String],
                       cells: @escaping ([String: String]) -> [String]) async -> TableData? {
        guard let pu = URL(string: "https://sports.core.api.espn.com/v2/sports/\(sport)/leagues/\(slug)/seasons/\(season)/powerindex?limit=200"),
              let tu = URL(string: "https://site.api.espn.com/apis/site/v2/sports/\(sport)/\(slug)/teams?limit=500"),
              let index = try? await ESPNClient.get(pu, as: PowerIndex.self),
              let list = try? await ESPNClient.get(tu, as: TeamList.self)
        else { return nil }
        var names: [String: String] = [:]
        for t in list.sports.first?.leagues.first?.teams ?? [] {
            names[t.team.id] = t.team.shortDisplayName ?? t.team.displayName ?? t.team.id
        }
        let rows: [(Int, [String])] = index.items.compactMap { item in
            let d = item.all
            let c = cells(d)
            guard let rank = Int(c.first ?? "") else { return nil }
            return (rank, [c[0], names[item.teamID] ?? item.teamID] + Array(c.dropFirst()))
        }
        let top = rows.sorted { $0.0 < $1.0 }.prefix(50).map { $0.1 }
        guard !top.isEmpty else { return nil }
        return TableData(caption: caption, headers: headers, rows: Array(top))
    }
}

// MARK: - Page

struct RatingsView: View {
    @Environment(\.textScale) private var s
    @StateObject private var store = RatingsStore()
    @StateObject private var hand = WinterStore()
    @AppStorage("winterURL") private var winterURL = ""

    private var ratingsURL: String {
        let t = winterURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "" : t.replacingOccurrences(of: "winter.json", with: "ratings.json")
    }

    var body: some View {
        PageScroll {
            Masthead(title: "Ratings", motto: "“Efficiency, not opinion.”")
            DoubleRule()
            StatusLine(text: "ESPN's FPI and BPI update daily. Torvik is compiled by hand and refreshed when you ask. KenPom and SP+ are paywalled, so FPI and BPI stand in for them.")
            if store.failed {
                StatusLine(text: "Couldn't load the power indexes. Pull down to try again.")
            }
            ForEach(store.tables) { AgateTable(table: $0, favorites: []) }
            if store.loading && store.tables.isEmpty { ProgressView().frame(maxWidth: .infinity).padding() }
            ForEach(hand.sections) { group in
                SportHeader(title: group.title)
                if !group.checked.isEmpty || !group.source.isEmpty {
                    Text("Checked \(group.checked) · Source: \(group.source)")
                        .font(.sans(10 * s))
                        .foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach(group.blocks) { BlockView(block: $0, favorites: []) }
            }
        }
        .refreshable {
            await store.load(force: true)
            await hand.load(urlString: ratingsURL, resource: "ratings")
        }
        .task {
            await store.load()
            await hand.load(urlString: ratingsURL, resource: "ratings")
        }
    }
}
