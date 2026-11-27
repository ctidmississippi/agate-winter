import SwiftUI

// MARK: - Whole-day slate image

/// Every final and live game of the day on one fixed-light page, for sharing as an image.
struct DaySlateCard: View {
    let date: Date
    let groups: [GroupSection]

    private struct Section: Identifiable {
        let id = UUID()
        let title: String
        let sport: String
        let rows: [Row]
    }

    private var sections: [Section] {
        groups.flatMap { g in
            g.blocks.compactMap { b -> Section? in
                let rows = b.rows.filter { ($0.kind == .line && $0.game != nil) || $0.kind == .live }
                return rows.isEmpty ? nil : Section(title: b.title, sport: b.sport, rows: rows)
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("The Agate Page")
                .font(.nameplate(36))
                .foregroundStyle(Theme.Light.ink)
                .frame(maxWidth: .infinity)
            Rectangle().fill(Theme.Light.ink).frame(height: 1)
            Text(Fmt.longDay(date))
                .font(.sans(11, bold: true))
                .foregroundStyle(Theme.Light.muted)
                .padding(.vertical, 3)
            Rectangle().fill(Theme.Light.ink).frame(height: 1)

            ForEach(sections) { sec in
                Text(sec.title.uppercased())
                    .font(.sans(10, bold: true))
                    .tracking(0.8)
                    .foregroundStyle(Theme.Light.muted)
                    .padding(.top, 8)
                ForEach(sec.rows) { r in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(r.left)
                            .font(.line(11.5))
                            .foregroundStyle(Theme.Light.ink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(r.right)
                            .font(.line(10.5))
                            .foregroundStyle(Theme.Light.muted)
                    }
                }
            }
            if sections.isEmpty {
                Text("No finals yet.")
                    .font(.sans(11.5)).italic()
                    .foregroundStyle(Theme.Light.muted)
                    .padding(.top, 8)
            }
            Rectangle().fill(Theme.Light.ink).frame(height: 1).padding(.top, 10)
            Text("Every final, every standing, every line.")
                .font(.sans(10)).italic()
                .foregroundStyle(Theme.Light.muted)
                .frame(maxWidth: .infinity)
        }
        .padding(18)
        .frame(width: 380)
        .background(Theme.Light.paper)
    }
}

// MARK: - Front page

/// A newspaper front page built from the day's finals: lead story, a few more, and a count line.
struct FrontPageCard: View {
    let date: Date
    let groups: [GroupSection]

    private var stories: [Story] {
        groups.flatMap { $0.blocks.flatMap { $0.rows.compactMap { $0.story } } }
            .sorted { $0.weight > $1.weight }
    }
    private var liveCount: Int {
        groups.reduce(0) { $0 + $1.blocks.reduce(0) { $0 + $1.rows.filter { $0.kind == .live }.count } }
    }

    var body: some View {
        let all = stories
        let lead = all.first
        let rest = Array(all.dropFirst().prefix(6))
        let upsets = all.filter { $0.kind == "upset" }.count
        let ots = all.filter { $0.kind == "overtime" }.count

        VStack(alignment: .leading, spacing: 6) {
            Text("The Agate")
                .font(.nameplate(44))
                .foregroundStyle(Theme.Light.ink)
                .frame(maxWidth: .infinity)
            Rectangle().fill(Theme.Light.ink).frame(height: 2)
            Text("\(Fmt.longDay(date)) · \(all.count) finals · \(upsets) upsets · \(ots) in overtime"
                 + (liveCount > 0 ? " · \(liveCount) live" : ""))
                .font(.sans(10.5, bold: true))
                .foregroundStyle(Theme.Light.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            Rectangle().fill(Theme.Light.ink).frame(height: 1)

            if let lead {
                Text(lead.league.uppercased())
                    .font(.sans(10, bold: true)).tracking(0.8)
                    .foregroundStyle(Theme.Light.accent)
                    .padding(.top, 6)
                Text(lead.headline)
                    .font(.head(26, black: true))
                    .foregroundStyle(Theme.Light.ink)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("A quiet day on the scoreboard")
                    .font(.head(24, black: true))
                    .foregroundStyle(Theme.Light.ink)
                    .padding(.top, 6)
            }

            if !rest.isEmpty {
                Rectangle().fill(Theme.Light.rule).frame(height: 1).padding(.top, 6)
                Text("ALSO TODAY")
                    .font(.sans(10, bold: true)).tracking(0.8)
                    .foregroundStyle(Theme.Light.muted)
                ForEach(Array(rest.enumerated()), id: \.offset) { _, s in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(s.league.uppercased())
                            .font(.sans(9, bold: true)).tracking(0.6)
                            .foregroundStyle(Theme.Light.muted)
                        Text(s.headline)
                            .font(.head(14))
                            .foregroundStyle(Theme.Light.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 2)
                }
            }
            Rectangle().fill(Theme.Light.ink).frame(height: 1).padding(.top, 8)
        }
        .padding(18)
        .frame(width: 380)
        .background(Theme.Light.paper)
    }
}

// MARK: - Sheet with preview and share

struct DayShareSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.textScale) private var s
    let date: Date
    let groups: [GroupSection]
    var showDone = true
    @State private var mode = 0
    @State private var shareUI: UIImage?
    @State private var showActivity = false

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Picker("Format", selection: $mode) {
                    Text("Front page").tag(0)
                    Text("Full slate").tag(1)
                }
                .pickerStyle(.segmented)
                Button {
                    shareUI = mode == 0
                        ? renderShareImage(FrontPageCard(date: date, groups: groups))
                        : renderShareImage(DaySlateCard(date: date, groups: groups))
                    showActivity = shareUI != nil
                } label: { Image(systemName: "square.and.arrow.up") }
                .padding(.leading, 8)
                .accessibilityLabel("Share")
                if showDone {
                    Button("Done") { dismiss() }
                        .font(.sans(13 * s, bold: true))
                }
            }
            .tint(Theme.accent)
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, 16)
            .padding(.top, 12)

            ScrollView {
                if mode == 0 {
                    FrontPageCard(date: date, groups: groups)
                } else {
                    DaySlateCard(date: date, groups: groups)
                }
            }
            .background(Theme.paper)
        }
        .background(Theme.paper.ignoresSafeArea())
        .sheet(isPresented: $showActivity) {
            if let ui = shareUI { ActivitySheet(items: [ui]).presentationDetents([.medium, .large]) }
        }
    }
}
