import Foundation

public enum InsightSeverity: Int, Comparable, Sendable, Codable {
    case info, suggestion, warning, critical

    public static func < (lhs: InsightSeverity, rhs: InsightSeverity) -> Bool { lhs.rawValue < rhs.rawValue }
}

public enum InsightKind: String, Sendable, Codable {
    case budgetPace, categoryIncrease, subscriptions, duplicateSubscriptions,
         installmentLoad, installmentRelief, smallFrequent, savingsRate
}

public struct Insight: Hashable, Sendable, Identifiable, Codable {
    public let id: String
    public let kind: InsightKind
    public let severity: InsightSeverity
    public let title: String
    public let message: String
    public let estimatedMonthlySaving: Money?
    public let categoryID: String?
}

public struct SubscriptionInfo: Hashable, Sendable {
    public let title: String
    public let monthlyAmount: Money
    public let categoryID: String?

    public init(title: String, monthlyAmount: Money, categoryID: String?) {
        self.title = title
        self.monthlyAmount = monthlyAmount
        self.categoryID = categoryID
    }
}

public struct AnalysisInput: Sendable {
    /// Aylık yük modunda (taksitler aylara yayılmış) işlemler.
    public var transactions: [TxSnapshot]
    public var asOf: Date
    public var budgets: [String: Money]
    public var categoryNames: [String: String]
    public var subscriptions: [SubscriptionInfo]
    public var installmentPlans: [PlanSchedule]

    public init(transactions: [TxSnapshot], asOf: Date, budgets: [String: Money], categoryNames: [String: String],
                subscriptions: [SubscriptionInfo], installmentPlans: [PlanSchedule]) {
        self.transactions = transactions
        self.asOf = asOf
        self.budgets = budgets
        self.categoryNames = categoryNames
        self.subscriptions = subscriptions
        self.installmentPlans = installmentPlans
    }
}

/// Öneri eşikleri; tek yerde tutulur.
public enum InsightThresholds {
    public static let categoryIncreaseRatio = 0.25
    public static let categoryIncreaseMinimum = Money(minor: 500_00)
    public static let installmentIncomeRatio = 0.25
    public static let smallExpenseMaximum = Money(minor: 300_00)
    public static let smallExpenseMinimumCount = 10
    public static let savingsRateTarget = 0.20
}

/// Kural tabanlı, çevrimdışı tasarruf önerileri.
public enum SavingsAnalyzer {
    public static func analyze(_ input: AnalysisInput, rule: MonthRule = .calendarMonths) -> [Insight] {
        let context = Context(input: input, rule: rule)
        let insights = budgetPace(context) + categoryIncrease(context) + subscriptionInsights(context)
            + installmentInsights(context) + smallFrequent(context) + savingsRate(context)
        return insights.sorted {
            if $0.severity != $1.severity { return $0.severity > $1.severity }
            return ($0.estimatedMonthlySaving ?? .zero) > ($1.estimatedMonthlySaving ?? .zero)
        }
    }

    private struct Context {
        let input: AnalysisInput
        let rule: MonthRule
        let calendar: Calendar
        let currentMonth: YearMonth
        let lastMonth: YearMonth
        let expenses: [TxSnapshot]

        init(input: AnalysisInput, rule: MonthRule) {
            self.input = input
            self.rule = rule
            calendar = rule.calendar
            currentMonth = rule.month(containing: input.asOf)
            lastMonth = currentMonth.adding(months: -1)
            expenses = input.transactions.filter { $0.kind == .expense && $0.date <= input.asOf }
        }

        func name(_ categoryID: String?) -> String {
            categoryID.flatMap { input.categoryNames[$0] } ?? "Kategorisiz"
        }

        func spent(_ categoryID: String?, in month: YearMonth) -> Money {
            expenses.filter { $0.categoryID == categoryID && rule.period(of: month).contains($0.date) }
                .map(\.amount).sum()
        }

        /// Son 3 tam ayın ortalama geliri.
        var averageIncome: Money {
            let months = (1...3).map { currentMonth.adding(months: -$0) }
            let total = input.transactions
                .filter { tx in tx.kind == .income && months.contains { rule.period(of: $0).contains(tx.date) } }
                .map(\.amount).sum()
            return total.scaled(numerator: 1, denominator: 3)
        }
    }

    // MARK: Kurallar

    private static func budgetPace(_ c: Context) -> [Insight] {
        c.input.budgets.sorted { $0.key < $1.key }.compactMap { categoryID, limit in
            guard limit.minor > 0 else { return nil }
            let spent = c.spent(categoryID, in: c.currentMonth)
            let status = BudgetEvaluator.evaluate(limit: limit, spent: spent, month: c.currentMonth,
                                                  asOf: c.input.asOf, rule: c.rule)
            let name = c.name(categoryID)
            if status.level == .exceeded {
                return Insight(id: "budget-\(categoryID)", kind: .budgetPace, severity: .critical,
                               title: "\(name) bütçesi aşıldı",
                               message: "Bu ay \(spent.formatted()) harcadın; limitin \(limit.formatted()). Ay sonuna kadar bu kategoride harcamayı kısmayı düşün.",
                               estimatedMonthlySaving: spent - limit, categoryID: categoryID)
            }
            guard status.projectedLevel == .exceeded else { return nil }
            let elapsed = c.rule.elapsedDays(in: c.currentMonth, asOf: c.input.asOf)
            let remainingDays = max(c.rule.dayCount(of: c.currentMonth) - elapsed, 1)
            let daily = status.remaining.scaled(numerator: 1, denominator: remainingDays)
            return Insight(id: "budget-\(categoryID)", kind: .budgetPace, severity: .warning,
                           title: "\(name) bütçesi aşılabilir",
                           message: "Bu hızla ay sonunda yaklaşık \(status.projected.formatted(decimals: false)) olacak (limit \(limit.formatted(decimals: false))). Günde \(daily.formatted(decimals: false)) altında kalırsan limit içinde kalırsın.",
                           estimatedMonthlySaving: status.projected - limit, categoryID: categoryID)
        }
    }

    private static func categoryIncrease(_ c: Context) -> [Insight] {
        let previous = (2...4).map { c.currentMonth.adding(months: -$0) }
        let categories = Set(c.expenses.map(\.categoryID))
        return categories.sorted { ($0 ?? "") < ($1 ?? "") }.compactMap { categoryID in
            let last = c.spent(categoryID, in: c.lastMonth)
            let average = previous.map { c.spent(categoryID, in: $0) }.sum().scaled(numerator: 1, denominator: 3)
            guard average.minor > 0 else { return nil }
            let difference = last - average
            let ratio = difference.ratio(of: average)
            guard ratio > InsightThresholds.categoryIncreaseRatio,
                  difference >= InsightThresholds.categoryIncreaseMinimum else { return nil }
            let name = c.name(categoryID)
            return Insight(id: "increase-\(categoryID ?? "none")", kind: .categoryIncrease, severity: .suggestion,
                           title: "\(name) harcaman arttı",
                           message: "\(c.lastMonth.locativeName) \(last.formatted(decimals: false)); önceki 3 ay ortalaması \(average.formatted(decimals: false)) (+\(percent(ratio))). Ortalamaya dönmek ayda \(difference.formatted(decimals: false)) kazandırır.",
                           estimatedMonthlySaving: difference, categoryID: categoryID)
        }
    }

    /// Aynı işi gören servis grupları (normalize edilmiş anahtar kelimeler).
    private static let serviceGroups: [(name: String, keywords: [String])] = [
        ("Video", ["NETFLIX", "PRIME", "DISNEY", "EXXEN", "BLUTV", "GAIN", "MUBI", "TABII", "HBO", "MAX", "TOD"]),
        ("Müzik", ["SPOTIFY", "APPLE MUSIC", "YOUTUBE", "DEEZER", "FIZY"]),
        ("Bulut depolama", ["ICLOUD", "GOOGLE ONE", "DROPBOX", "ONEDRIVE"]),
    ]

    private static func subscriptionInsights(_ c: Context) -> [Insight] {
        let subs = c.input.subscriptions
        guard !subs.isEmpty else { return [] }
        var insights: [Insight] = []

        let total = subs.map(\.monthlyAmount).sum()
        let top = subs.sorted { $0.monthlyAmount > $1.monthlyAmount }.prefix(3)
            .map { "\($0.title) (\($0.monthlyAmount.formatted()))" }.joined(separator: ", ")
        let income = c.averageIncome
        let heavy = income.minor > 0 && total.ratio(of: income) > 0.03
        insights.append(Insight(id: "subscriptions", kind: .subscriptions, severity: heavy ? .suggestion : .info,
                                title: "Abonelikler ayda \(total.formatted(decimals: false))",
                                message: "Aylık \(total.formatted()), yılda \((total * 12).formatted()) ediyor. En pahalılar: \(top). Kullanmadıklarını iptal etmeyi düşün.",
                                estimatedMonthlySaving: nil, categoryID: nil))

        for group in serviceGroups {
            let matches = subs.filter { sub in
                let normalized = " " + MerchantNormalizer.normalize(sub.title) + " "
                return group.keywords.contains { normalized.contains(" \($0) ") }
            }
            guard matches.count >= 2, let cheapest = matches.min(by: { $0.monthlyAmount < $1.monthlyAmount }) else { continue }
            let names = matches.map(\.title)
            insights.append(Insight(id: "duplicate-\(group.name)", kind: .duplicateSubscriptions, severity: .suggestion,
                                    title: "Benzer abonelikler: \(group.name)",
                                    message: "\(names.dropLast().joined(separator: ", ")) ve \(names.last!) aynı ihtiyacı karşılıyor. \(cheapest.title) iptal edilirse ayda \(cheapest.monthlyAmount.formatted()), yılda \((cheapest.monthlyAmount * 12).formatted(decimals: false)) tasarruf edersin.",
                                    estimatedMonthlySaving: cheapest.monthlyAmount, categoryID: cheapest.categoryID))
        }
        return insights
    }

    private static func installmentInsights(_ c: Context) -> [Insight] {
        guard !c.input.installmentPlans.isEmpty else { return [] }
        let outlook = InstallmentScheduler.outlook(plans: c.input.installmentPlans, from: c.currentMonth,
                                                   monthCount: 12, calendar: c.calendar)
        var insights: [Insight] = []
        let load = outlook.months.first?.amount ?? .zero
        let income = c.averageIncome
        if income.minor > 0, load.minor > 0 {
            let ratio = load.ratio(of: income)
            if ratio > InsightThresholds.installmentIncomeRatio {
                insights.append(Insight(id: "installment-load", kind: .installmentLoad, severity: .warning,
                                        title: "Taksit yükün yüksek",
                                        message: "Bu ay taksitlerin \(load.formatted(decimals: false)); bu, ortalama gelirinin \(percent(ratio))'u. Yeni taksitli alımdan önce mevcutların bitmesini beklemek iyi olur.",
                                        estimatedMonthlySaving: nil, categoryID: nil))
            }
        }
        if let relief = outlook.reliefs.first {
            insights.append(Insight(id: "installment-relief", kind: .installmentRelief, severity: .info,
                                    title: "\(relief.month.locativeName) taksit yükün azalıyor",
                                    message: "\(relief.titles.joined(separator: ", ")) bitiyor; aylık \(relief.amount.formatted(decimals: false)) rahatlayacaksın. Bu tutarı birikime yönlendirebilirsin.",
                                    estimatedMonthlySaving: nil, categoryID: nil))
        }
        return insights
    }

    private static func smallFrequent(_ c: Context) -> [Insight] {
        let start = c.calendar.date(byAdding: .day, value: -30, to: c.input.asOf)!
        let small = c.expenses.filter {
            $0.date > start && $0.amount < InsightThresholds.smallExpenseMaximum && $0.installment == nil
        }
        let grouped = Dictionary(grouping: small, by: \.categoryID)
        return grouped.sorted { ($0.key ?? "") < ($1.key ?? "") }.compactMap { categoryID, txs in
            guard txs.count >= InsightThresholds.smallExpenseMinimumCount else { return nil }
            let total = txs.map(\.amount).sum()
            let half = total.scaled(numerator: 1, denominator: 2)
            let name = c.name(categoryID)
            return Insight(id: "small-\(categoryID ?? "none")", kind: .smallFrequent, severity: .suggestion,
                           title: "\(name): sık küçük harcamalar",
                           message: "Son 30 günde \(txs.count) küçük harcama, toplam \(total.formatted(decimals: false)). Yarıya indirmek ayda ~\(half.formatted(decimals: false)), yılda ~\((half * 12).formatted(decimals: false)) kazandırır.",
                           estimatedMonthlySaving: half, categoryID: categoryID)
        }
    }

    private static func savingsRate(_ c: Context) -> [Insight] {
        let summary = ReportBuilder.summary(c.input.transactions, in: c.rule.period(of: c.lastMonth))
        guard let rate = summary.savingsRate else { return [] }
        let when = c.lastMonth.locativeName
        if rate < 0 {
            // Yalnızca gider: yatırım tasarruf sayılır, aşıma eklenmez.
            let overspend = summary.expense - summary.income
            return [Insight(id: "savings-rate", kind: .savingsRate, severity: .critical,
                            title: "Gelirinden fazla harcadın",
                            message: "\(when) giderin gelirini \(overspend.formatted(decimals: false)) aştı. Önce sabit giderleri ve taksitleri gözden geçir.",
                            estimatedMonthlySaving: overspend, categoryID: nil)]
        }
        if rate < InsightThresholds.savingsRateTarget {
            let allowed = summary.income.scaled(numerator: 100 - Int(InsightThresholds.savingsRateTarget * 100),
                                                denominator: 100)
            let gap = summary.expense - allowed
            return [Insight(id: "savings-rate", kind: .savingsRate, severity: .warning,
                            title: "Tasarruf oranın düşük",
                            message: "\(when) gelirinin \(percent(rate))'ini biriktirebildin. \(percent(InsightThresholds.savingsRateTarget)) hedefi için ayda \(gap.formatted(decimals: false)) daha az harcaman gerekiyor.",
                            estimatedMonthlySaving: gap, categoryID: nil)]
        }
        return [Insight(id: "savings-rate", kind: .savingsRate, severity: .info,
                        title: "Tasarruf oranın iyi",
                        message: "\(when) gelirinin \(percent(rate))'ini biriktirdin. Böyle devam!",
                        estimatedMonthlySaving: nil, categoryID: nil)]
    }

    private static func percent(_ ratio: Double) -> String {
        "%" + String(Int((ratio * 100).rounded()))
    }
}
