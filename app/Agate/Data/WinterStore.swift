import Foundation
import SwiftUI

// The Winter tab reads a small JSON file that is compiled by hand (see README, "Refreshing winter").
// It is bundled in the app (Resources/winter.json); if a URL is set in Settings, that is tried first.

struct WinterFeed: Decodable {
    let updated: String?
    let note: String?
    let sports: [WinterSport]
}

struct WinterSport: Decodable {
    let name: String
    let checked: String?
    let source: String?
    let blocks: [WinterBlock]
}

struct WinterBlock: Decodable {
    let title: String
    let rows: [WinterRow]
}

struct WinterRow: Decodable {
    let kind: String?      // "line" (default), "live", "sub", "note"
    let left: String
    let right: String?
}

@MainActor
final class WinterStore: ObservableObject {
    @Published var sections: [GroupSection] = []
    @Published var updated = ""
    @Published var note = ""
    @Published var source = ""
    @Published var loading = false

    func load(urlString: String, resource: String = "winter") async {
        loading = true
        defer { loading = false }

        var feed: WinterFeed?
        var src = "bundled"
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, let url = URL(string: trimmed) {
            feed = try? await ESPNClient.get(url, as: WinterFeed.self)
            if feed != nil { src = "online" }
        }
        if feed == nil,
           let url = Bundle.main.url(forResource: resource, withExtension: "json"),
           let data = try? Data(contentsOf: url) {
            feed = try? JSONDecoder().decode(WinterFeed.self, from: data)
        }
        guard let feed else {
            sections = []
            source = "none"
            return
        }

        sections = feed.sports.map { sport in
            var g = GroupSection(title: sport.name, blocks: sport.blocks.map { block in
                Block(id: sport.name + "|" + block.title, title: block.title, rows: block.rows.map { r in
                    let kind: Row.Kind
                    switch r.kind {
                    case "sub": kind = .sub
                    case "note": kind = .note
                    case "live": kind = .live
                    default: kind = .line
                    }
                    return Row(kind: kind, left: r.left, right: r.right ?? "", search: r.left)
                })
            })
            g.checked = sport.checked ?? ""
            g.source = sport.source ?? ""
            return g
        }
        updated = feed.updated ?? ""
        note = feed.note ?? ""
        source = src
    }
}
