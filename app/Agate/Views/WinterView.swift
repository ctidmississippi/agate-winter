import SwiftUI

struct SeasonListView: View {
    @Environment(\.textScale) private var s
    @StateObject private var store = WinterStore()
    @AppStorage("favorites") private var favoritesRaw = "Ole Miss, Titans, Grizzlies, Predators"
    @AppStorage private var url: String
    @State private var selected = "All sports"
    let title: String
    let motto: String
    let resource: String

    init(title: String, motto: String, resource: String, urlKey: String) {
        self.title = title
        self.motto = motto
        self.resource = resource
        _url = AppStorage(wrappedValue: "", urlKey)
    }

    private var shown: [GroupSection] {
        selected == "All sports" ? store.sections : store.sections.filter { $0.title == selected }
    }

    var body: some View {
        NavigationStack {
            PageScroll {
                Masthead(title: title, motto: motto)
                Rule(height: 1)
                HStack {
                    Picker("Sport", selection: $selected) {
                        Text("All sports").tag("All sports")
                        ForEach(store.sections, id: \.title) { Text($0.title).tag($0.title) }
                    }
                    .pickerStyle(.menu)
                    .tint(Theme.accent)
                    Spacer()
                    if store.loading { ProgressView().controlSize(.small) }
                }
                .padding(.vertical, 6)
                DoubleRule()

                if !store.updated.isEmpty {
                    StatusLine(text: "Compiled \(store.updated). Updated when you ask for a refresh.")
                }
                if !store.note.isEmpty { StatusLine(text: store.note) }

                ForEach(shown) { group in
                    SportHeader(title: group.title)
                    NextUpBanner(group: group)
                    if !group.checked.isEmpty || !group.source.isEmpty {
                        Text(["Checked \(group.checked)", group.source.isEmpty ? "" : "Source: \(group.source)"]
                            .filter { !$0.hasSuffix(" ") && $0 != "" }.joined(separator: " · "))
                            .font(.sans(10 * s))
                            .foregroundStyle(Theme.ink.opacity(0.55))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 2)
                    }
                    ForEach(group.blocks) { block in
                        BlockView(block: block, favorites: parseFavorites(favoritesRaw))
                    }
                }
                if store.sections.isEmpty && !store.loading {
                    StatusLine(text: "No data found. Check the URL in Settings or reinstall the app.")
                }
            }
            .refreshable { await store.load(urlString: url, resource: resource) }
            .task(id: url) { await store.load(urlString: url, resource: resource) }
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}


/// The next thing on a sport's calendar, pulled from its first current-season block.
struct NextUpBanner: View {
    @Environment(\.textScale) private var s
    let group: GroupSection

    private var next: Row? {
        for b in group.blocks where !b.title.contains("Results") && !b.title.hasPrefix("LA28") {
            if let r = b.rows.first(where: { $0.kind == .line || $0.kind == .live }) { return r }
        }
        return nil
    }

    var body: some View {
        if let r = next, !r.left.contains("ask for a refresh") {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("NEXT UP")
                    .font(.sans(10 * s, bold: true))
                    .tracking(0.8)
                    .foregroundStyle(Theme.accent)
                Text(r.right.isEmpty ? r.left : "\(r.left) · \(r.right)")
                    .font(.line(13 * s, bold: true))
                    .foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .background(Theme.shade)
        }
    }
}

/// One tab for Olympic seasons and the LA28 guide.
struct OlympicsView: View {
    @State private var season = "winter"

    var body: some View {
        VStack(spacing: 0) {
            Picker("Games", selection: $season) {
                Text("Winter").tag("winter")
                Text("Summer").tag("summer")
                Text("LA28 map").tag("map")
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Theme.paper)
            if season == "map" {
                LA28MapView()
            } else if season == "winter" {
                SeasonListView(title: "Winter Sports", motto: "“Snow, ice, and everything that slides.”",
                               resource: "winter", urlKey: "winterURL")
            } else {
                SeasonListView(title: "Summer Sports", motto: "“Every sport in the Games, in small type.”",
                               resource: "summer", urlKey: "summerURL")
            }
        }
        .background(Theme.paper.ignoresSafeArea())
    }
}
