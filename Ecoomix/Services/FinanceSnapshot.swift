import Foundation
import EcoomixCore

/// Ekranların ortak hesap girdisi: SwiftData nesnelerinin Core değer tiplerine çevrilmiş hâli.
struct FinanceSnapshot {
    let transactions: [TxSnapshot]
    let categories: [EntryCategory]
    let plans: [InstallmentPlan]
    let recurring: [RecurringItem]

    init(entries: [LedgerEntry], categories: [EntryCategory], plans: [InstallmentPlan], recurring: [RecurringItem]) {
        self.transactions = entries.map(\.snapshot)
        self.categories = categories
        self.plans = plans
        self.recurring = recurring
    }

    var categoryNames: [String: String] {
        Dictionary(categories.map { ($0.id.uuidString, $0.name) }, uniquingKeysWith: { first, _ in first })
    }

    var budgets: [String: Money] {
        Dictionary(categories.compactMap { c in c.monthlyLimit.map { (c.id.uuidString, $0) } },
                   uniquingKeysWith: { first, _ in first })
    }

    var subscriptions: [SubscriptionInfo] {
        recurring.filter { $0.isActive && $0.isSubscription && $0.kind == .expense }.map {
            SubscriptionInfo(title: $0.title, monthlyAmount: $0.monthlyEquivalent, categoryID: $0.category?.id.uuidString)
        }
    }

    var planSchedules: [PlanSchedule] {
        plans.map { PlanSchedule(id: $0.id.uuidString, title: $0.displayTitle, lines: $0.lines) }
    }

    func category(id: String?) -> EntryCategory? {
        guard let id else { return nil }
        return categories.first { $0.id.uuidString == id }
    }

    func insights(asOf date: Date = .now, rule: MonthRule = MonthSettings.rule()) -> [Insight] {
        SavingsAnalyzer.analyze(AnalysisInput(transactions: transactions, asOf: date, budgets: budgets,
                                              categoryNames: categoryNames, subscriptions: subscriptions,
                                              installmentPlans: planSchedules), rule: rule)
    }
}

/// Özet ekranındaki "yaklaşan ödemeler" satırı.
struct UpcomingPayment: Identifiable {
    let id: String
    let date: Date
    let title: String
    let subtitle: String
    let amount: Money
    let icon: String
    let colorHex: String

    static func collect(cards: [Account], recurring: [RecurringItem], transactions: [TxSnapshot],
                        asOf date: Date = .now, days: Int = 30) -> [UpcomingPayment] {
        let calendar = FinanceCalendar.calendar
        let today = calendar.startOfDay(for: date)
        let horizon = calendar.date(byAdding: .day, value: days, to: today)!
        var items: [UpcomingPayment] = []

        for card in cards where card.isCreditCard {
            let summary = CardLedger.summary(cardID: card.id.uuidString, cycle: card.cycle,
                                             transactions: transactions, asOf: date)
            if summary.remainingDue.minor > 0, summary.lastStatement.dueDate >= today {
                items.append(UpcomingPayment(id: "card-\(card.id)", date: summary.lastStatement.dueDate,
                                             title: card.name, subtitle: "Ekstre son ödeme",
                                             amount: summary.remainingDue, icon: "creditcard.fill",
                                             colorHex: card.colorHex))
            }
            let next = summary.openStatement
            if summary.openPeriodSpending.minor > 0, next.dueDate <= horizon {
                items.append(UpcomingPayment(id: "card-next-\(card.id)", date: next.dueDate, title: card.name,
                                             subtitle: "Sonraki ekstre (tahmini)", amount: summary.openPeriodSpending,
                                             icon: "creditcard", colorHex: card.colorHex))
            }
        }

        for item in recurring where item.isActive && item.kind == .expense {
            guard let next = item.nextDate(after: date), next <= horizon else { continue }
            items.append(UpcomingPayment(id: "rec-\(item.id)", date: next, title: item.title,
                                         subtitle: item.account.map { "\(item.frequency.title) · \($0.name)" } ?? item.frequency.title,
                                         amount: item.amount, icon: item.category?.icon ?? "repeat",
                                         colorHex: item.category?.colorHex ?? "#8E8E93"))
        }
        return items.sorted { $0.date < $1.date }
    }
}
