import Foundation

// MARK: - Reference to a game (what a tappable row carries)

struct GameRef: Identifiable {
    let id = UUID()
    var league: League
    var date: Date
    /// ESPN event id when known (ESPN-sourced rows). NHL/MLB rows carry team names instead.
    var eventID: String?
    var names: [String] = []
    /// ESPN's short recap, carried from the scoreboard so the box score can show it.
    var recap: String? = nil
}

// MARK: - ESPN "summary" feed (lenient: everything optional)

struct SummaryTeam: Decodable {
    let id: String?
    let displayName: String?
    let shortDisplayName: String?
    let abbreviation: String?
    let location: String?
    let name: String?
}

struct SummaryLine: Decodable { let displayValue: String? }

struct SummaryCompetitor: Decodable {
    let homeAway: String?
    let winner: Bool?
    let score: FlexibleString?
    let team: SummaryTeam?
    let linescores: [SummaryLine]?
}

struct SummaryStatusType: Decodable { let detail: String?; let shortDetail: String? }
struct SummaryStatus: Decodable { let type: SummaryStatusType? }

struct SummaryCompetition: Decodable {
    let competitors: [SummaryCompetitor]?
    let status: SummaryStatus?
}

struct SummaryHeader: Decodable { let competitions: [SummaryCompetition]? }

struct SummaryStat: Decodable { let label: String?; let displayValue: String? }
struct SummaryBoxTeam: Decodable {
    let team: SummaryTeam?
    let homeAway: String?
    let statistics: [SummaryStat]?
}
struct SummaryPlayerRow: Decodable {
    let athlete: SummaryAthlete?
    let stats: [String]?
}
struct SummaryStatGroup: Decodable {
    let name: String?
    let labels: [String]?
    let athletes: [SummaryPlayerRow]?
    let totals: [String]?
}
struct SummaryTeamPlayers: Decodable {
    let team: SummaryTeam?
    let statistics: [SummaryStatGroup]?
}
struct SummaryBox: Decodable {
    let teams: [SummaryBoxTeam]?
    let players: [SummaryTeamPlayers]?
}

struct SummaryPeriod: Decodable { let displayValue: String?; let number: Int? }
struct SummaryClock: Decodable { let displayValue: String? }
struct SummaryPlay: Decodable {
    let text: String?
    let awayScore: FlexibleString?
    let homeScore: FlexibleString?
    let period: SummaryPeriod?
    let clock: SummaryClock?
    let scoringPlay: Bool?
}

struct SummaryAthlete: Decodable { let displayName: String?; let shortName: String? }
struct SummaryLeader: Decodable { let displayValue: String?; let athlete: SummaryAthlete? }
struct SummaryLeaderCat: Decodable { let displayName: String?; let leaders: [SummaryLeader]? }
struct SummaryTeamLeaders: Decodable {
    let team: SummaryTeam?
    let leaders: [SummaryLeaderCat]?
}

struct SummaryArticle: Decodable { let headline: String?; let description: String? }

struct SummaryDrive: Decodable { let plays: [SummaryPlay]? }
struct SummaryDrives: Decodable {
    let previous: [SummaryDrive]?
    let current: SummaryDrive?
}

struct GameSummary: Decodable {
    let drives: SummaryDrives?
    let header: SummaryHeader?
    let boxscore: SummaryBox?
    let scoringPlays: [SummaryPlay]?
    let plays: [SummaryPlay]?
    let leaders: [SummaryTeamLeaders]?
    let article: SummaryArticle?
}

extension ESPNClient {
    static func teamSchedule(sport: String, slug: String, teamID: String) async throws -> [ESPNEvent] {
        let s = "https://site.api.espn.com/apis/site/v2/sports/\(sport)/\(slug)/teams/\(teamID)/schedule"
        guard let url = URL(string: s) else { throw URLError(.badURL) }
        return try await get(url, as: Scoreboard.self).events ?? []
    }

    static func summary(sport: String, slug: String, eventID: String) async throws -> GameSummary {
        let s = "https://site.api.espn.com/apis/site/v2/sports/\(sport)/\(slug)/summary?event=\(eventID)"
        guard let url = URL(string: s) else { throw URLError(.badURL) }
        return try await get(url, as: GameSummary.self)
    }
}

// MARK: - Summary -> display

struct TeamLink: Identifiable {
    var id: String
    var name: String
    var abbr: String
}

struct PlayerTable: Identifiable {
    let id = UUID()
    var caption: String
    var headers: [String]
    var rows: [[String]]      // first cell is the player name
    var totals: [String]?
}

struct GameDetailContent {
    var title: String
    var status: String
    var lineScore: TableData?
    var teamStats: TableData?
    var sections: [Block]
    var teams: [TeamLink] = []
    var players: [PlayerTable] = []
    /// Every play, newest first.
    var playByPlay: [Row] = []
}

enum GameDetailBuilder {
    private static func regulation(_ league: League) -> Int {
        switch league.sport {
        case "hockey": return 3
        case "baseball": return 9
        case "football": return 4
        case "basketball": return league.id.hasPrefix("cbb") ? 2 : 4
        default: return 4
        }
    }

    static func build(_ sum: GameSummary, league: League) -> GameDetailContent? {
        guard let comp = sum.header?.competitions?.first,
              let comps = comp.competitors, comps.count >= 2 else { return nil }
        let away = comps.first { $0.homeAway == "away" } ?? comps[0]
        let home = comps.first { $0.homeAway == "home" } ?? comps[1]
        func abbr(_ c: SummaryCompetitor) -> String { c.team?.abbreviation ?? c.team?.shortDisplayName ?? "?" }
        func full(_ c: SummaryCompetitor) -> String { c.team?.displayName ?? abbr(c) }
        func score(_ c: SummaryCompetitor) -> String { c.score?.value ?? "" }

        let title = "\(full(away)) \(score(away)), \(full(home)) \(score(home))"
        let status = comp.status?.type?.detail ?? comp.status?.type?.shortDetail ?? ""

        // Line score
        var lineScore: TableData?
        let n = max(away.linescores?.count ?? 0, home.linescores?.count ?? 0)
        if n > 0 {
            let reg = regulation(league)
            var headers = ["", "TEAM"]
            for i in 1...n {
                if i <= reg { headers.append("\(i)") } else { headers.append(i - reg > 1 ? "OT\(i - reg)" : "OT") }
            }
            headers.append("T")
            func row(_ c: SummaryCompetitor) -> [String] {
                var cells = ["", abbr(c)]
                for i in 0..<n {
                    cells.append(i < (c.linescores?.count ?? 0) ? (c.linescores?[i].displayValue ?? "-") : "-")
                }
                cells.append(score(c))
                return cells
            }
            lineScore = TableData(caption: "Line score", headers: headers, rows: [row(away), row(home)])
        }

        // Team stats side by side
        var teamStats: TableData?
        if let teams = sum.boxscore?.teams, teams.count >= 2 {
            let a = teams.first { $0.homeAway == "away" } ?? teams[0]
            let h = teams.first { $0.homeAway == "home" } ?? teams[1]
            let hStats = h.statistics ?? []
            let rows = (a.statistics ?? []).prefix(16).compactMap { stat -> [String]? in
                guard let label = stat.label else { return nil }
                let other = hStats.first { $0.label == label }?.displayValue ?? "-"
                return ["", label, stat.displayValue ?? "-", other]
            }
            if !rows.isEmpty {
                teamStats = TableData(caption: "Team stats",
                                      headers: ["", "STAT", a.team?.abbreviation ?? "AWAY", h.team?.abbreviation ?? "HOME"],
                                      rows: rows)
            }
        }

        var sections: [Block] = []

        // Scoring plays (skipped when there are too many, e.g. basketball)
        let plays = (sum.scoringPlays ?? []).isEmpty
            ? (sum.plays ?? []).filter { $0.scoringPlay == true }
            : (sum.scoringPlays ?? [])
        if !plays.isEmpty && plays.count <= 40 {
            let rows = plays.map { p -> Row in
                let per = p.period?.displayValue ?? (p.period?.number).map { "P\($0)" } ?? ""
                let clock = p.clock?.displayValue ?? ""
                let prefix = [per, clock].filter { !$0.isEmpty }.joined(separator: " ")
                let text = (p.text ?? "").trimmingCharacters(in: .whitespaces)
                let left = prefix.isEmpty ? text : "\(prefix) — \(text)"
                let right = "\(p.awayScore?.value ?? "")–\(p.homeScore?.value ?? "")"
                return Row(kind: .line, left: left, right: right)
            }
            sections.append(Block(id: "scoring", title: "Scoring", rows: rows))
        }

        // Leaders
        for tl in sum.leaders ?? [] {
            let rows = (tl.leaders ?? []).compactMap { cat -> Row? in
                guard let top = cat.leaders?.first, let name = top.athlete?.displayName ?? top.athlete?.shortName else { return nil }
                return Row(kind: .line, left: "\(cat.displayName ?? ""): \(name)", right: top.displayValue ?? "")
            }
            if !rows.isEmpty {
                sections.append(Block(id: "leaders-\(tl.team?.abbreviation ?? "")",
                                      title: "Leaders · \(tl.team?.displayName ?? tl.team?.abbreviation ?? "")",
                                      rows: rows))
            }
        }

        // Recap headline
        if let a = sum.article, let h = a.headline, !h.isEmpty {
            var rows = [Row(kind: .line, left: h)]
            if let d = a.description, !d.isEmpty { rows.append(Row(kind: .note, left: d)) }
            sections.append(Block(id: "recap", title: "Recap", rows: rows))
        }

        var teams: [TeamLink] = []
        for c in [away, home] {
            if let id = c.team?.id { teams.append(TeamLink(id: id, name: full(c), abbr: abbr(c))) }
        }

        // Full player box score
        var players: [PlayerTable] = []
        for tp in sum.boxscore?.players ?? [] {
            let teamAbbr = tp.team?.abbreviation ?? tp.team?.displayName ?? ""
            for (i, g) in (tp.statistics ?? []).enumerated() {
                guard let labels = g.labels, let athletes = g.athletes, !athletes.isEmpty else { continue }
                var group = (g.name ?? "").capitalized
                if group.isEmpty { group = league.sport == "baseball" ? (i == 0 ? "Batting" : "Pitching") : "Players" }
                let rows = athletes.map { a -> [String] in
                    [a.athlete?.shortName ?? a.athlete?.displayName ?? "?"] + (a.stats ?? [])
                }
                players.append(PlayerTable(caption: "\(teamAbbr) · \(group)", headers: labels, rows: rows, totals: g.totals))
            }
        }

        // Play by play (football keeps its plays inside drives)
        var allPlays = sum.plays ?? []
        if allPlays.isEmpty {
            allPlays = (sum.drives?.previous ?? []).flatMap { $0.plays ?? [] } + (sum.drives?.current?.plays ?? [])
        }
        let pbp = allPlays.reversed().compactMap { p -> Row? in
            let text = (p.text ?? "").trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { return nil }
            let per = p.period?.displayValue ?? (p.period?.number).map { "P\($0)" } ?? ""
            let clock = p.clock?.displayValue ?? ""
            let prefix = [per, clock].filter { !$0.isEmpty }.joined(separator: " ")
            var score = ""
            if let a = p.awayScore?.value, let h = p.homeScore?.value { score = "\(a)–\(h)" }
            return Row(kind: p.scoringPlay == true ? .live : .line,
                       left: prefix.isEmpty ? text : "\(prefix) — \(text)", right: score)
        }

        return GameDetailContent(title: title, status: status, lineScore: lineScore,
                                 teamStats: teamStats, sections: sections, teams: teams, players: players,
                                 playByPlay: pbp)
    }
}
