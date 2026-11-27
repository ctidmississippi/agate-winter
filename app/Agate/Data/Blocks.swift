import Foundation

// MARK: - Display model (what the agate views draw)

struct Row: Identifiable {
    enum Kind { case line, live, sub, note }
    let id = UUID()
    var kind: Kind
    var left: String
    var right: String = ""
    /// Text used to match against the favorites list.
    var search: String = ""
    /// When set, tapping the row opens the box score.
    var game: GameRef? = nil
    /// Scheduled start, used by the "By time" slate.
    var start: Date? = nil
    /// Live and tight late in the game.
    var close = false
    /// Team colors and logos in the order the teams appear in the row.
    var art: [TeamArt] = []
    /// Headline candidate for the front page (finals only).
    var story: Story? = nil
    /// A finished result in a feed that has no box score (golf, racing, tennis, fights).
    var isFinal = false
    /// Two stacked lines (name and score) for team games; empty for everything else.
    var sides: [Side] = []
}

struct Side {
    var name: String
    var score: String
    var won = false
}

struct Story {
    var kind: String        // upset, overtime, close, rout, plain
    var weight: Int
    var headline: String
    var league: String
    /// ESPN's recap paragraph for the game, when the scoreboard includes one.
    var recap: String? = nil
}

struct TeamArt {
    var color: String?
    var logo: String?
}

struct Block: Identifiable {
    let id: String
    var title: String
    var rows: [Row]
    /// Key used for the per-sport accent color.
    var sport: String = ""
    /// Which league produced this block (lets live refreshes reload only that league).
    var leagueID: String = ""
}

struct GroupSection: Identifiable {
    var id: String { title }
    var title: String
    var blocks: [Block]
    var checked: String = ""   // e.g. "Nov. 24, 2026"
    var source: String = ""    // e.g. "FIG calendar" or "Hand-compiled"
}

// MARK: - Feed -> Blocks

enum BlockBuilder {
    static func blocks(for league: League, events: [ESPNEvent], day: Date) -> [Block] {
        let key: String
        switch league.kind {
        case .team: key = league.sport
        case .golf: key = "golf"
        case .racing: key = "racing"
        case .fighting: key = "fighting"
        case .tennis: key = "tennis"
        }
        return rawBlocks(for: league, events: events, day: day).map { b in
            var b = b
            b.sport = key
            return b
        }
    }

    private static func rawBlocks(for league: League, events: [ESPNEvent], day: Date) -> [Block] {
        switch league.kind {
        case .team: return teamBlocks(league, events, day: day)
        case .golf: return golfBlocks(league, events)
        case .racing: return racingBlocks(league, events)
        case .fighting: return fightBlocks(league, events)
        case .tennis: return tennisBlocks(league, events, day: day)
        }
    }

    // MARK: Team sports

    private static func score(_ c: Competitor) -> String { c.score?.value ?? "" }

    static func isClose(_ league: League, _ a: Int, _ b: Int, period: Int?) -> Bool {
        let diff = abs(a - b), p = period ?? 0
        switch league.sport {
        case "basketball": return diff <= 5 && p >= (league.id.hasPrefix("cbb") ? 2 : 4)
        case "football": return diff <= 8 && p >= 4
        case "hockey": return diff <= 1 && p >= 3
        case "baseball": return diff <= 1 && p >= 7
        case "soccer": return diff <= 1 && p >= 2
        default: return false
        }
    }

    private static func art(_ c: Competitor) -> TeamArt {
        TeamArt(color: c.team?.color, logo: c.team?.logo)
    }

    /// A front-page headline for a finished game, with a rough news weight.
    private static func story(_ league: League, _ w: Competitor, _ l: Competitor, status: ESPNStatus?) -> Story? {
        guard let ws = Int(score(w)), let ls = Int(score(l)) else { return nil }
        let wn = w.team?.label(for: league) ?? "?", ln = l.team?.label(for: league) ?? "?"
        let margin = abs(ws - ls)
        let line = "\(ws)–\(ls)"
        let lr = l.curatedRank?.current ?? 0, wr = w.curatedRank?.current ?? 0
        let lrank = (lr > 0 && lr <= 25) ? lr : 0
        let wrank = (wr > 0 && wr <= 25) ? wr : 99
        let base: Int
        switch league.id {
        case "nfl": base = 20
        case "nba": base = 18
        case "cfb-fbs": base = 17
        case "nhl", "mlb": base = 15
        case "cbb-m": base = 14
        default: base = 8
        }
        let detail = status?.type?.shortDetail ?? ""
        if lrank > 0 && wrank > lrank + 4 {
            return Story(kind: "upset", weight: 100 + (26 - lrank) + base,
                         headline: "Upset: \(wn) topples No. \(lrank) \(ln), \(line)", league: league.title)
        }
        if detail.contains("OT") {
            return Story(kind: "overtime", weight: 60 + base,
                         headline: "\(wn) outlasts \(ln) in overtime, \(line)", league: league.title)
        }
        let tight: Bool
        switch league.sport {
        case "football": tight = margin <= 3
        case "basketball": tight = margin <= 2
        default: tight = margin <= 1
        }
        if tight {
            return Story(kind: "close", weight: 40 + base,
                         headline: "\(wn) edges \(ln), \(line)", league: league.title)
        }
        let rout = (league.sport == "football" && margin >= 35) || (league.sport == "basketball" && margin >= 30)
        if rout {
            return Story(kind: "rout", weight: 30 + base,
                         headline: "\(wn) routs \(ln), \(line)", league: league.title)
        }
        return Story(kind: "plain", weight: 5 + base,
                     headline: "\(wn) beats \(ln), \(line)", league: league.title)
    }

    private static func rankedName(_ c: Competitor, _ league: League) -> String {
        let base = c.team?.label(for: league) ?? c.athlete?.label ?? "?"
        var name = base
        if let r = c.curatedRank?.current, r > 0, r <= 25 { name = "(\(r)) \(base)" }
        if let rec = Extras.record(c) { name += " (\(rec))" }
        return name
    }

    private static func teamBlocks(_ league: League, _ events: [ESPNEvent], day: Date) -> [Block] {
        var live: [Row] = []
        var done: [Row] = []
        var upcoming: [(Date, [Row])] = []

        for event in events {
            guard let comp = event.competitions?.first,
                  let comps = comp.competitors, comps.count >= 2 else { continue }
            let status = comp.status ?? event.status
            let state = status?.type?.state ?? "pre"
            let typeName = status?.type?.name ?? ""
            let home = comps.first { $0.homeAway == "home" } ?? comps[1]
            let away = comps.first { $0.homeAway == "away" } ?? comps[0]
            let search = [home, away].map { $0.team?.searchText ?? "" }.joined(separator: " ")

            switch state {
            case "post":
                var first = away, second = home
                if home.winner == true {
                    first = home; second = away
                } else if away.winner != true,
                          let h = Int(score(home)), let a = Int(score(away)), h > a {
                    first = home; second = away
                }
                let left = "\(rankedName(first, league)) \(score(first)), \(rankedName(second, league)) \(score(second))"
                let right = status?.type?.shortDetail ?? "Final"
                var st = story(league, first, second, status: status)
                if let h = comp.headlines?.first {
                    if let t = h.shortLinkText, !t.isEmpty { st?.headline = t }
                    var r = (h.description ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    if r.hasPrefix("—") || r.hasPrefix("-") { r = String(r.dropFirst()).trimmingCharacters(in: .whitespaces) }
                    if !r.isEmpty { st?.recap = r }
                }
                done.append(Row(kind: .line, left: left, right: right, search: search,
                                game: GameRef(league: league, date: day, eventID: event.id, recap: st?.recap),
                                start: Fmt.parse(comp.date ?? event.date),
                                art: [art(first), art(second)],
                                story: st,
                                sides: [Side(name: rankedName(first, league), score: score(first), won: true),
                                        Side(name: rankedName(second, league), score: score(second))]))
            case "in":
                let left = "\(rankedName(away, league)) \(score(away)), \(rankedName(home, league)) \(score(home))"
                let right = status?.type?.shortDetail ?? status?.type?.detail ?? "Live"
                let close = isClose(league, Int(score(home)) ?? 0, Int(score(away)) ?? 0, period: status?.period)
                live.append(Row(kind: .live, left: left, right: right, search: search,
                                game: GameRef(league: league, date: day, eventID: event.id),
                                start: Fmt.parse(comp.date ?? event.date), close: close,
                                art: [art(away), art(home)],
                                sides: [Side(name: rankedName(away, league), score: score(away)),
                                        Side(name: rankedName(home, league), score: score(home))]))
            default:
                let joiner = (comp.neutralSite ?? false) ? "vs." : "at"
                let left = "\(rankedName(away, league)) \(joiner) \(rankedName(home, league))"
                let date = Fmt.parse(comp.date ?? event.date)
                var right = Fmt.time(date)
                if typeName.contains("POSTPONED") || typeName.contains("CANCELED") || typeName.contains("DELAYED") {
                    right = status?.type?.description ?? right
                } else if let net = comp.broadcasts?.first?.names?.first {
                    right += " · \(net)"
                }
                var group = [Row(kind: .line, left: left, right: right, search: search, start: date,
                                 art: [art(away), art(home)])]
                upcoming.append((date ?? .distantFuture, group))
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

    // MARK: Golf

    private static func golfBlocks(_ league: League, _ events: [ESPNEvent]) -> [Block] {
        events.compactMap { event -> Block? in
            guard let comp = event.competitions?.first else { return nil }
            var rows: [Row] = []
            let status = comp.status ?? event.status
            rows.append(Row(kind: .sub, left: status?.type?.description ?? "Leaderboard"))
            let players = (comp.competitors ?? []).sorted { ($0.order ?? 999) < ($1.order ?? 999) }
            let gstart = Fmt.parse(comp.date ?? event.date)
            let gdone = status?.type?.state == "post"
            for (i, p) in players.prefix(15).enumerated() {
                let name = p.athlete?.label ?? "?"
                rows.append(Row(kind: .line, left: "\(p.order ?? 0). \(name)", right: p.score?.value ?? "", search: name,
                                start: i == 0 ? gstart : nil, isFinal: gdone))
            }
            if players.isEmpty {
                rows.append(Row(kind: .note, left: "Field not yet posted."))
            }
            return Block(id: "\(league.id)-\(event.id)", title: event.name ?? league.title, rows: rows)
        }
    }

    // MARK: Racing

    private static func racingBlocks(_ league: League, _ events: [ESPNEvent]) -> [Block] {
        events.compactMap { event -> Block? in
            guard let comps = event.competitions, !comps.isEmpty else { return nil }
            var rows: [Row] = []
            for comp in comps {
                let label = comp.type?.abbreviation ?? "Session"
                let state = (comp.status ?? event.status)?.type?.state ?? "pre"
                let date = Fmt.parse(comp.date)
                if state == "post" {
                    let top = (comp.competitors ?? [])
                        .sorted { ($0.order ?? 999) < ($1.order ?? 999) }
                        .prefix(3)
                    let names = top.enumerated().map { "\($0.offset + 1). \($0.element.athlete?.label ?? "?")" }
                    rows.append(Row(kind: .line, left: "\(label): " + names.joined(separator: "  "), right: "Final",
                                    search: names.joined(separator: " "), start: date, isFinal: true))
                } else if state == "in" {
                    rows.append(Row(kind: .live, left: label, right: "Live", start: date))
                } else {
                    rows.append(Row(kind: .line, left: label, right: Fmt.dayTime(date), start: date))
                }
            }
            return Block(id: "\(league.id)-\(event.id)", title: event.name ?? league.title, rows: rows)
        }
    }

    // MARK: MMA

    private static func fightBlocks(_ league: League, _ events: [ESPNEvent]) -> [Block] {
        events.compactMap { event -> Block? in
            guard let all = event.competitions, !all.isEmpty else { return nil }
            // The feed lists the main event last. Numbered events show the main card (top five);
            // Fight Nights show only the main event and co-main.
            let name = event.name ?? ""
            let numbered = name.range(of: #"UFC \d+"#, options: .regularExpression) != nil
            let keep = numbered ? 5 : 2
            let comps = Array(all.suffix(keep).reversed())
            var rows: [Row] = []
            for (i, comp) in comps.enumerated() {
                let fighters = comp.competitors ?? []
                guard fighters.count >= 2 else { continue }
                let state = (comp.status ?? event.status)?.type?.state ?? "pre"
                let weight = comp.type?.abbreviation ?? ""
                let slot = i == 0 ? "Main event" : (i == 1 ? "Co-main" : "Main card")
                let a = fighters[0].athlete?.label ?? "?"
                let b = fighters[1].athlete?.label ?? "?"
                let when = Fmt.parse(comp.date)
                if state == "post", let w = fighters.first(where: { $0.winner == true }) {
                    let l = (w.athlete?.label == a) ? b : a
                    rows.append(Row(kind: .line, left: "\(slot): \(w.athlete?.label ?? "?") def. \(l)", right: weight,
                                    search: "\(a) \(b)", start: when, isFinal: true))
                } else {
                    let right = state == "in" ? "Live" : [weight, Fmt.dayTime(when)].filter { !$0.isEmpty }.joined(separator: " · ")
                    rows.append(Row(kind: state == "in" ? .live : .line, left: "\(slot): \(a) vs. \(b)", right: right,
                                    search: "\(a) \(b)", start: when))
                }
            }
            guard !rows.isEmpty else { return nil }
            return Block(id: "\(league.id)-\(event.id)", title: name.isEmpty ? league.title : name, rows: rows)
        }
    }

    // MARK: Tournament weeks (golf, racing, tennis) and fight cards for the Calendar

    static func tourneyBlocks(for league: League, events: [ESPNEvent]) -> [Block] {
        if league.kind == .fighting {
            return fightBlocks(league, events.sorted { ($0.date ?? "") < ($1.date ?? "") })
        }
        let sorted = events.sorted { ($0.date ?? "") < ($1.date ?? "") }
        var rows: [Row] = []
        for e in sorted {
            let start = Fmt.parse(e.date)
            let end = Fmt.parse(e.endDate) ?? start
            var span = start.map { Fmt.shortDay($0) } ?? ""
            if let s = start, let en = end, !Calendar.current.isDate(s, inSameDayAs: en) {
                span += " – " + Fmt.shortDay(en)
            }
            let state = (e.competitions?.first?.status ?? e.status)?.type?.state ?? "pre"
            let name = e.name ?? "Event"
            if state == "in" {
                rows.append(Row(kind: .live, left: name, right: span))
            } else {
                rows.append(Row(kind: .line, left: name, right: span))
            }
            if state == "post", league.kind == .golf,
               let top = (e.competitions?.first?.competitors ?? []).min(by: { ($0.order ?? 999) < ($1.order ?? 999) }) {
                rows.append(Row(kind: .note, left: "Winner: \(top.athlete?.label ?? "?") \(top.score?.value ?? "")"))
            }
        }
        guard !rows.isEmpty else { return [] }
        return [Block(id: "weeks-\(league.id)", title: league.title + " · tournament weeks", rows: rows, sport: league.sport)]
    }

    // MARK: Tennis

    private static func tennisName(_ c: Competitor) -> String {
        let base = c.athlete?.label ?? c.roster?.shortDisplayName ?? c.roster?.displayName ?? "?"
        if let r = c.curatedRank?.current, r > 0, r <= 32 { return "(\(r)) \(base)" }
        return base
    }

    /// "6-3 5-7 1-0(4)" read from `first`'s side.
    private static func setScores(_ first: Competitor, _ second: Competitor) -> String {
        let a = first.linescores ?? []
        let b = second.linescores ?? []
        return zip(a, b).map { x, y -> String in
            let g1 = Int(x.value ?? 0), g2 = Int(y.value ?? 0)
            var s = "\(g1)-\(g2)"
            let tbs = [x.tiebreak, y.tiebreak].compactMap { $0 }
            if let loserPoints = tbs.min() { s += "(\(Int(loserPoints)))" }
            return s
        }.joined(separator: " ")
    }

    private static func tennisBlocks(_ league: League, _ events: [ESPNEvent], day: Date) -> [Block] {
        var blocks: [Block] = []
        for event in events {
            for group in event.groupings ?? [] {
                var live: [Row] = []
                var done: [Row] = []
                var upcoming: [(Date, Row)] = []

                for comp in group.competitions ?? [] {
                    let date = Fmt.parse(comp.date)
                    // The feed returns the whole tournament week; keep only the chosen day.
                    if let date, !Calendar.current.isDate(date, inSameDayAs: day) { continue }
                    let players = (comp.competitors ?? []).sorted { ($0.order ?? 9) < ($1.order ?? 9) }
                    guard players.count >= 2 else { continue }
                    let p1 = players[0], p2 = players[1]
                    let search = [p1, p2].map { tennisName($0) }.joined(separator: " ")
                    let state = comp.status?.type?.state ?? "pre"
                    let round = comp.round?.displayName ?? ""

                    switch state {
                    case "post":
                        let (w, l) = (p2.winner == true) ? (p2, p1) : (p1, p2)
                        var right = round
                        let desc = comp.status?.type?.description ?? ""
                        if desc.contains("Retire") { right = "ret." } else if desc.contains("Walkover") { right = "w/o" }
                        let sets = setScores(w, l)
                        let left = "\(tennisName(w)) def. \(tennisName(l))" + (sets.isEmpty ? "" : " \(sets)")
                        done.append(Row(kind: .line, left: left, right: right, search: search, start: date, isFinal: true))
                    case "in":
                        let sets = setScores(p1, p2)
                        let left = "\(tennisName(p1)) vs. \(tennisName(p2))"
                        live.append(Row(kind: .live, left: left, right: sets.isEmpty ? "Live" : sets, search: search, start: date))
                    default:
                        let left = "\(tennisName(p1)) vs. \(tennisName(p2))"
                        var right = Fmt.time(date)
                        if !round.isEmpty { right += " · \(round)" }
                        upcoming.append((date ?? .distantFuture, Row(kind: .line, left: left, right: right, search: search, start: date)))
                    }
                }

                var rows: [Row] = []
                if !live.isEmpty { rows.append(Row(kind: .sub, left: "In progress")); rows += live }
                if !done.isEmpty { rows.append(Row(kind: .sub, left: "Final")); rows += done }
                if !upcoming.isEmpty {
                    rows.append(Row(kind: .sub, left: "Upcoming"))
                    rows += upcoming.sorted { $0.0 < $1.0 }.map { $0.1 }
                }
                guard !rows.isEmpty else { continue }
                let title = [event.name, group.grouping?.displayName].compactMap { $0 }.joined(separator: " · ")
                blocks.append(Block(id: "\(league.id)-\(event.id)-\(group.grouping?.displayName ?? "")", title: title, rows: rows))
            }
        }
        return blocks
    }
}

// MARK: - Extra game info (records, odds, network) shared by all feeds

struct GameExtras {
    var records: [String: String] = [:]   // lowercased nickname -> "7-2"
    var odds: String?
    var network: String?
}

enum Extras {
    static func key(_ a: String, _ b: String) -> String {
        [a.lowercased(), b.lowercased()].sorted().joined(separator: "|")
    }

    static func record(_ c: Competitor) -> String? {
        let recs = c.records ?? []
        return (recs.first { $0.type == "total" } ?? recs.first { $0.type == "ytd" })?.summary
    }

    static func oddsLine(_ comp: Competition) -> String? {
        guard let o = comp.odds?.first else { return nil }
        var parts: [String] = []
        if let d = o.details, !d.isEmpty { parts.append(d) }
        if let ou = o.overUnder { parts.append("O/U " + (ou.rounded() == ou ? String(Int(ou)) : String(ou))) }
        return parts.isEmpty ? nil : "Line: " + parts.joined(separator: " · ")
    }

    /// Builds a lookup from an ESPN scoreboard so NHL/MLB rows (own feeds) can show the same info.
    static func map(_ events: [ESPNEvent]) -> [String: GameExtras] {
        var out: [String: GameExtras] = [:]
        for e in events {
            guard let comp = e.competitions?.first, let cs = comp.competitors, cs.count >= 2,
                  let a = cs[0].team?.name, let b = cs[1].team?.name else { continue }
            var x = GameExtras()
            x.records[a.lowercased()] = record(cs[0])
            x.records[b.lowercased()] = record(cs[1])
            x.network = comp.broadcasts?.first?.names?.first
            out[key(a, b)] = x
        }
        return out
    }

    /// "Kings (8-5)" when a record is known.
    static func label(_ name: String, _ extras: GameExtras?) -> String {
        if let r = extras?.records[name.lowercased()] { return "\(name) (\(r))" }
        return name
    }
}
