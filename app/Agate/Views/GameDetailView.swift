import SwiftUI

struct GameDetailView: View {
    @Environment(\.textScale) private var s
    @Environment(\.dismiss) private var dismiss
    let ref: GameRef

    @State private var content: GameDetailContent?
    @State private var loading = true
    @State private var failed = false
    @State private var showFull = false
    @State private var showPlays = false
    @State private var allPlays = false
    @State private var shareUI: UIImage?
    @State private var showActivity = false
    @State private var scheduleTeam: TeamLink?

    var body: some View {
        NavigationStack {
            PageScroll {
                Masthead(title: "Box Score", motto: ref.league.title)
                Rule(height: 1)
                if let c = content {
                    Text(c.title)
                        .font(.head(18 * s, black: true))
                        .foregroundStyle(Theme.ink)
                        .padding(.top, 10)
                    Text(c.status)
                        .font(.sans(11.5 * s))
                        .foregroundStyle(Theme.muted)
                        .padding(.bottom, 6)
                    if let r = ref.recap {
                        Text(r)
                            .font(.head(15 * s))
                            .foregroundStyle(Theme.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.bottom, 8)
                    }
                    DoubleRule()
                    if let t = c.lineScore { AgateTable(table: t, favorites: []) }
                    ForEach(c.sections) { BlockView(block: $0, favorites: []) }
                    if let t = c.teamStats { AgateTable(table: t, favorites: []) }

                    if !c.players.isEmpty {
                        Button { withAnimation { showFull.toggle() } } label: {
                            Text(showFull ? "Hide full box score ▴" : "Full box score ▾")
                                .font(.sans(13 * s, bold: true))
                                .foregroundStyle(Theme.accent)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)
                        if showFull {
                            ForEach(c.players) { PlayerTableView(table: $0) }
                        }
                    }

                    if !c.playByPlay.isEmpty {
                        Button { withAnimation { showPlays.toggle() } } label: {
                            Text(showPlays ? "Hide play by play ▴" : "Play by play (\(c.playByPlay.count)) ▾")
                                .font(.sans(13 * s, bold: true))
                                .foregroundStyle(Theme.accent)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)
                        if showPlays {
                            let shown = allPlays ? c.playByPlay : Array(c.playByPlay.prefix(60))
                            BlockView(block: Block(id: "pbp", title: "Play by play · newest first", rows: shown,
                                                   sport: ref.league.sport), favorites: [])
                            if !allPlays && c.playByPlay.count > 60 {
                                Button("Show all \(c.playByPlay.count) plays") { allPlays = true }
                                    .font(.sans(12.5 * s, bold: true))
                                    .foregroundStyle(Theme.accent)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                            }
                        }
                    }

                    if !c.teams.isEmpty {
                        SportHeader(title: "Team schedules", sport: ref.league.sport)
                        HStack(spacing: 10) {
                            ForEach(c.teams) { team in
                                Button { scheduleTeam = team } label: {
                                    Text(team.abbr + " schedule")
                                        .font(.sans(12.5 * s, bold: true))
                                        .foregroundStyle(Theme.accent)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 8)
                                        .overlay(Rectangle().stroke(Theme.accent, lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.bottom, 6)
                    }
                    StatusLine(text: "Via ESPN")
                } else if loading {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                } else {
                    StatusLine(text: failed ? "Couldn't load this game. Close and try again." : "No detail available for this game.")
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .overlay(alignment: .topTrailing) {
                HStack(spacing: 16) {
                    #if canImport(ActivityKit)
                    if let c = content, let id = ref.eventID, c.status.lowercased().contains("final") == false {
                        Button { startLive(c, id) } label: { Image(systemName: "lock.iphone") }
                            .accessibilityLabel("Follow on lock screen")
                    }
                    #endif
                    if let c = content {
                        Button {
                            shareUI = renderShareImage(ShareCard(content: c, leagueTitle: ref.league.title))
                            showActivity = shareUI != nil
                        } label: { Image(systemName: "square.and.arrow.up") }
                        .accessibilityLabel("Share")
                    }
                    Button("Done") { dismiss() }
                }
                .font(.sans(13 * s, bold: true))
                .foregroundStyle(Theme.accent)
                .padding(.trailing, 16)
                .padding(.top, 8)
            }
            .sheet(isPresented: $showActivity) {
                if let ui = shareUI { ActivitySheet(items: [ui]).presentationDetents([.medium, .large]) }
            }
            .sheet(item: $scheduleTeam) { team in
                TeamScheduleView(league: ref.league, team: team)
            }
            .task { await load() }
        }
    }

    @MainActor private func load() async {
        loading = true
        defer { loading = false }
        do {
            var id = ref.eventID
            if id == nil { id = try await resolveEventID() }
            guard let id else { return }
            let sum = try await ESPNClient.summary(sport: ref.league.sport, slug: ref.league.slug, eventID: id)
            if let built = GameDetailBuilder.build(sum, league: ref.league) {
                content = built
            }
        } catch {
            failed = true
        }
    }

    #if canImport(ActivityKit)
    private func startLive(_ c: GameDetailContent, _ id: String) {
        LiveGame.start(key: id, title: ref.league.title, score: c.title, detail: c.status)
    }
    #endif

    /// NHL/MLB rows come from their own feeds, so match the ESPN event by team names.
    private func resolveEventID() async throws -> String? {
        let events = try await ESPNClient.scoreboard(ref.league, date: ref.date)
        let wanted = ref.names.map { $0.lowercased() }
        return events.first { e in
            let comps = e.competitions?.first?.competitors ?? []
            let blob = comps.map { ($0.team?.displayName ?? "") + " " + ($0.team?.name ?? "") }.joined(separator: " ").lowercased()
            return !wanted.isEmpty && wanted.allSatisfy { blob.contains($0) }
        }?.id
    }
}
