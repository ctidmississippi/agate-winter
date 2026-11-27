import SwiftUI

struct SettingsView: View {
    @AppStorage("dataSaver") private var dataSaver = false
    @AppStorage("disabledLeagues") private var disabledRaw = ""
    @AppStorage("textScale") private var textScale = 1.0
    @AppStorage("winterURL") private var winterURL = ""
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("summerURL") private var summerURL = ""
    @AppStorage("showTeamColors") private var showTeamColors = true
    @AppStorage("showLogos") private var showLogos = true
    @AppStorage("alertClose") private var alertClose = false
    @AppStorage("alertNightly") private var alertNightly = false
    @AppStorage(Reminders.autoKey) private var radarAuto = true
    @AppStorage(SportInterest.key) private var interestRaw = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://… (optional)", text: $winterURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                } header: {
                    Text("Winter data URL")
                } footer: {
                    Text("Leave blank to use the winter data built into the app. If you host winter.json somewhere, paste its address here and the Winter tab will update without reinstalling.")
                }

                Section {
                    TextField("https://… (optional)", text: $summerURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                } header: {
                    Text("Summer data URL")
                } footer: {
                    Text("Same idea as Winter: paste the address of a hosted summer.json, or leave blank to use the data built into the app.")
                }

                Section("Appearance") {
                    Picker("Appearance", selection: $appearance) {
                        Text("Match system").tag("system")
                        Text("Light").tag("light")
                        Text("Dark").tag("dark")
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    Toggle("Data saver", isOn: $dataSaver)
                } header: {
                    Text("Data")
                } footer: {
                    Text("Live games refresh every 2 minutes instead of 45 seconds. Only leagues with a game in progress are reloaded either way, and team logos are saved on the phone after the first load.")
                }

                Section("Score rows") {
                    Toggle("Team color strips", isOn: $showTeamColors)
                    Toggle("Team logos", isOn: $showLogos)
                }

                Section {
                    Toggle("Close-game alerts", isOn: $alertClose)
                    Toggle("Remind me of big events", isOn: $radarAuto)
                    Toggle("Nightly summary (after 10 p.m.)", isOn: $alertNightly)
                } header: {
                    Text("Notifications")
                } footer: {
                    Text("These are checked when the app refreshes: every 45 seconds while it is open, and when iOS allows a background refresh. Without a paid developer account there are no push alerts, so they can arrive late or not at all while the app is closed.")
                }
                .onChange(of: alertClose) { _, on in if on { Alerts.requestAuthorization() } }
                .onChange(of: alertNightly) { _, on in if on { Alerts.requestAuthorization() } }
                .onChange(of: radarAuto) { _, on in if on { Alerts.requestAuthorization() } }

                if !SportInterest.knownSports().isEmpty {
                    Section {
                        ForEach(SportInterest.knownSports(), id: \.self) { sport in
                            Picker(sport, selection: interestBinding(sport)) {
                                Text("Big only").tag("big")
                                Text("Everything").tag("all")
                                Text("Hide").tag("off")
                            }
                        }
                    } header: {
                        Text("Don't Miss by sport")
                    } footer: {
                        Text("Big only reminds you of the major events. Everything reminds you of each event in that sport. Hide removes the sport from Don't Miss.")
                    }
                }

                Section("Text size") {
                    Slider(value: $textScale, in: 0.8...1.5, step: 0.05)
                    Text("The quick brown fox, 31–27 Final")
                        .font(.line(14 * textScale))
                }

                ForEach(groupTitles, id: \.self) { title in
                    Section(title) {
                        ForEach(Catalog.all.filter { $0.group == title }) { league in
                            Toggle(league.title, isOn: binding(for: league))
                        }
                    }
                }

                Section {
                    Text("Scores, standings and box scores come from ESPN's public feeds. They're unofficial and can change without notice, so some entries may occasionally be missing.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .tint(Theme.accent)
            .navigationTitle("Settings")
        }
    }

    private func interestBinding(_ sport: String) -> Binding<String> {
        Binding(
            get: { SportInterest.level(sport, raw: interestRaw) },
            set: { v in
                var d = SportInterest.dict(interestRaw)
                d[sport] = v
                interestRaw = SportInterest.raw(d)
                Alerts.requestAuthorization()
            }
        )
    }

    private var groupTitles: [String] {
        var seen = Set<String>()
        return Catalog.all.map(\.group).filter { seen.insert($0).inserted }
    }

    private func binding(for league: League) -> Binding<Bool> {
        Binding(
            get: { !DisabledLeagues.set(from: disabledRaw).contains(league.id) },
            set: { on in
                var off = DisabledLeagues.set(from: disabledRaw)
                if on { off.remove(league.id) } else { off.insert(league.id) }
                disabledRaw = DisabledLeagues.raw(from: off)
            }
        )
    }
}
