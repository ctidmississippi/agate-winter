import Foundation

enum LeagueKind { case team, golf, racing, fighting, tennis }

/// Where the scoreboard comes from. NHL and MLB fall back to ESPN if their own feed fails.
enum ScoreSource { case espn, nhl, mlb }

struct League: Identifiable, Hashable {
    let id: String
    let group: String
    let title: String
    let sport: String
    let slug: String
    var query: String = ""
    var kind: LeagueKind = .team
    var standingsQuery: String? = nil
    var hasStandings = false
    var hasRankings = false
    /// Use the school/city ("Florida", "Carolina") instead of the nickname.
    var useLocation = true
    /// Pro US leagues where "LA" / "New York" are ambiguous.
    var isProUS = false
    var scoreSource: ScoreSource = .espn
}

enum Catalog {
    static let all: [League] = [
        League(id: "cfb-fbs", group: "College Football", title: "FBS", sport: "football", slug: "college-football",
               query: "groups=80", standingsQuery: "group=80", hasStandings: true, hasRankings: true),
        League(id: "cfb-fcs", group: "College Football", title: "FCS", sport: "football", slug: "college-football",
               query: "groups=81"),
        League(id: "nfl", group: "NFL", title: "NFL", sport: "football", slug: "nfl",
               standingsQuery: "level=3", hasStandings: true, isProUS: true),
        League(id: "cbb-m", group: "College Basketball", title: "Men's Basketball", sport: "basketball",
               slug: "mens-college-basketball", query: "groups=50", hasStandings: true, hasRankings: true),
        League(id: "cbb-w", group: "College Basketball", title: "Women's Basketball", sport: "basketball",
               slug: "womens-college-basketball", query: "groups=50", hasStandings: true, hasRankings: true),
        League(id: "nba", group: "Pro Basketball", title: "NBA", sport: "basketball", slug: "nba",
               hasStandings: true, isProUS: true),
        League(id: "wnba", group: "Pro Basketball", title: "WNBA", sport: "basketball", slug: "wnba",
               hasStandings: true, isProUS: true),
        League(id: "nhl", group: "Hockey", title: "NHL", sport: "hockey", slug: "nhl",
               hasStandings: true, isProUS: true, scoreSource: .nhl),
        League(id: "chockey-m", group: "Hockey", title: "College Men's Hockey", sport: "hockey",
               slug: "mens-college-hockey", hasRankings: true),
        League(id: "chockey-w", group: "Hockey", title: "College Women's Hockey", sport: "hockey",
               slug: "womens-college-hockey"),
        League(id: "mlb", group: "Baseball", title: "MLB", sport: "baseball", slug: "mlb",
               hasStandings: true, isProUS: true, scoreSource: .mlb),
        League(id: "cbase", group: "Baseball", title: "College Baseball", sport: "baseball", slug: "college-baseball"),
        League(id: "cvb-w", group: "Other College Sports", title: "Women's Volleyball", sport: "volleyball",
               slug: "womens-college-volleyball", hasRankings: true),
        League(id: "cfh-w", group: "Other College Sports", title: "Field Hockey", sport: "field-hockey",
               slug: "womens-college-field-hockey"),
        League(id: "csoc-m", group: "Other College Sports", title: "Men's Soccer", sport: "soccer",
               slug: "usa.ncaa.m.1"),
        League(id: "csoc-w", group: "Other College Sports", title: "Women's Soccer", sport: "soccer",
               slug: "usa.ncaa.w.1"),
        League(id: "mls", group: "Soccer", title: "MLS", sport: "soccer", slug: "usa.1",
               hasStandings: true, useLocation: false),
        League(id: "epl", group: "Soccer", title: "Premier League", sport: "soccer", slug: "eng.1",
               hasStandings: true, useLocation: false),
        League(id: "liga", group: "Soccer", title: "La Liga", sport: "soccer", slug: "esp.1",
               hasStandings: true, useLocation: false),
        League(id: "seriea", group: "Soccer", title: "Serie A", sport: "soccer", slug: "ita.1",
               hasStandings: true, useLocation: false),
        League(id: "bundes", group: "Soccer", title: "Bundesliga", sport: "soccer", slug: "ger.1",
               hasStandings: true, useLocation: false),
        League(id: "ligue1", group: "Soccer", title: "Ligue 1", sport: "soccer", slug: "fra.1",
               hasStandings: true, useLocation: false),
        League(id: "ucl", group: "Soccer", title: "Champions League", sport: "soccer", slug: "uefa.champions",
               hasStandings: true, useLocation: false),
        League(id: "pga", group: "Golf, Racing, Tennis, Fighting", title: "PGA Tour", sport: "golf", slug: "pga", kind: .golf),
        League(id: "lpga", group: "Golf, Racing, Tennis, Fighting", title: "LPGA", sport: "golf", slug: "lpga", kind: .golf),
        League(id: "f1", group: "Golf, Racing, Tennis, Fighting", title: "Formula 1", sport: "racing", slug: "f1", kind: .racing,
               hasStandings: true),
        League(id: "nascar", group: "Golf, Racing, Tennis, Fighting", title: "NASCAR Cup", sport: "racing",
               slug: "nascar-premier", kind: .racing),
        League(id: "atp", group: "Golf, Racing, Tennis, Fighting", title: "ATP Tennis", sport: "tennis", slug: "atp", kind: .tennis),
        League(id: "wta", group: "Golf, Racing, Tennis, Fighting", title: "WTA Tennis", sport: "tennis", slug: "wta", kind: .tennis),
        League(id: "ufc", group: "Golf, Racing, Tennis, Fighting", title: "UFC", sport: "mma", slug: "ufc", kind: .fighting),
    ]

    static var withStandings: [League] { all.filter { $0.hasStandings } }
    static var withRankings: [League] { all.filter { $0.hasRankings } }
}

/// Which leagues the user has switched off in Settings (comma-separated ids).
enum DisabledLeagues {
    static func set(from raw: String) -> Set<String> {
        Set(raw.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) })
    }
    static func raw(from set: Set<String>) -> String { set.sorted().joined(separator: ",") }
}

extension String {
    /// Short league tag for crowded lists like "Close games right now".
    var leagueTag: String {
        switch self {
        case "Men's Basketball": return "MBB"
        case "Women's Basketball": return "WBB"
        case "College Men's Hockey": return "M Hockey"
        case "College Women's Hockey": return "W Hockey"
        case "College Baseball": return "CBSB"
        case "Women's Volleyball": return "WVB"
        case "Field Hockey": return "FH"
        case "Men's Soccer": return "Soccer"
        case "Women's Soccer": return "WoSo"
        case "Premier League": return "EPL"
        case "Champions League": return "UCL"
        case "Formula 1": return "F1"
        case "NASCAR Cup": return "NASCAR"
        case "ATP Tennis": return "ATP"
        case "WTA Tennis": return "WTA"
        case "PGA Tour": return "PGA"
        default: return self
        }
    }
}
