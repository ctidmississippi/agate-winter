import Foundation

/// Thin wrapper around ESPN's public (unofficial) site API.
enum ESPNClient {
    private static let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 20
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: c)
    }()

    private static let siteBase = "https://site.api.espn.com/apis/site/v2/sports"
    private static let v2Base = "https://site.api.espn.com/apis/v2/sports"

    static func get<T: Decodable>(_ url: URL, as type: T.Type) async throws -> T {
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    static func ymd(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d%02d%02d", c.year ?? 2026, c.month ?? 1, c.day ?? 1)
    }

    static func scoreboard(_ league: League, date: Date) async throws -> [ESPNEvent] {
        var s = "\(siteBase)/\(league.sport)/\(league.slug)/scoreboard?limit=400&dates=\(ymd(date))"
        if !league.query.isEmpty { s += "&\(league.query)" }
        guard let url = URL(string: s) else { throw URLError(.badURL) }
        let board = try await get(url, as: Scoreboard.self)
        return board.events ?? []
    }

    /// Events whose dates fall in a range (used for tournament weeks and fight cards).
    static func scoreboardRange(_ league: League, from: Date, to: Date) async throws -> [ESPNEvent] {
        var s = "\(siteBase)/\(league.sport)/\(league.slug)/scoreboard?limit=400&dates=\(ymd(from))-\(ymd(to))"
        if !league.query.isEmpty { s += "&\(league.query)" }
        guard let url = URL(string: s) else { throw URLError(.badURL) }
        return try await get(url, as: Scoreboard.self).events ?? []
    }

    /// Postseason games. ESPN only honors this while the league is in its postseason;
    /// otherwise it returns regular-season games, which `isPostseason` reports as false.
    static func postseason(_ league: League) async throws -> (events: [ESPNEvent], isPostseason: Bool) {
        var s = "\(siteBase)/\(league.sport)/\(league.slug)/scoreboard?seasontype=3&limit=300"
        if !league.query.isEmpty { s += "&\(league.query)" }
        guard let url = URL(string: s) else { throw URLError(.badURL) }
        let board = try await get(url, as: Scoreboard.self)
        let events = board.events ?? []
        let flagged = events.contains { e in
            let c = e.competitions?.first
            return c?.series?.type == "playoff" || (c?.notes?.first?.headline ?? "").contains("Round")
        }
        return (events, board.season?.type == 3 || flagged)
    }

    static func standings(_ league: League) async throws -> StandingsNode {
        var s = "\(v2Base)/\(league.sport)/\(league.slug)/standings"
        if let q = league.standingsQuery { s += "?\(q)" }
        guard let url = URL(string: s) else { throw URLError(.badURL) }
        return try await get(url, as: StandingsNode.self)
    }

    static func rankings(_ league: League) async throws -> [Poll] {
        let s = "\(siteBase)/\(league.sport)/\(league.slug)/rankings"
        guard let url = URL(string: s) else { throw URLError(.badURL) }
        return try await get(url, as: RankingsResponse.self).rankings ?? []
    }
}
