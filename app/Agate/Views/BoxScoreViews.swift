import SwiftUI

/// One team's player stat table; scrolls sideways because some sports have 20+ columns.
struct PlayerTableView: View {
    @Environment(\.textScale) private var s
    let table: PlayerTable

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(table.caption)
                .font(.head(14 * s))
                .foregroundStyle(Theme.ink)
            Rule(height: 1)
            ScrollView(.horizontal, showsIndicators: false) {
                Grid(alignment: .trailing, horizontalSpacing: 10, verticalSpacing: 3) {
                    GridRow {
                        Text("PLAYER")
                            .font(.sans(9.5 * s, bold: true))
                            .foregroundStyle(Theme.muted)
                            .frame(width: 110, alignment: .leading)
                        ForEach(Array(table.headers.enumerated()), id: \.offset) { _, h in
                            Text(h)
                                .font(.sans(9.5 * s, bold: true))
                                .foregroundStyle(Theme.muted)
                                .frame(minWidth: 30, alignment: .trailing)
                        }
                    }
                    Divider()
                    ForEach(Array(table.rows.enumerated()), id: \.offset) { _, cells in
                        row(cells, bold: false)
                    }
                    if let totals = table.totals, !totals.isEmpty {
                        Divider()
                        row(["Totals"] + totals, bold: true)
                    }
                }
            }
        }
        .padding(.vertical, 8)
    }

    private func row(_ cells: [String], bold: Bool) -> some View {
        GridRow {
            ForEach(Array(cells.enumerated()), id: \.offset) { i, cell in
                Text(cell)
                    .font(.line(12.5 * s, bold: bold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .frame(width: i == 0 ? 110 : nil, alignment: i == 0 ? .leading : .trailing)
                    .frame(minWidth: i == 0 ? nil : 30, alignment: .trailing)
            }
        }
    }
}

/// Last results and upcoming games for one team.
struct TeamScheduleView: View {
    @Environment(\.textScale) private var s
    @Environment(\.dismiss) private var dismiss
    let league: League
    let team: TeamLink

    @State private var recent: [Row] = []
    @State private var upcoming: [Row] = []
    @State private var loading = true
    @State private var failed = false

    var body: some View {
        NavigationStack {
            PageScroll {
                Masthead(title: team.name, motto: "Schedule · \(league.title)")
                Rule(height: 1)
                if !recent.isEmpty {
                    SportHeader(title: "Recent")
                    BlockView(block: Block(id: "recent", title: "Results", rows: recent), favorites: [])
                }
                if !upcoming.isEmpty {
                    SportHeader(title: "Upcoming")
                    BlockView(block: Block(id: "next", title: "Next games", rows: upcoming), favorites: [])
                }
                if loading {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 30)
                } else if failed {
                    StatusLine(text: "Couldn't load this schedule.")
                } else if recent.isEmpty && upcoming.isEmpty {
                    StatusLine(text: "No games found.")
                }
                StatusLine(text: "Via ESPN")
            }
            .toolbar(.hidden, for: .navigationBar)
            .overlay(alignment: .topTrailing) {
                Button("Done") { dismiss() }
                    .font(.sans(13 * s, bold: true))
                    .foregroundStyle(Theme.accent)
                    .padding(.trailing, 16)
                    .padding(.top, 8)
            }
            .task { await load() }
        }
    }

    @MainActor private func load() async {
        loading = true
        defer { loading = false }
        do {
            let events = try await ESPNClient.teamSchedule(sport: league.sport, slug: league.slug, teamID: team.id)
            build(events)
        } catch {
            failed = true
        }
    }

    private func build(_ events: [ESPNEvent]) {
        struct Item { var date: Date; var row: Row; var done: Bool }
        var items: [Item] = []
        let now = Date()
        for e in events {
            guard let comp = e.competitions?.first, let cs = comp.competitors, cs.count >= 2 else { continue }
            let me = cs.first { $0.id == team.id || $0.team?.id == team.id } ?? cs[0]
            let opp = cs.first { ($0.team?.id ?? $0.id) != team.id } ?? cs[1]
            let date = Fmt.parse(comp.date ?? e.date) ?? .distantFuture
            let state = (comp.status ?? e.status)?.type?.state
            let finished = state == "post" || (state == nil && date < now)
            let oppName = opp.team?.shortDisplayName ?? opp.team?.displayName ?? "?"
            let prefix = (me.homeAway == "home") ? "vs." : "at"
            if finished {
                let mine = me.score?.value ?? "", theirs = opp.score?.value ?? ""
                let letter = (me.winner == true) ? "W" : (opp.winner == true ? "L" : "")
                let result = [letter, "\(mine)–\(theirs)"].filter { !$0.isEmpty }.joined(separator: " ")
                items.append(Item(date: date,
                                  row: Row(kind: .line, left: "\(result) \(prefix) \(oppName)", right: Fmt.shortDay(date)),
                                  done: true))
            } else {
                var right = Fmt.dayTime(date)
                if let net = comp.broadcasts?.first?.names?.first { right += " · \(net)" }
                items.append(Item(date: date, row: Row(kind: .line, left: "\(prefix) \(oppName)", right: right), done: false))
            }
        }
        items.sort { $0.date < $1.date }
        recent = Array(items.filter { $0.done }.suffix(6).map { $0.row })
        upcoming = Array(items.filter { !$0.done }.prefix(8).map { $0.row })
    }
}
