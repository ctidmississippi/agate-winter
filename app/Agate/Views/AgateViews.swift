import SwiftUI

// MARK: - Masthead

struct Masthead: View {
    @Environment(\.textScale) private var s
    var title = "The Agate Page"
    var motto = "“Every final, every standing, every line. Small type, nothing left out.”"

    var body: some View {
        VStack(spacing: 4) {
            Rule(height: 3).padding(.bottom, 6)
            Text(title)
                .font(.nameplate(52 * s))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(motto)
                .font(.sans(11.5 * s))
                .italic()
                .foregroundStyle(Theme.ink2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 6)
        .padding(.bottom, 8)
    }
}

// MARK: - Section header (College Football, NFL, ...)

struct SportHeader: View {
    @Environment(\.textScale) private var s
    let title: String
    var sport = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Rule(height: 3, color: sport.isEmpty ? Theme.ink : SportAccent.color(sport))
            Text(title)
                .font(.head(22 * s, black: true))
                .foregroundStyle(Theme.ink)
                .padding(.top, 2)
        }
        .padding(.top, 14)
        .padding(.bottom, 4)
    }
}

// MARK: - Agate line block

struct BlockView: View {
    @Environment(\.textScale) private var s
    let block: Block
    let favorites: [String]
    @State private var selected: GameRef?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(block.title)
                .font(.head(15 * s))
                .foregroundStyle(block.sport.isEmpty ? Theme.ink : SportAccent.color(block.sport))
                .padding(.bottom, 3)
            Rule(height: 1, color: block.sport.isEmpty ? Theme.ink : SportAccent.color(block.sport))
            ForEach(block.rows) { row in
                if let game = row.game {
                    Button { selected = game } label: {
                        RowView(row: row, favorite: isFavorite(row.search, favorites: favorites))
                    }
                    .buttonStyle(.plain)
                } else {
                    RowView(row: row, favorite: isFavorite(row.search, favorites: favorites))
                }
            }
        }
        .padding(.vertical, 8)
        .sheet(item: $selected) { GameDetailView(ref: $0) }
    }
}

struct RowView: View {
    @Environment(\.textScale) private var s
    @AppStorage("showTeamColors") private var showColors = true
    @AppStorage("showLogos") private var showLogos = true
    let row: Row
    let favorite: Bool

    var body: some View {
        switch row.kind {
        case .sub:
            Text(row.left.uppercased())
                .font(.sans(10 * s, bold: true))
                .tracking(1.4)
                .foregroundStyle(Theme.ink2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 10)
                .padding(.bottom, 2)
                .overlay(alignment: .bottom) { Rule(height: 0.5, color: Theme.ink2) }
        case .note:
            Text(row.left)
                .font(.sans(11 * s))
                .italic()
                .foregroundStyle(Theme.muted)
                .padding(.vertical, 3)
        case .line, .live:
            if row.sides.count == 2 { stacked } else { plain }
        }
    }

    private var plain: some View {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if showColors || showLogos, !row.art.isEmpty { teamArt }
                Text(row.left)
                    .font(.line(14 * s, bold: favorite))
                    .foregroundStyle(favorite ? Theme.accent : Theme.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !row.right.isEmpty {
                    Text(row.right)
                        .font(.line(12 * s, bold: row.kind == .live))
                        .foregroundStyle(row.kind == .live ? Theme.accent : Theme.muted)
                        .multilineTextAlignment(.trailing)
                }
            }
            .padding(.vertical, 3.5)
            .overlay(alignment: .bottom) { Rule(height: 0.5, color: Theme.rule) }
    }
}

extension RowView {
    /// Two tight lines: names on the left, scores in a column, status at the right edge.
    var stacked: some View {
        let live = row.kind == .live
        return HStack(alignment: .center, spacing: 8) {
            VStack(spacing: 1) {
                ForEach(Array(row.sides.enumerated()), id: \.offset) { i, side in
                    let lead = live || side.won
                    HStack(spacing: 6) {
                        if showColors || showLogos, i < row.art.count { sideArt(row.art[i]) }
                        Text(side.name)
                            .font(.line(14 * s, bold: lead))
                            .foregroundStyle(lead ? Theme.ink : Theme.muted)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(side.score)
                            .font(.line(14 * s, bold: lead))
                            .monospacedDigit()
                            .foregroundStyle(lead ? Theme.ink : Theme.muted)
                            .frame(minWidth: 26 * s, alignment: .trailing)
                    }
                }
            }
            Text(row.right)
                .font(.line(11 * s, bold: live))
                .foregroundStyle(live ? Theme.accent : Theme.muted)
                .multilineTextAlignment(.trailing)
                .frame(width: 58 * s, alignment: .trailing)
        }
        .padding(.vertical, 4)
        .overlay(alignment: .bottom) { Rule(height: 0.5, color: Theme.rule) }
    }

    @ViewBuilder func sideArt(_ a: TeamArt) -> some View {
        HStack(spacing: 3) {
            if showColors {
                Rectangle()
                    .fill(Color(espnHex: a.color) ?? Theme.rule)
                    .frame(width: 3, height: 13 * s)
            }
            if showLogos, let u = a.logo.flatMap({ URL(string: $0) }) {
                AsyncImage(url: u) { $0.resizable().scaledToFit() } placeholder: { Color.clear }
                    .frame(width: 15 * s, height: 15 * s)
            }
        }
    }

    /// Color strips and small logos for the two teams, in the order they appear in the row.
    @ViewBuilder var teamArt: some View {
        HStack(spacing: 3) {
            if showColors {
                ForEach(Array(row.art.enumerated()), id: \.offset) { _, a in
                    Rectangle()
                        .fill(Color(espnHex: a.color) ?? Theme.rule)
                        .frame(width: 4, height: 14 * s)
                        .overlay(Rectangle().stroke(Theme.rule, lineWidth: 0.5))
                }
            }
            if showLogos {
                ForEach(Array(row.art.enumerated()), id: \.offset) { _, a in
                    if let u = a.logo.flatMap({ URL(string: $0) }) {
                        AsyncImage(url: u) { img in
                            img.resizable().scaledToFit()
                        } placeholder: {
                            Color.clear
                        }
                        .frame(width: 16 * s, height: 16 * s)
                    }
                }
            }
        }
        .alignmentGuide(.firstTextBaseline) { d in d[.bottom] - 3 }
    }
}

// MARK: - Table (rankings & standings)

struct TableData: Identifiable {
    let id = UUID()
    var caption: String
    var headers: [String]      // headers[0] is the rank column, headers[1] the team
    var rows: [[String]]
}

struct AgateTable: View {
    @Environment(\.textScale) private var s
    let table: TableData
    let favorites: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(table.caption)
                .font(.head(15 * s))
                .foregroundStyle(Theme.ink)
            Rule(height: 1)
            Grid(alignment: .trailing, horizontalSpacing: 10, verticalSpacing: 3) {
                GridRow {
                    ForEach(Array(table.headers.enumerated()), id: \.offset) { i, h in
                        Text(h)
                            .font(.sans(9.5 * s, bold: true))
                            .tracking(0.5)
                            .foregroundStyle(Theme.muted)
                            .frame(maxWidth: i == 1 ? CGFloat.infinity : nil, alignment: i == 1 ? .leading : .trailing)
                    }
                }
                Rule(height: 0.5, color: Theme.ink2)
                ForEach(Array(table.rows.enumerated()), id: \.offset) { _, cells in
                    let fav = cells.count > 1 && isFavorite(cells[1], favorites: favorites)
                    GridRow {
                        ForEach(Array(cells.enumerated()), id: \.offset) { i, cell in
                            Text(cell)
                                .font(.line(13 * s, bold: fav))
                                .monospacedDigit()
                                .foregroundStyle(fav ? Theme.accent : (i == 0 ? Theme.muted : Theme.ink))
                                .lineLimit(1)
                                .frame(maxWidth: i == 1 ? CGFloat.infinity : nil, alignment: i == 1 ? .leading : .trailing)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Shared page chrome

struct PageScroll<Content: View>: View {
    private let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) { content }
                .padding(.horizontal, 16)
                .padding(.bottom, 40)
        }
        .background(Theme.paper.ignoresSafeArea())
    }
}

struct StatusLine: View {
    @Environment(\.textScale) private var s
    let text: String
    var body: some View {
        Text(text)
            .font(.sans(11 * s))
            .foregroundStyle(Theme.muted)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 12)
    }
}
