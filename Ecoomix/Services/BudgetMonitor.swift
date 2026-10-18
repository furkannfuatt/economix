import Foundation
import SwiftData
import EcoomixCore

/// Bir gider kaydedildiğinde kategorinin aylık bütçe eşiklerini kontrol eder.
/// Her ay/kategori/eşik için en fazla bir bildirim gider.
@Observable
final class BudgetMonitor {
    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let notifier: Notifier

    init(context: ModelContext, defaults: UserDefaults = .standard, notifier: Notifier = LocalNotifier()) {
        self.context = context
        self.defaults = defaults
        self.notifier = notifier
    }

    @discardableResult
    func check(category: EntryCategory, date: Date, asOf now: Date = .now) -> [Double] {
        guard NotificationPreferences.isEnabled(NotificationPreferences.budgetKey, in: defaults),
              let limit = category.monthlyLimit, limit.minor > 0 else { return [] }
        let month = YearMonth(date: now)
        guard month.contains(date) else { return [] }

        let spent = (category.entries ?? [])
            .filter { $0.kind == .expense && month.contains($0.date) && $0.date <= now }
            .map(\.amount).sum()
        let ratio = spent.ratio(of: limit)

        var fired: [Double] = []
        for threshold in [BudgetEvaluator.warningThreshold, BudgetEvaluator.exceededThreshold] where ratio >= threshold {
            let key = "budget-alert-\(category.id.uuidString)-\(month)-\(Int(threshold * 100))"
            guard !defaults.bool(forKey: key) else { continue }
            defaults.set(true, forKey: key)
            fired.append(threshold)
        }
        guard let highest = fired.last else { return [] }

        let title = highest >= BudgetEvaluator.exceededThreshold
            ? "\(category.name) bütçesi aşıldı"
            : "\(category.name) bütçesinin \(TR.percent(ratio))'i doldu"
        let body = "Bu ay \(spent.formatted(decimals: false)) harcadın; limit \(limit.formatted(decimals: false))."
        notifier.notify(id: "budget-\(category.id.uuidString)-\(month)", title: title, body: body)
        return fired
    }
}
