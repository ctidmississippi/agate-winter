import SwiftUI
import MapKit

/// LA28 venues on a map, with the sports held at each. Coordinates are approximate.
struct LA28Venue: Identifiable {
    let id = UUID()
    let name: String
    let lat: Double
    let lon: Double
    let sports: [String]
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lon) }
}

enum LA28Venues {
    static let all: [LA28Venue] = [
        LA28Venue(name: "LA Memorial Coliseum", lat: 34.0141, lon: -118.2879, sports: ["Athletics"]),
        LA28Venue(name: "SoFi Stadium (2028 Stadium)", lat: 33.9535, lon: -118.3392, sports: ["Swimming"]),
        LA28Venue(name: "Dignity Health Sports Park, Carson", lat: 33.8644, lon: -118.2610,
                  sports: ["Archery", "Rugby sevens", "Tennis (Tennis Center)", "Track cycling (VELO)", "Field hockey (Galaxy Park)"]),
        LA28Venue(name: "Los Angeles Convention Center", lat: 34.0403, lon: -118.2696,
                  sports: ["Fencing", "Judo", "Table tennis", "Taekwondo", "Wrestling"]),
        LA28Venue(name: "Galen Center", lat: 34.0224, lon: -118.2851, sports: ["Badminton", "Rhythmic gymnastics"]),
        LA28Venue(name: "Dodger Stadium", lat: 34.0739, lon: -118.2400, sports: ["Baseball"]),
        LA28Venue(name: "Honda Center, Anaheim", lat: 33.8078, lon: -117.8765, sports: ["Indoor volleyball"]),
        LA28Venue(name: "Santa Anita Park, Arcadia", lat: 34.1396, lon: -118.0453, sports: ["Equestrian"]),
        LA28Venue(name: "Venice Beach", lat: 33.9850, lon: -118.4695, sports: ["Triathlon"]),
        LA28Venue(name: "Universal Studios Lot", lat: 34.1381, lon: -118.3534, sports: ["Squash"]),
        LA28Venue(name: "Fairgrounds, Pomona", lat: 34.0870, lon: -117.7690, sports: ["Cricket"]),
        LA28Venue(name: "Sepulveda Basin", lat: 34.1740, lon: -118.4800, sports: ["3x3 basketball", "Modern pentathlon"]),
        LA28Venue(name: "Marine Stadium, Long Beach", lat: 33.7690, lon: -118.1180, sports: ["Rowing", "Canoe sprint"]),
        LA28Venue(name: "Long Beach waterfront", lat: 33.7600, lon: -118.1900, sports: ["Handball", "Coastal rowing", "Marathon swimming (confirm)"]),
        LA28Venue(name: "Alamitos Beach, Long Beach", lat: 33.7638, lon: -118.1760, sports: ["Beach volleyball"]),
        LA28Venue(name: "Belmont Shore, Long Beach", lat: 33.7580, lon: -118.1250, sports: ["Sailing"]),
        LA28Venue(name: "San Clemente", lat: 33.4269, lon: -117.6120, sports: ["Surfing"]),
    ]
    /// Outside the Los Angeles area.
    static let away: [(String, [String])] = [
        ("Oklahoma City", ["Softball", "Canoe slalom"]),
    ]
}

struct LA28MapView: View {
    @Environment(\.textScale) private var s
    @State private var selected: UUID?
    @State private var camera = MapCameraPosition.region(
        MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 33.95, longitude: -118.2),
                           span: MKCoordinateSpan(latitudeDelta: 0.8, longitudeDelta: 0.9)))

    private var chosen: LA28Venue? { LA28Venues.all.first { $0.id == selected } }

    var body: some View {
        PageScroll {
            Masthead(title: "LA28 Venues", motto: "“Where each sport will be held.”")
            Rule(height: 1)
            Map(position: $camera, selection: $selected) {
                ForEach(LA28Venues.all) { v in
                    Marker(v.name, coordinate: v.coordinate).tag(v.id)
                }
            }
            .frame(height: 320)
            .overlay(Rectangle().stroke(Theme.rule, lineWidth: 1))
            .padding(.vertical, 8)

            if let v = chosen {
                Text(v.name).font(.head(16 * s, black: true)).foregroundStyle(Theme.ink)
                Text(v.sports.joined(separator: " · ")).font(.line(13 * s)).foregroundStyle(Theme.ink2)
                    .padding(.bottom, 6)
            }

            SportHeader(title: "By venue")
            ForEach(LA28Venues.all) { v in
                VStack(alignment: .leading, spacing: 1) {
                    Text(v.name).font(.line(14 * s, bold: true)).foregroundStyle(Theme.ink)
                    Text(v.sports.joined(separator: " · ")).font(.line(12 * s)).foregroundStyle(Theme.muted)
                }
                .padding(.vertical, 3)
                .overlay(alignment: .bottom) { Rule(height: 0.5, color: Theme.rule) }
                .onTapGesture {
                    selected = v.id
                    withAnimation {
                        camera = .region(MKCoordinateRegion(center: v.coordinate,
                                                            span: MKCoordinateSpan(latitudeDelta: 0.12, longitudeDelta: 0.12)))
                    }
                }
            }
            ForEach(LA28Venues.away, id: \.0) { place, sports in
                VStack(alignment: .leading, spacing: 1) {
                    Text(place + " (outside Los Angeles)").font(.line(14 * s, bold: true)).foregroundStyle(Theme.ink)
                    Text(sports.joined(separator: " · ")).font(.line(12 * s)).foregroundStyle(Theme.muted)
                }
                .padding(.vertical, 3)
            }
            StatusLine(text: "Venues as listed in the Summer tab's LA28 plan. Pins are approximate. Sports not shown have no venue compiled yet.")
        }
    }
}
