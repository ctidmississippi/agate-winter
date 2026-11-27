import Foundation
#if canImport(ActivityKit)
import ActivityKit

/// Copy of the attributes type in Agate/Data/GameActivity.swift. Keep the two identical.
struct AgateGameAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var score: String
        var detail: String
    }
    var title: String
    var key: String
}
#endif
