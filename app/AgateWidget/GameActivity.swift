import Foundation
#if canImport(ActivityKit)
import ActivityKit

/// Shared by the app and the widget extension (tick both targets for this file).
struct AgateGameAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var score: String
        var detail: String
    }
    var title: String
    var key: String
}

/// Starts and updates a lock-screen Live Activity for one game. Without push (free Apple ID) it updates
/// whenever the app refreshes, so it stays current while the app is open and goes stale after.
@MainActor
enum LiveGame {
    static var current: Activity<AgateGameAttributes>?

    static func start(key: String, title: String, score: String, detail: String) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        Task {
            for a in Activity<AgateGameAttributes>.activities { await a.end(nil, dismissalPolicy: .immediate) }
        }
        let state = AgateGameAttributes.ContentState(score: score, detail: detail)
        current = try? Activity.request(attributes: AgateGameAttributes(title: title, key: key),
                                        content: .init(state: state, staleDate: nil))
    }

    static var key: String? { current?.attributes.key }

    static func update(score: String, detail: String, finished: Bool) {
        guard let a = current else { return }
        let state = AgateGameAttributes.ContentState(score: score, detail: detail)
        Task {
            if finished {
                await a.end(.init(state: state, staleDate: nil), dismissalPolicy: .after(Date().addingTimeInterval(1800)))
                current = nil
            } else {
                await a.update(.init(state: state, staleDate: nil))
            }
        }
    }

    /// Called after each scoreboard refresh.
    static func refresh(from groups: [GroupSection]) {
        guard let key = key else { return }
        for g in groups { for b in g.blocks { for r in b.rows where (r.game?.eventID ?? "") == key {
            update(score: r.left, detail: r.right, finished: r.kind != .live)
            return
        } } }
    }
}
#endif
