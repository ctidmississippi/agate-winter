import Foundation
import SwiftUI

@MainActor
final class ScoresStore: ObservableObject {
    @Published var groups: [GroupSection] = []
    @Published var isLoading = false
    @Published var failures: [String] = []
    @Published var updated: Date?
    /// Every league failed, so the screen is showing the last good scores.
    @Published var offline = false
    /// Scores came from the saved copy and have not been refreshed yet.
    @Published var showingSaved = false

    private var byLeague: [String: [Block]] = [:]
    private var loadedDay = ""

    var hasLive: Bool {
        groups.contains { $0.blocks.contains { $0.rows.contains { $0.kind == .live } } }
    }

    /// Leagues with a game in progress. Live refreshes reload only these, to save data.
    var liveLeagueIDs: Set<String> {
        Set(byLeague.filter { $0.value.contains { $0.rows.contains { $0.kind == .live } } }.keys)
    }

    /// Loads every league, or only `only` when given. A league that fails keeps its last good blocks.
    func load(date: Date, leagues: [League], only: Set<String>? = nil) async {
        isLoading = true
        defer { isLoading = false }

        let day = ESPNClient.ymd(date)
        if day != loadedDay { byLeague = [:]; loadedDay = day }

        let targets = leagues.filter { only == nil || only!.contains($0.id) }
        var results: [(String, [Block]?)] = []
        await withTaskGroup(of: (String, [Block]?).self) { group in
            for league in targets {
                group.addTask { (league.id, await Self.fetch(league, date: date)) }
            }
            for await r in group { results.append(r) }
        }
        if Task.isCancelled { return }

        var failed: [String] = []
        for league in targets {
            if let r = results.first(where: { $0.0 == league.id }), let blocks = r.1 {
                byLeague[league.id] = blocks
            } else {
                failed.append(league.title)
            }
        }
        let allFailed = only == nil && !targets.isEmpty && failed.count == targets.count
        offline = allFailed
        if only == nil { failures = failed }
        groups = Self.sections(leagues, byLeague)
        if allFailed { return }

        showingSaved = false
        updated = Date()
        if Calendar.current.isDateInToday(date) {
            saveCache()
            Alerts.process(groups: groups)
            #if canImport(ActivityKit)
            LiveGame.refresh(from: groups)
            #endif
        }
    }

    private static func sections(_ leagues: [League], _ byLeague: [String: [Block]]) -> [GroupSection] {
        var sections: [GroupSection] = []
        for league in leagues {
            guard let blocks = byLeague[league.id], !blocks.isEmpty else { continue }
            if let i = sections.firstIndex(where: { $0.title == league.group }) {
                sections[i].blocks += blocks
            } else {
                sections.append(GroupSection(title: league.group, blocks: blocks))
            }
        }
        return sections
    }

    /// Own feed first (NHL, MLB); ESPN is the fallback for everything.
    nonisolated private static func fetch(_ league: League, date: Date) async -> [Block]? {
        guard let blocks = await fetchRaw(league, date: date) else { return nil }
        return blocks.map { b in
            var b = b
            b.leagueID = league.id
            if b.sport.isEmpty { b.sport = league.sport }
            return b
        }
    }

    nonisolated private static func fetchRaw(_ league: League, date: Date) async -> [Block]? {
        switch league.scoreSource {
        case .nhl:
            async let espn = try? await ESPNClient.scoreboard(league, date: date)
            let extras = Extras.map((await espn) ?? [])
            if let b = try? await NHLClient.blocks(league, date: date, extras: extras) { return b }
        case .mlb:
            async let espn = try? await ESPNClient.scoreboard(league, date: date)
            let extras = Extras.map((await espn) ?? [])
            if let b = try? await MLBClient.blocks(league, date: date, extras: extras) { return b }
        case .espn:
            break
        }
        guard let events = try? await ESPNClient.scoreboard(league, date: date) else { return nil }
        return BlockBuilder.blocks(for: league, events: events, day: date)
    }

    // MARK: Saved copy (text only, so rows are not tappable until a refresh succeeds)

    private struct SavedRow: Codable { var k: Int; var l: String; var r: String }
    private struct SavedBlock: Codable { var id: String; var title: String; var sport: String; var rows: [SavedRow] }
    private struct SavedGroup: Codable { var title: String; var blocks: [SavedBlock] }
    private struct Saved: Codable { var day: String; var saved: Date; var groups: [SavedGroup] }

    private static var cacheURL: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent("scores-saved.json")
    }

    private func saveCache() {
        guard let url = Self.cacheURL else { return }
        let kinds: [Row.Kind: Int] = [.line: 0, .live: 1, .sub: 2, .note: 3]
        let saved = Saved(day: loadedDay, saved: Date(), groups: groups.map { g in
            SavedGroup(title: g.title, blocks: g.blocks.map { b in
                SavedBlock(id: b.id, title: b.title, sport: b.sport,
                           rows: b.rows.map { SavedRow(k: kinds[$0.kind] ?? 0, l: $0.left, r: $0.right) })
            })
        })
        if let data = try? JSONEncoder().encode(saved) { try? data.write(to: url, options: .atomic) }
    }

    /// Shows today's saved scores at once, before the network answers.
    func loadSaved() {
        guard groups.isEmpty, let url = Self.cacheURL, let data = try? Data(contentsOf: url),
              let saved = try? JSONDecoder().decode(Saved.self, from: data),
              saved.day == ESPNClient.ymd(Date()) else { return }
        let kinds: [Row.Kind] = [.line, .live, .sub, .note]
        groups = saved.groups.map { g in
            GroupSection(title: g.title, blocks: g.blocks.map { b in
                Block(id: b.id, title: b.title,
                      rows: b.rows.map { Row(kind: $0.k < kinds.count ? kinds[$0.k] : .line, left: $0.l, right: $0.r) },
                      sport: b.sport)
            })
        }
        updated = saved.saved
        showingSaved = true
    }
}
