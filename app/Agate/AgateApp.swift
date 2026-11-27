import SwiftUI

@main
struct AgateApp: App {
    @Environment(\.scenePhase) private var phase

    init() {
        FontLoader.registerBundledFonts()
        URLCache.shared = URLCache(memoryCapacity: 30_000_000, diskCapacity: 150_000_000)
        Alerts.registerBackground()
        let bar = UITabBarAppearance()
        bar.configureWithOpaqueBackground()
        bar.backgroundColor = UIColor(Theme.paper)
        bar.shadowColor = UIColor(Theme.ink2)
        UITabBar.appearance().standardAppearance = bar
        UITabBar.appearance().scrollEdgeAppearance = bar
    }

    var body: some Scene {
        WindowGroup { RootView() }
            .onChange(of: phase) { _, new in
                if new == .background { Alerts.scheduleBackground() }
            }
    }
}

struct RootView: View {
    @AppStorage("textScale") private var textScale = 1.0
    @AppStorage("appearance") private var appearance = "system"

    private var scheme: ColorScheme? {
        switch appearance {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    var body: some View {
        TabView {
            ScoresView()
                .tabItem { Label("Scores", systemImage: "newspaper") }
            CalendarHub()
                .tabItem { Label("Don't Miss", systemImage: "bell.badge") }
            StandingsHub()
                .tabItem { Label("Standings", systemImage: "list.number") }
            OlympicsView()
                .tabItem { Label("Olympics", systemImage: "snowflake") }
        }
        .tint(Theme.accent)
        .environment(\.textScale, CGFloat(textScale))
        .preferredColorScheme(scheme)
    }
}
