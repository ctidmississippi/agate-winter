import Foundation

// Lenient models for ESPN's public site API. Every field is optional because
// the feeds differ from sport to sport and change without notice.

// MARK: - Scoreboard

struct Scoreboard: Decodable {
    let events: [ESPNEvent]?
    let season: ScoreboardSeason?
}

struct ScoreboardSeason: Decodable {
    let type: Int?
    let year: Int?
}

struct PlayoffSeries: Decodable {
    let type: String?
    let summary: String?
    let completed: Bool?
}

struct ESPNEvent: Decodable, Identifiable {
    let id: String
    let date: String?
    let endDate: String?
    let name: String?
    let shortName: String?
    let status: ESPNStatus?
    let competitions: [Competition]?
    /// Tennis only: a tournament holds groupings (men's singles, doubles, ...).
    let groupings: [Grouping]?
}

struct Grouping: Decodable {
    let grouping: GroupingInfo?
    let competitions: [Competition]?
}

struct GroupingInfo: Decodable {
    let displayName: String?
}

struct ESPNStatus: Decodable {
    let type: StatusType?
    let period: Int?
}

struct StatusType: Decodable {
    let name: String?
    let state: String?          // "pre", "in", "post"
    let completed: Bool?
    let description: String?
    let detail: String?
    let shortDetail: String?
}

struct Competition: Decodable {
    let date: String?
    let status: ESPNStatus?
    let competitors: [Competitor]?
    let venue: Venue?
    let broadcasts: [Broadcast]?
    let notes: [Note]?
    let type: CompetitionType?
    let neutralSite: Bool?
    let round: Round?
    let odds: [OddsInfo]?
    let series: PlayoffSeries?
    let headlines: [CompHeadline]?
}

/// ESPN's short game recap, delivered inside the scoreboard response (no extra request).
struct CompHeadline: Decodable {
    let description: String?
    let shortLinkText: String?
}

struct OddsInfo: Decodable {
    let details: String?
    let overUnder: Double?
}

struct CompRecord: Decodable {
    let type: String?
    let summary: String?
}

struct Round: Decodable {
    let displayName: String?
}

struct CompetitionType: Decodable {
    let abbreviation: String?
}

struct Competitor: Decodable {
    let id: String?
    let homeAway: String?
    let winner: Bool?
    let order: Int?
    let score: FlexibleString?
    let team: Team?
    let athlete: Athlete?
    let curatedRank: CuratedRank?
    let linescores: [Linescore]?
    let records: [CompRecord]?
    /// Tennis doubles pairs.
    let roster: Roster?
}

struct Roster: Decodable {
    let displayName: String?
    let shortDisplayName: String?
}

struct Linescore: Decodable {
    let value: Double?
    let tiebreak: Double?
}

struct Team: Decodable {
    let id: String?
    let location: String?
    let name: String?
    let nickname: String?
    let abbreviation: String?
    let displayName: String?
    let shortDisplayName: String?
    let color: String?
    let alternateColor: String?
    let logo: String?
}

struct Athlete: Decodable {
    let fullName: String?
    let displayName: String?
    let shortName: String?
}

struct CuratedRank: Decodable {
    let current: Int?
}

struct Venue: Decodable {
    let fullName: String?
    let address: Address?
}

struct Address: Decodable {
    let city: String?
    let state: String?
}

struct Broadcast: Decodable {
    let names: [String]?
}

struct Note: Decodable {
    let headline: String?
}

/// Decodes a value that may arrive as a string, a number, or an object with a
/// `displayValue` (ESPN uses all three for scores).
struct FlexibleString: Decodable {
    let value: String

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) {
            value = s
        } else if let i = try? c.decode(Int.self) {
            value = String(i)
        } else if let d = try? c.decode(Double.self) {
            value = d.rounded() == d ? String(Int(d)) : String(d)
        } else if let o = try? c.decode(DisplayValueBox.self) {
            value = o.displayValue ?? ""
        } else {
            value = ""
        }
    }

    private struct DisplayValueBox: Decodable { let displayValue: String? }
}

// MARK: - Rankings

struct RankingsResponse: Decodable {
    let rankings: [Poll]?
}

struct Poll: Decodable, Identifiable {
    var id: String { (name ?? "") + (headline ?? "") }
    let name: String?
    let shortName: String?
    let headline: String?
    let ranks: [PollRank]?
}

struct PollRank: Decodable {
    let current: Int?
    let previous: Int?
    let points: Double?
    let firstPlaceVotes: Int?
    let recordSummary: String?
    let team: Team?
}

// MARK: - Standings

struct StandingsNode: Decodable {
    let name: String?
    let abbreviation: String?
    let children: [StandingsNode]?
    let standings: StandingsTable?
}

struct StandingsTable: Decodable {
    let entries: [StandingsEntry]?
}

struct StandingsEntry: Decodable {
    let team: Team?
    let stats: [StandingsStat]?
}

struct StandingsStat: Decodable {
    let name: String?
    let type: String?
    let abbreviation: String?
    let displayValue: String?
}
