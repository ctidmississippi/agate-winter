import SwiftUI

/// The shareable "newspaper clipping". Fixed light colors so it looks the same in either mode.
struct ShareCard: View {
    let content: GameDetailContent
    let leagueTitle: String

    private var scoring: [Row] {
        (content.sections.first { $0.id == "scoring" }?.rows ?? []).prefix(8).map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("The Agate Page")
                .font(.nameplate(36))
                .foregroundStyle(Theme.Light.ink)
                .frame(maxWidth: .infinity)
            Rectangle().fill(Theme.Light.ink).frame(height: 1)
            Text(leagueTitle.uppercased())
                .font(.sans(10, bold: true))
                .tracking(0.8)
                .foregroundStyle(Theme.Light.muted)
                .padding(.top, 4)
            Text(content.title)
                .font(.head(19, black: true))
                .foregroundStyle(Theme.Light.ink)
            Text(content.status)
                .font(.sans(11.5))
                .foregroundStyle(Theme.Light.muted)

            if let t = content.lineScore {
                VStack(spacing: 2) {
                    line(t.headers.dropFirst().map { $0 }, bold: true, muted: true)
                    Rectangle().fill(Theme.Light.rule).frame(height: 1)
                    ForEach(Array(t.rows.enumerated()), id: \.offset) { _, r in
                        line(r.dropFirst().map { $0 }, bold: false, muted: false)
                    }
                }
                .padding(.top, 6)
            }

            if !scoring.isEmpty {
                Text("SCORING")
                    .font(.sans(10, bold: true))
                    .tracking(0.8)
                    .foregroundStyle(Theme.Light.muted)
                    .padding(.top, 8)
                ForEach(scoring) { r in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(r.left).font(.line(11.5)).foregroundStyle(Theme.Light.ink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(r.right).font(.line(11.5, bold: true)).foregroundStyle(Theme.Light.accent)
                    }
                }
            }

            Rectangle().fill(Theme.Light.ink).frame(height: 1).padding(.top, 8)
            Text("Every final, every standing, every line.")
                .font(.sans(10))
                .italic()
                .foregroundStyle(Theme.Light.muted)
                .frame(maxWidth: .infinity)
        }
        .padding(18)
        .frame(width: 380)
        .background(Theme.Light.paper)
    }

    /// First cell is the team (left), the rest are right-aligned numbers.
    private func line(_ cells: [String], bold: Bool, muted: Bool) -> some View {
        HStack(spacing: 8) {
            ForEach(Array(cells.enumerated()), id: \.offset) { i, c in
                Text(c)
                    .font(.line(12.5, bold: bold || i == cells.count - 1))
                    .foregroundStyle(muted ? Theme.Light.muted : Theme.Light.ink)
                    .frame(maxWidth: i == 0 ? CGFloat.infinity : nil, alignment: i == 0 ? .leading : .trailing)
                    .frame(minWidth: i == 0 ? nil : 22, alignment: .trailing)
            }
        }
    }
}
