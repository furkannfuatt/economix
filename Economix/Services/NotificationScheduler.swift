import Foundation
import UserNotifications
import EconomixCore

protocol Notifier {
    func notify(id: String, title: String, body: String)
}

/// Anında yerel bildirim gönderir.
struct LocalNotifier: Notifier {
    func notify(id: String, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

enum NotificationPreferences {
    static let budgetKey = "notify.budget"
    static let cardKey = "notify.cardDue"
    static let subscriptionKey = "notify.subscription"
    static let monthlyKey = "notify.monthlySummary"

    /// Varsayılan açık.
    static func isEnabled(_ key: String, in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: key) as? Bool ?? true
    }
}

/// Uygulama açıkken de bildirimin banner olarak görünmesini sağlar (bütçe uyarıları kayıt anında gelir).
final class NotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationPresenter()

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification)
        async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }
}

/// Kart son ödeme, abonelik yenileme ve aylık özet hatırlatmalarını planlar.
enum NotificationScheduler {
    private static let prefix = "reminder-"

    static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// Bekleyen hatırlatmaları silip baştan kurar. Açılışta ve veri değişince çağrılır.
    static func reschedule(cards: [Account], recurring: [RecurringItem], transactions: [TxSnapshot],
                           now: Date = .now) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(prefix) })

        let calendar = FinanceCalendar.calendar
        var requests: [(id: String, date: Date, title: String, body: String)] = []

        if NotificationPreferences.isEnabled(NotificationPreferences.cardKey) {
            for card in cards where card.isCreditCard && !card.isArchived {
                let summary = CardLedger.summary(cardID: card.id.uuidString, cycle: card.cycle,
                                                 transactions: transactions, asOf: now)
                guard summary.remainingDue.minor > 0 else { continue }
                let due = summary.lastStatement.dueDate
                let remind = at9(calendar.date(byAdding: .day, value: -2, to: due)!, calendar)
                requests.append(("\(prefix)card-\(card.id)", remind, "\(card.name) son ödeme \(TR.dayMonth(due))",
                                 "Ödenecek tutar \(summary.remainingDue.formatted()). Gecikme faizinden kaçınmak için unutma."))
            }
        }

        if NotificationPreferences.isEnabled(NotificationPreferences.subscriptionKey) {
            for item in recurring where item.isActive && item.isSubscription {
                guard let next = item.nextDate(after: now) else { continue }
                let remind = at9(calendar.date(byAdding: .day, value: -1, to: next)!, calendar)
                requests.append(("\(prefix)sub-\(item.id)", remind, "Yarın \(item.title) yenileniyor",
                                 "\(item.amount.formatted()) çekilecek. Kullanmıyorsan iptal etmenin tam zamanı."))
            }
        }

        if NotificationPreferences.isEnabled(NotificationPreferences.monthlyKey) {
            // Bütçe ayı bitince, yeni dönemin ilk günü 10:00'da.
            let rule = MonthSettings.rule()
            let current = rule.month(containing: now)
            let nextMonth = current.adding(months: 1)
            let date = calendar.date(byAdding: .hour, value: 10, to: rule.start(of: nextMonth))!
            requests.append(("\(prefix)monthly-\(nextMonth)", date, "\(current.monthName) özeti hazır",
                             "Geçen ay ne harcadığına ve önerilere göz at."))
        }

        for request in requests where request.date > now {
            let content = UNMutableNotificationContent()
            content.title = request.title
            content.body = request.body
            content.sound = .default
            let components = calendar.dateComponents(in: calendar.timeZone, from: request.date)
            let trigger = UNCalendarNotificationTrigger(
                dateMatching: DateComponents(year: components.year, month: components.month, day: components.day,
                                             hour: components.hour, minute: components.minute),
                repeats: false)
            try? await center.add(UNNotificationRequest(identifier: request.id, content: content, trigger: trigger))
        }
    }

    private static func at9(_ date: Date, _ calendar: Calendar) -> Date {
        calendar.date(bySettingHour: 9, minute: 0, second: 0, of: date) ?? date
    }
}
