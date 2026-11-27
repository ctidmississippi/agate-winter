import SwiftUI

/// Playoff brackets that fill in as rounds finish, plus the college bowl and CFP schedule.
struct PostseasonView: View {
    @Environment(\.textScale) private var s
    @AppStorage("favorites") private var favoritesRaw = "Ole Miss, Titans, Grizzlies, Predators"
    @State private var mode = 0                      // 0 brackets, 1 bowls
    @State private var leagueID = "nfl"
    @State private var blocks: [Block] = []
    @State private var loading = false
    @State private var inPostseason = true
    @State private var failed = false

    private let bracketIDs = ["nfl", "nba", "nhl", "mlb", "wnba", "cbb-m", "cbb-w"]
    private var bracketLeagues: [League] { Catalog.all.filter { bracketIDs.contains($0.id) } }
    private var league: League {
        mode == 1 ? (Catalog.all.first { $0.id == "cfb-fbs" } ?? Catalog.all[0])
                  : (Catalog.all.first { $0.id == leagueID } ?? Catalog.all[0])
    }

    var body: some View {
        NavigationStack {
            PageScroll {
                Masthead(title: mode == 0 ? "The Brackets" : "Bowl Season", motto: mode == 0 ? "“Win or go home.”" : "“Thirty-odd bowls and a playoff.”")
                Rule(height: 1)
                Picker("View", selection: $mode) {
                    Text("Playoff brackets").tag(0)
                    Text("Bowls and CFP").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.top, 6)
                if mode == 0 {
                    HStack {
                        Picker("League", selection: $leagueID) {
                            ForEach(bracketLeagues) { Text($0.title).tag($0.id) }
                        }
                        .pickerStyle(.menu)
                        .tint(Theme.accent)
                        Spacer()
                        if loading { ProgressView().controlSize(.small) }
                    }
                } else if loading {
                    ProgressView().controlSize(.small).padding(.top, 8)
                }
                DoubleRule()

                ForEach(blocks) { BlockView(block: $0, favorites: parseFavorites(favoritesRaw)) }
                if blocks.isEmpty && !loading {
                    if failed {
                        StatusLine(text: "Couldn't load this. Pull down to retry.")
                    } else if mode == 0 {
                        StatusLine(text: "The \(league.title) postseason hasn't started. The bracket fills in as rounds are set.")
                    } else {
                        StatusLine(text: "Bowl games aren't posted yet.")
                    }
                }
                StatusLine(text: "Via ESPN")
            }
            .refreshable { await load() }
            .task(id: "\(mode)|\(leagueID)") { await load() }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    @MainActor private func load() async {
        loading = true
        failed = false
        defer { loading = false }
        let lg = league
        let m = mode
        do {
            let result = try await ESPNClient.postseason(lg)
            if Task.isCancelled { return }
            if m == 1 {
                blocks = PostseasonBuilder.bowls(lg, events: result.events)
            } else if result.isPostseason {
                blocks = PostseasonBuilder.bracket(lg, events: result.events)
            } else {
                blocks = []
            }
        } catch {
            if !Task.isCancelled { blocks = []; failed = true }
        }
    }
}

/// Standings, brackets and bowls share one tab.
struct StandingsHub: View {
    @State private var page = 0
    var body: some View {
        VStack(spacing: 0) {
            Picker("Section", selection: $page) {
                Text("Standings").tag(0)
                Text("Playoffs").tag(1)
                Text("Ratings").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Theme.paper)
            if page == 0 { StandingsView() } else if page == 1 { PostseasonView() } else { RatingsView() }
        }
        .background(Theme.paper.ignoresSafeArea())
    }
}
