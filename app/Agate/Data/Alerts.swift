import Foundation
import UserNotifications
import BackgroundTasks

/// Close-game alerts and the nightly summary, sent as local notifications.
/// With a free Apple ID there is no push, so these fire when the app refreshes: every 45 seconds while it is
/// open, and at the times iOS grants a background refresh (roughly every 15 minutes or more, not guaranteed).
enum Alerts {
    static let taskID = "com.nicholas.agate.refresh"

    static var closeEnabled: Bool { UserDefaults.standard.bool(forKey: "alertClose") }
    static var nightlyEnabled: Bool { UserDefaults.standard.bool(forKey: "alertNightly") }

    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    // MARK: Processing a fresh scoreboard

    @MainActor static func process(groups: [GroupSection]) {
        if closeEnabled { notifyClose(groups) }
        if nightlyEnabled { notifyNightly(groups) }
    }

    private static func dayKey() -> String { ESPNClient.ymd(Date()) }

    private static func seen() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: "alertSeen-\(dayKey())") ?? [])
    }
    private static func remember(_ id: String) {
        var s = seen(); s.insert(id)
        UserDefaults.standard.set(Array(s), forKey: "alertSeen-\(dayKey())")
    }

    @MainActor private static func notifyClose(_ groups: [GroupSection]) {
        for g in groups {
            for b in g.blocks {
                for r in b.rows where r.close {
                    let id = "close-" + (r.game?.eventID ?? r.left)
                    if seen().contains(id) { continue }
                    remember(id)
                    post(title: "Close game · \(b.title)", body: "\(r.left) — \(r.right)", id: id)
                }
            }
        }
    }

    /// After 10 p.m., once a day: the finals and the top stories.
    @MainActor private static func notifyNightly(_ groups: [GroupSection]) {
        let hour = Calendar.current.component(.hour, from: Date())
        guard hour >= 22 else { return }
        let id = "nightly"
        if seen().contains(id) { return }
        var finals = 0
        var stories: [Story] = []
        for g in groups { for b in g.blocks { for r in b.rows {
            if r.kind == .line && r.game != nil { finals += 1 }
            if let s = r.story { stories.append(s) }
        } } }
        guard finals > 0 else { return }
        remember(id)
        let top = stories.sorted { $0.weight > $1.weight }.prefix(3).map { $0.headline }
        post(title: "Tonight: \(finals) finals", body: top.joined(separator: "\n"), id: id)
    }

    private static func post(title: String, body: String, id: String) {
        let c = UNMutableNotificationContent()
        c.title = title
        c.body = body
        c.sound = .default
        let req = UNNotificationRequest(identifier: id, content: c, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }

    // MARK: Background refresh

    /// Only registers when the identifier is listed in the target's Info (see README), so a missing setting
    /// can't crash the app at launch.
    static func registerBackground() {
        let ids = Bundle.main.object(forInfoDictionaryKey: "BGTaskSchedulerPermittedIdentifiers") as? [String] ?? []
        guard ids.contains(taskID) else { return }
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskID, using: nil) { task in
            guard let task = task as? BGAppRefreshTask else { task.setTaskCompleted(success: false); return }
            scheduleBackground()
            let work = Task { @MainActor in
                let enabled = Catalog.all.filter {
                    !DisabledLeagues.set(from: UserDefaults.standard.string(forKey: "disabledLeagues") ?? "").contains($0.id)
                }
                let store = ScoresStore()
                await store.load(date: Date(), leagues: enabled)
                process(groups: store.groups)
                task.setTaskCompleted(success: true)
            }
            task.expirationHandler = { work.cancel() }
        }
    }

    static func scheduleBackground() {
        let ids = Bundle.main.object(forInfoDictionaryKey: "BGTaskSchedulerPermittedIdentifiers") as? [String] ?? []
        guard ids.contains(taskID), closeEnabled || nightlyEnabled else { return }
        let req = BGAppRefreshTaskRequest(identifier: taskID)
        req.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(req)
    }
}
