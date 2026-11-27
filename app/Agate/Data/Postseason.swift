import Foundation

/// Playoff brackets (series and single games, by round) and the college bowl schedule.
enum PostseasonBuilder {
    private static func headline(_ comp: Competition) -> String {
        comp.notes?.first?.headline ?? ""
    }

    private static func roundName(_ comp: Competition) -> String {
        let h = headline(comp)
        if h.isEmpty { return "Postseason" }
        let parts = h.components(separatedBy: " - ")
        if let cfp = parts.first(where: { $0.contains("CFP") || $0.contains("Playoff") }) { return cfp }
        return parts[0]
    }

    private static func name(_ c: Competitor, _ league: League) -> String {
        var n = c.team?.label(for: league) ?? "TBD"
        if let r = c.curatedRank?.current, r > 0, r <= 25 { n = "(\(r)) \(n)" }
        return n
    }

    private static func gameRow(_ e: ESPNEvent, _ comp: Competition, _ league: League) -> Row? {
        guard let comps = comp.competitors, comps.count >= 2 else { return nil }
        let home = comps.first { $0.homeAway == "home" } ?? comps[1]
        let away = comps.first { $0.homeAway == "away" } ?? comps[0]
        let state = (comp.status ?? e.status)?.type?.state ?? "pre"
        let date = Fmt.parse(comp.date ?? e.date)
        let ref = GameRef(league: league, date: date ?? Date(), eventID: e.id)
        let art = [TeamArt(color: away.team?.color, logo: away.team?.logo),
                   TeamArt(color: home.team?.color, logo: home.team?.logo)]
        func sc(_ c: Competitor) -> String { c.score?.value ?? "" }
        switch state {
        case "post":
            var w = away, l = home
            if home.winner == true { w = home; l = away }
            else if away.winner != true, (Int(sc(home)) ?? 0) > (Int(sc(away)) ?? 0) { w = home; l = away }
            return Row(kind: .line, left: "\(name(w, league)) \(sc(w)), \(name(l, league)) \(sc(l))",
                       right: (comp.status ?? e.status)?.type?.shortDetail ?? "Final",
                       search: name(away, league) + " " + name(home, league), game: ref, start: date, art: art)
        case "in":
            return Row(kind: .live, left: "\(name(away, league)) \(sc(away)), \(name(home, league)) \(sc(home))",
                       right: (comp.status ?? e.status)?.type?.shortDetail ?? "Live",
                       search: name(away, league) + " " + name(home, league), game: ref, start: date, art: art)
        default:
            var right = Fmt.dayTime(date)
            if let net = comp.broadcasts?.first?.names?.first { right += " · \(net)" }
            return Row(kind: .line, left: "\(name(away, league)) at \(name(home, league))", right: right,
                       search: name(away, league) + " " + name(home, league), start: date, art: art)
        }
    }

    /// Bracket: one block per round, in date order. Best-of series collapse to one row each.
    static func bracket(_ league: League, events: [ESPNEvent]) -> [Block] {
        var order: [String] = []
        var rounds: [String: [(Date, Row)]] = [:]
        var seenSeries = Set<String>()
        let sorted = events.sorted { ($0.date ?? "") > ($1.date ?? "") }   // newest game first, so a series shows its latest state

        for e in sorted {
            guard let comp = e.competitions?.first else { continue }
            let round = roundName(comp)
            let date = Fmt.parse(comp.date ?? e.date) ?? .distantFuture
            var row: Row?
            if let series = comp.series, series.type == "playoff", let summary = series.summary,
               let comps = comp.competitors, comps.count >= 2 {
                let ids = comps.compactMap { $0.team?.id }.sorted().joined(separator: "-")
                let key = round + "|" + ids
                if !seenSeries.insert(key).inserted { continue }
                let home = comps.first { $0.homeAway == "home" } ?? comps[1]
                let away = comps.first { $0.homeAway == "away" } ?? comps[0]
                row = Row(kind: series.completed == true ? .line : .live,
                          left: "\(name(home, league)) vs. \(name(away, league))", right: summary,
                          search: name(home, league) + " " + name(away, league), game: nil, start: date,
                          art: [TeamArt(color: home.team?.color, logo: home.team?.logo),
                                TeamArt(color: away.team?.color, logo: away.team?.logo)])
            } else {
                row = gameRow(e, comp, league)
            }
            guard let r = row else { continue }
            if rounds[round] == nil { order.append(round) }
            rounds[round, default: []].append((date, r))
        }
        // Rounds in the order they begin.
        let sortedRounds = order.sorted { a, b in
            (rounds[a]?.map { $0.0 }.min() ?? .distantFuture) < (rounds[b]?.map { $0.0 }.min() ?? .distantFuture)
        }
        return sortedRounds.compactMap { r in
            guard let items = rounds[r] else { return nil }
            return Block(id: "round-\(league.id)-\(r)", title: r,
                         rows: items.sorted { $0.0 < $1.0 }.map { $0.1 }, sport: league.sport)
        }
    }

    /// College bowls: the CFP games first, then every other bowl by date.
    static func bowls(_ league: League, events: [ESPNEvent]) -> [Block] {
        var cfp: [(Date, Row)] = []
        var bowls: [(Date, Row)] = []
        for e in events {
            guard let comp = e.competitions?.first else { continue }
            let h = headline(comp)
            let parts = h.components(separatedBy: " - ")
            let isCFP = h.contains("CFP") || h.contains("Playoff")
            let bowlName = parts.first(where: { !$0.contains("CFP") }) ?? (parts.first ?? "Bowl")
            guard var row = gameRow(e, comp, league) else { continue }
            let date = Fmt.parse(comp.date ?? e.date) ?? .distantFuture
            let label = isCFP ? (parts.first(where: { $0.contains("CFP") }) ?? "CFP") : ""
            row.left = (bowlName.isEmpty ? "" : bowlName + ": ") + row.left + (label.isEmpty || label == bowlName ? "" : " (\(label))")
            let when = Fmt.shortDay(date == .distantFuture ? nil : date)
            if row.kind == .line, row.game == nil { row.right = when + " · " + row.right }
            if isCFP { cfp.append((date, row)) } else { bowls.append((date, row)) }
        }
        var blocks: [Block] = []
        if !cfp.isEmpty {
            blocks.append(Block(id: "cfp", title: "College Football Playoff",
                                rows: cfp.sorted { $0.0 < $1.0 }.map { $0.1 }, sport: "football"))
        }
        if !bowls.isEmpty {
            blocks.append(Block(id: "bowls", title: "Bowl games",
                                rows: bowls.sorted { $0.0 < $1.0 }.map { $0.1 }, sport: "football"))
        }
        return blocks
    }
}
