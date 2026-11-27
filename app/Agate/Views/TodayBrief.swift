import SwiftUI

/// A short "what matters today" strip at the top of Scores: big events underway, then the best results so far.
struct TodayBrief: View {
    let groups: [GroupSection]
    let events: [RadarEvent]
    let favorites: [String]
    @AppStorage(SportInterest.key) private var interestRaw = ""

    private var eventRows: [Row] {
        let today = Calendar.current.startOfDay(for: Date())
        return events
            .filter { $0.startDate <= today && $0.endDate >= today && SportInterest.level($0.sport, raw: interestRaw) != "off" }
            .sorted { ($0.big ? 0 : 1) < ($1.big ? 0 : 1) }
            .prefix(4)
            .map { e in
                let place = (e.place ?? "").isEmpty ? "" : " · " + e.place!
                return Row(kind: .line, left: (e.big ? "★ " : "") + e.title + place, right: e.whenLabel)
            }
    }

    private var topResults: [Row] {
        groups.flatMap { $0.blocks.flatMap { $0.rows.filter { $0.story != nil } } }
            .sorted { ($0.story?.weight ?? 0) > ($1.story?.weight ?? 0) }
            .prefix(3)
            .map { $0 }
    }

    var body: some View {
        let ev = eventRows, res = topResults
        if !ev.isEmpty || !res.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                if !ev.isEmpty {
                    BlockView(block: Block(id: "brief-events", title: "Don't miss today", rows: ev), favorites: favorites)
                }
                if !res.isEmpty {
                    BlockView(block: Block(id: "brief-results", title: "Top results so far", rows: res), favorites: favorites)
                }
            }
        }
    }
}
