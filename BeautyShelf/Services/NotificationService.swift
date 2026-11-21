import Foundation
import UserNotifications

enum SettingsKey {
    static let onboarded = "hasOnboarded"
    static let notifyExpiry = "notifyExpiry"
    static let notifyLowStock = "notifyLowStock"
    static let notifyEvening = "notifyEvening"
}

/// 本地通知：
/// - 实际过期日前 30 天、7 天各一次（10:00）
/// - 剩余 < 15% 时提醒补货（当天或次日 20:00，只提醒一次）
/// - 每晚 21:30 晚间流程提醒（可关）
/// 每次重排都会先清掉本 App 之前排的所有提醒，再按当前数据重新排。
enum NotificationService {
    private static let prefix = "bs."
    private static let eveningID = "bs.evening"
    /// iOS 最多保留 64 条待发通知
    private static let limit = 60

    static var expiryOn: Bool { UserDefaults.standard.object(forKey: SettingsKey.notifyExpiry) as? Bool ?? true }
    static var lowStockOn: Bool { UserDefaults.standard.object(forKey: SettingsKey.notifyLowStock) as? Bool ?? true }
    static var eveningOn: Bool { UserDefaults.standard.object(forKey: SettingsKey.notifyEvening) as? Bool ?? false }

    static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// 未决定时弹出系统授权；已拒绝返回 false
    @discardableResult
    static func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        switch await center.notificationSettings().authorizationStatus {
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        case .denied:
            return false
        default:
            return true
        }
    }

    static func reschedule(products: [Product]) {
        let cal = Calendar.current
        let now = Date.now
        let active = products.filter { !$0.isFinished }
        var timed: [(date: Date, request: UNNotificationRequest)] = []

        if expiryOn {
            for p in active {
                let eff = p.effectiveExpiry
                for days in [30, 7] {
                    guard let day = cal.date(byAdding: .day, value: -days, to: eff),
                          let fire = cal.date(bySettingHour: 10, minute: 0, second: 0, of: day),
                          fire > now else { continue }
                    let content = UNMutableNotificationContent()
                    content.title = "「\(p.name)」还有 \(days) 天过期"
                    content.body = "\(Fmt.day(eff)) 过期（\(p.expiryBasis.text)），记得先用掉它。"
                    content.sound = .default
                    timed.append((date: fire, request: request(id: "\(prefix)exp\(days).\(p.uid.uuidString)", content: content, at: fire)))
                }
            }
        }

        for p in active {
            guard p.isLow else {
                p.lowStockAlertAt = nil
                continue
            }
            if p.lowStockAlertAt == nil { p.lowStockAlertAt = nextEvening(after: now) }
            guard lowStockOn, let at = p.lowStockAlertAt, at > now else { continue }
            let content = UNMutableNotificationContent()
            content.title = "「\(p.name)」快用完了"
            content.body = "只\(p.remainingText)，要不要加入补货清单？"
            content.sound = .default
            timed.append((date: at, request: request(id: "\(prefix)low.\(p.uid.uuidString)", content: content, at: at)))
        }

        var requests = timed.sorted { $0.date < $1.date }.prefix(limit).map { $0.request }

        if eveningOn {
            let count = active.filter { $0.inEvening }.count
            let content = UNMutableNotificationContent()
            content.title = "晚间护肤时间"
            content.body = count > 0 ? "晚间流程 \(count) 件，点一下就记好了。" : "今天辛苦了，打开妆台记一下晚间护肤吧。"
            content.sound = .default
            var comps = DateComponents()
            comps.hour = 21
            comps.minute = 30
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
            requests.append(UNNotificationRequest(identifier: eveningID, content: content, trigger: trigger))
        }

        let toAdd = requests
        Task {
            let center = UNUserNotificationCenter.current()
            let pending = await center.pendingNotificationRequests()
            let ours = pending.map { $0.identifier }.filter { $0.hasPrefix(prefix) }
            center.removePendingNotificationRequests(withIdentifiers: ours)
            guard !toAdd.isEmpty else { return }
            guard await requestAuthorization() else { return }
            for r in toAdd {
                try? await center.add(r)
            }
        }
    }

    private static func request(id: String, content: UNNotificationContent, at date: Date) -> UNNotificationRequest {
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        return UNNotificationRequest(identifier: id, content: content, trigger: trigger)
    }

    /// 今天 20:00（已过则明天 20:00）
    private static func nextEvening(after date: Date) -> Date {
        let cal = Calendar.current
        let today = cal.date(bySettingHour: 20, minute: 0, second: 0, of: date) ?? date
        if today > date.addingTimeInterval(5 * 60) { return today }
        return cal.date(byAdding: .day, value: 1, to: today) ?? today
    }
}

/// App 在前台时也展示横幅
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
