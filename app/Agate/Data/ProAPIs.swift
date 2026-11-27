import Foundation

// Official / community feeds that are richer than ESPN for three leagues:
// NHL (api-web.nhle.com), MLB (statsapi.mlb.com) and Formula 1 (Jolpica, the Ergast successor).
// If any of them fails, the app falls back to ESPN (NHL, MLB) or simply omits the table (F1).

enum ProAPI {
    private static let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 20
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: c)
    }()

    static func get<T: Decodable>(_ urlString: String, as type: T.Type) async throws -> T {
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    static func isoDay(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 2026, c.month ?? 1, c.day ?? 1)
    }
}

// MARK: - NHL

struct NHLScore: Decodable { var games: [NHLGame]? }

struct NHLName: Decodable { var `default`: String? }

struct NHLTeam: Decodable {
    var name: NHLName?
    var abbrev: String?
    var score: Int?
}

struct NHLPeriod: Decodable {
    var number: Int?
    var periodType: String?
}

struct NHLClock: Decodable {
    var timeRemaining: String?
    var inIntermission: Bool?
}

struct NHLGoal: Decodable {
    var teamAbbrev: String?
    var name: NHLName?
    var goalsToDate: Int?
}

struct NHLGame: Decodable {
    var id: Int?
    var startTimeUTC: String?
    var gameState: String?
    var awayTeam: NHLTeam?
    var homeTeam: NHLTeam?
    var periodDescriptor: NHLPeriod?
    var clock: NHLClock?
    var goals: [NHLGoal]?
}

enum NHLClient {
    static func blocks(_ league: League, date: Date, extras: [String: GameExtras]) async throws -> [Block] {
        let feed = try await ProAPI.get("https://api-web.nhle.com/v1/score/\(ProAPI.isoDay(date))", as: NHLScore.self)
        var live: [Row] = [], done: [Row] = []
        var upcoming: [(Date, [Row])] = []

        for g in feed.games ?? [] {
            guard let away = g.awayTeam, let home = g.homeTeam else { continue }
            let an = away.name?.default ?? away.abbrev ?? "?"
            let hn = home.name?.default ?? home.abbrev ?? "?"
            let search = "\(an) \(hn)"
            let ex = extras[Extras.key(an, hn)]
            let al = Extras.label(an, ex), hl = Extras.label(hn, ex)
            let state = g.gameState ?? "FUT"
            let ptype = g.periodDescriptor?.periodType ?? "REG"
            let pnum = g.periodDescriptor?.number ?? 0

            switch state {
            case "FINAL", "OFF":
                var first = (al, away.score ?? 0), second = (hl, home.score ?? 0)
                if second.1 > first.1 { swap(&first, &second) }
                let suffix = ptype == "SO" ? "Final/SO" : (ptype == "OT" ? (pnum > 4 ? "Final/\(pnum - 3)OT" : "Final/OT") : "Final")
                done.append(Row(kind: .line, left: "\(first.0) \(first.1), \(second.0) \(second.1)", right: suffix, search: search,
                                game: GameRef(league: league, date: date, eventID: nil, names: [an, hn]),
                                start: Fmt.parse(g.startTimeUTC)))
                if let note = scorers(g) { done.append(Row(kind: .note, left: note)) }
            case "LIVE", "CRIT":
                let per = ptype == "OT" ? "OT" : (ptype == "SO" ? "SO" : "P\(pnum)")
                let time = (g.clock?.inIntermission ?? false) ? "Int." : (g.clock?.timeRemaining ?? "")
                live.append(Row(kind: .live, left: "\(al) \(away.score ?? 0), \(hl) \(home.score ?? 0)",
                                right: "\(per) \(time)".trimmingCharacters(in: .whitespaces), search: search,
                                game: GameRef(league: league, date: date, eventID: nil, names: [an, hn]),
                                start: Fmt.parse(g.startTimeUTC),
                                close: abs((away.score ?? 0) - (home.score ?? 0)) <= 1 && pnum >= 3))
                if let note = scorers(g) { live.append(Row(kind: .note, left: note)) }
            default:
                let d = Fmt.parse(g.startTimeUTC)
                var right = Fmt.time(d)
                if let net = ex?.network { right += " · \(net)" }
                var group = [Row(kind: .line, left: "\(al) at \(hl)", right: right, search: search, start: d)]
                upcoming.append((d ?? .distantFuture, group))
            }
        }

        var rows: [Row] = []
        if !live.isEmpty { rows.append(Row(kind: .sub, left: "In progress")); rows += live }
        if !done.isEmpty { rows.append(Row(kind: .sub, left: "Final")); rows += done }
        if !upcoming.isEmpty {
            rows.append(Row(kind: .sub, left: "Upcoming"))
            rows += upcoming.sorted { $0.0 < $1.0 }.flatMap { $0.1 }
        }
        guard !rows.isEmpty else { return [] }
        return [Block(id: league.id, title: league.title, rows: rows)]
    }

    /// "Goals: LAK — Kopitar, Byfield 2; TOR — Matthews"
    private static func scorers(_ g: NHLGame) -> String? {
        guard let goals = g.goals, !goals.isEmpty else { return nil }
        var order: [String] = []
        var byTeam: [String: [String]] = [:]
        for goal in goals {
            let team = goal.teamAbbrev ?? "?"
            // Shootout goals are credited by the final score, not the scorer list.
            let name = goal.name?.default ?? "?"
            if byTeam[team] == nil { order.append(team); byTeam[team] = [] }
            byTeam[team]?.append(name)
        }
        let parts = order.map { team -> String in
            var counts: [(String, Int)] = []
            for n in byTeam[team] ?? [] {
                if let i = counts.firstIndex(where: { $0.0 == n }) { counts[i].1 += 1 } else { counts.append((n, 1)) }
            }
            let names = counts.map { $0.1 > 1 ? "\($0.0) \($0.1)" : $0.0 }.joined(separator: ", ")
            return "\(team) — \(names)"
        }
        return "Goals: " + parts.joined(separator: "; ")
    }
}

// MARK: - MLB

struct MLBSchedule: Decodable { var dates: [MLBDate]? }
struct MLBDate: Decodable { var games: [MLBGame]? }

struct MLBStatus: Decodable {
    var abstractGameState: String?
    var detailedState: String?
}

struct MLBTeamRef: Decodable { var name: String? }
struct MLBSide: Decodable {
    var team: MLBTeamRef?
    var score: Int?
}
struct MLBTeams: Decodable { var away: MLBSide?; var home: MLBSide? }

struct MLBLinescore: Decodable {
    var currentInning: Int?
    var currentInningOrdinal: String?
    var inningState: String?
    var scheduledInnings: Int?
}

struct MLBPerson: Decodable { var fullName: String? }
struct MLBDecisions: Decodable {
    var winner: MLBPerson?
    var loser: MLBPerson?
    var save: MLBPerson?
}

struct MLBGame: Decodable {
    var gamePk: Int?
    var gameDate: String?
    var status: MLBStatus?
    var teams: MLBTeams?
    var linescore: MLBLinescore?
    var decisions: MLBDecisions?
}

enum MLBClient {
    private static func nickname(_ full: String?) -> String {
        guard let full else { return "?" }
        for two in ["Red Sox", "White Sox", "Blue Jays"] where full.hasSuffix(two) { return two }
        return full.split(separator: " ").last.map(String.init) ?? full
    }

    private static func surname(_ p: MLBPerson?) -> String {
        p?.fullName?.split(separator: " ").last.map(String.init) ?? "?"
    }

    static func blocks(_ league: League, date: Date, extras: [String: GameExtras]) async throws -> [Block] {
        let url = "https://statsapi.mlb.com/api/v1/schedule?sportId=1&date=\(ProAPI.isoDay(date))&hydrate=linescore,decisions"
        let feed = try await ProAPI.get(url, as: MLBSchedule.self)
        var live: [Row] = [], done: [Row] = []
        var upcoming: [(Date, [Row])] = []

        for g in (feed.dates ?? []).flatMap({ $0.games ?? [] }) {
            guard let away = g.teams?.away, let home = g.teams?.home else { continue }
            let an = nickname(away.team?.name), hn = nickname(home.team?.name)
            let search = "\(an) \(hn)"
            let ex = extras[Extras.key(an, hn)]
            let al = Extras.label(an, ex), hl = Extras.label(hn, ex)
            let state = g.status?.abstractGameState ?? "Preview"

            switch state {
            case "Final":
                var first = (al, away.score ?? 0), second = (hl, home.score ?? 0)
                if second.1 > first.1 { swap(&first, &second) }
                var right = "Final"
                if let n = g.linescore?.currentInning, n != (g.linescore?.scheduledInnings ?? 9) { right = "F/\(n)" }
                done.append(Row(kind: .line, left: "\(first.0) \(first.1), \(second.0) \(second.1)", right: right, search: search,
                                game: GameRef(league: league, date: date, eventID: nil, names: [an, hn]),
                                start: Fmt.parse(g.gameDate)))
                if let d = g.decisions {
                    var parts: [String] = []
                    if d.winner != nil { parts.append("W: \(surname(d.winner))") }
                    if d.loser != nil { parts.append("L: \(surname(d.loser))") }
                    if d.save != nil { parts.append("S: \(surname(d.save))") }
                    if !parts.isEmpty { done.append(Row(kind: .note, left: parts.joined(separator: " · "))) }
                }
            case "Live":
                let inning = g.linescore?.currentInningOrdinal ?? ""
                let half = g.linescore?.inningState ?? ""
                live.append(Row(kind: .live, left: "\(al) \(away.score ?? 0), \(hl) \(home.score ?? 0)",
                                right: "\(half) \(inning)".trimmingCharacters(in: .whitespaces), search: search,
                                game: GameRef(league: league, date: date, eventID: nil, names: [an, hn]),
                                start: Fmt.parse(g.gameDate),
                                close: abs((away.score ?? 0) - (home.score ?? 0)) <= 1 && (g.linescore?.currentInning ?? 0) >= 7))
            default:
                let d = Fmt.parse(g.gameDate)
                var right = Fmt.time(d)
                if let ds = g.status?.detailedState, ds != "Scheduled", ds != "Pre-Game", ds != "Warmup" { right = ds }
                if let net = ex?.network { right += " · \(net)" }
                var group = [Row(kind: .line, left: "\(al) at \(hl)", right: right, search: search, start: d)]
                upcoming.append((d ?? .distantFuture, group))
            }
        }

        var rows: [Row] = []
        if !live.isEmpty { rows.append(Row(kind: .sub, left: "In progress")); rows += live }
        if !done.isEmpty { rows.append(Row(kind: .sub, left: "Final")); rows += done }
        if !upcoming.isEmpty {
            rows.append(Row(kind: .sub, left: "Upcoming"))
            rows += upcoming.sorted { $0.0 < $1.0 }.flatMap { $0.1 }
        }
        guard !rows.isEmpty else { return [] }
        return [Block(id: league.id, title: league.title, rows: rows)]
    }
}

// MARK: - Formula 1 (Jolpica)

struct F1Response: Decodable { var MRData: F1Data? }
struct F1Data: Decodable {
    var StandingsTable: F1StandingsTable?
    var RaceTable: F1RaceTable?
}
struct F1StandingsTable: Decodable { var StandingsLists: [F1StandingsList]? }
struct F1StandingsList: Decodable {
    var DriverStandings: [F1DriverStanding]?
    var ConstructorStandings: [F1ConstructorStanding]?
}
struct F1Driver: Decodable { var code: String?; var givenName: String?; var familyName: String? }
struct F1Constructor: Decodable { var name: String? }
struct F1DriverStanding: Decodable {
    var position: String?
    var points: String?
    var wins: String?
    var Driver: F1Driver?
    var Constructors: [F1Constructor]?
}
struct F1ConstructorStanding: Decodable {
    var position: String?
    var points: String?
    var wins: String?
    var Constructor: F1Constructor?
}
struct F1RaceTable: Decodable { var Races: [F1Race]? }
struct F1Race: Decodable {
    var raceName: String?
    var Results: [F1Result]?
}
struct F1Time: Decodable { var time: String? }
struct F1Result: Decodable {
    var position: String?
    var grid: String?
    var points: String?
    var status: String?
    var Driver: F1Driver?
    var Constructor: F1Constructor?
    var Time: F1Time?
}

enum F1Client {
    private static let base = "https://api.jolpi.ca/ergast/f1/current"

    static func tables() async throws -> [TableData] {
        async let drivers = ProAPI.get("\(base)/driverstandings.json", as: F1Response.self)
        async let teams = ProAPI.get("\(base)/constructorstandings.json", as: F1Response.self)
        let d = try await drivers
        let c = try await teams
        var out: [TableData] = []

        if let list = d.MRData?.StandingsTable?.StandingsLists?.first?.DriverStandings {
            let rows = list.map { s -> [String] in
                let name = s.Driver?.familyName ?? "?"
                return [s.position ?? "", name, s.Constructors?.first?.name ?? "", s.wins ?? "0", s.points ?? "0"]
            }
            out.append(TableData(caption: "Drivers' Championship", headers: ["", "DRIVER", "TEAM", "W", "PTS"], rows: rows))
        }
        if let list = c.MRData?.StandingsTable?.StandingsLists?.first?.ConstructorStandings {
            let rows = list.map { s -> [String] in
                [s.position ?? "", s.Constructor?.name ?? "?", s.wins ?? "0", s.points ?? "0"]
            }
            out.append(TableData(caption: "Constructors' Championship", headers: ["", "TEAM", "W", "PTS"], rows: rows))
        }
        // Last race is optional: a failure here must not hide the championships.
        if let last = try? await ProAPI.get("\(base)/last/results.json", as: F1Response.self),
           let race = last.MRData?.RaceTable?.Races?.first, let results = race.Results {
            let rows = results.map { r -> [String] in
                let name = r.Driver?.familyName ?? "?"
                let finish = r.Time?.time ?? r.status ?? ""
                return [r.position ?? "", name, r.Constructor?.name ?? "", finish, r.points ?? "0"]
            }
            out.append(TableData(caption: "Last race · \(race.raceName ?? "")",
                                 headers: ["", "DRIVER", "TEAM", "TIME", "PTS"], rows: rows))
        }
        return out
    }
}
