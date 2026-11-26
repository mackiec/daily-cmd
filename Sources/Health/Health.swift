// Adapted from baa by Selvi Arora (MIT). See NOTICE.
import SwiftUI
import UserNotifications

enum Health {
    case ok, falling, tight, critical
    var word: String { ["healthy", "dropping fast", "getting tight", "critical"][index] }
    var dot: String { ["🟢", "🟠", "🟡", "🔴"][index] }
    var color: Color { [Theme.willow, Theme.persimmon, Theme.ochre, Theme.akabeni][index] }
    private var index: Int { switch self { case .ok: 0; case .falling: 1; case .tight: 2; case .critical: 3 } }

    static func of(free: Int, level: Int, minutesToRed: Double?) -> Health {
        if level >= 4 || free <= Limits.crit { return .critical }
        if free <= Limits.warn { return .tight }   // yellow is only ever your number
        if let m = minutesToRed, m <= 5 { return .falling }
        return .ok
    }
}

// when to go yellow / red, in % free. set from the Mac tab's sliders
enum Limits {
    static var warn: Int { get { read("warnAt", 15) } set { Env.defaults.set(newValue, forKey: "warnAt") } }
    static var crit: Int { get { min(read("critAt", 8), warn - 1) } set { Env.defaults.set(newValue, forKey: "critAt") } }
    static var trend: Bool {
        get { Env.defaults.object(forKey: "trendAlerts") as? Bool ?? true }
        set { Env.defaults.set(newValue, forKey: "trendAlerts") }
    }
    private static func read(_ k: String, _ d: Int) -> Int { Env.defaults.object(forKey: k) as? Int ?? d }
}

final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()
    private var handlers: [String: () -> Void] = [:]
    private var categories: [UNNotificationCategory] = []
    private var allowed = false

    func setup() {
        let c = UNUserNotificationCenter.current()
        c.delegate = self
        c.requestAuthorization(options: [.alert, .sound]) { ok, _ in self.allowed = ok }
    }

    func post(_ title: String, _ subtitle: String, _ body: String, button: String? = nil, action: (() -> Void)? = nil) {
        guard allowed else {
            // no permission: plain notification, no button
            let esc = { (s: String) in s.replacingOccurrences(of: "\"", with: "'") }
            run("/usr/bin/osascript", ["-e", "display notification \"\(esc(body))\" with title \"\(esc(title))\" subtitle \"\(esc(subtitle))\""])
            return
        }
        let c = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = title; content.subtitle = subtitle; content.body = body; content.sound = .default
        if let button, let action {
            // action titles are fixed per category, so each "Free 2.1 GB" button gets its own category
            let id = UUID().uuidString
            categories = Array((categories + [UNNotificationCategory(identifier: id, actions: [UNNotificationAction(identifier: "free", title: button)],
                                                                    intentIdentifiers: [])]).suffix(8))
            c.setNotificationCategories(Set(categories))
            content.categoryIdentifier = id
            handlers[id] = action
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            c.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
    }

    func userNotificationCenter(_ c: UNUserNotificationCenter, didReceive r: UNNotificationResponse, withCompletionHandler done: @escaping () -> Void) {
        if r.actionIdentifier == "free", let h = handlers[r.notification.request.content.categoryIdentifier] { DispatchQueue.main.async(execute: h) }
        done()
    }

    func userNotificationCenter(_ c: UNUserNotificationCenter, willPresent n: UNNotification,
                                withCompletionHandler done: @escaping (UNNotificationPresentationOptions) -> Void) {
        done([.banner, .sound])
    }
}
