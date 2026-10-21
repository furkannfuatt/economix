import Foundation

/// AI analizine gönderilen özet. Ham işlem listesi ve notlar yer almaz; işyeri adları yalnızca izinle eklenir.
public struct AIPayload: Codable, Equatable, Sendable {
    public struct MonthRow: Codable, Equatable, Sendable {
        public let month: String
        public let income: Double
        public let expense: Double
        /// Yatırıma giden net para (alım − bozma; negatifse yatırımdan çekilen). Gider değil, tasarruf sayılır.
        public let investment: Double
        public let savingsRatePercent: Double?
    }

    public struct CategoryRow: Codable, Equatable, Sendable {
        public let name: String
        public let monthlyBudget: Double?
        /// `months` sırasıyla aylık harcama.
        public let amountsByMonth: [Double]
        public let averagePerMonth: Double
    }

    public struct SubscriptionRow: Codable, Equatable, Sendable {
        public let title: String
        public let monthly: Double
    }

    public struct InstallmentRow: Codable, Equatable, Sendable {
        public let month: String
        public let amount: Double
    }

    public struct MerchantRow: Codable, Equatable, Sendable {
        public let name: String
        public let total: Double
        public let count: Int
    }

    public let currency: String
    public let today: String
    /// Cari ay kısmi: dönemin kaçıncı günündeyiz.
    public let currentMonthDay: Int
    /// Aylar her ayın bu gününde başlar (1 = takvim ayı); `month` etiketi dönemin çoğunun düştüğü aydır.
    public let monthStartDay: Int
    public let months: [MonthRow]
    public let categories: [CategoryRow]
    public let subscriptions: [SubscriptionRow]
    public let installmentLoad: [InstallmentRow]
    public let ruleBasedFindings: [String]
    public let topMerchants: [MerchantRow]?
}

public enum AIPayloadBuilder {
    public static let monthCount = 6

    public static func build(from input: AnalysisInput, insights: [Insight], includeMerchants: Bool,
                             rule: MonthRule = .calendarMonths) -> AIPayload {
        let calendar = rule.calendar
        let current = rule.month(containing: input.asOf)
        let months = (0..<monthCount).map { current.adding(months: -(monthCount - 1) + $0) }
        let period = rule.period(of: months.first!...months.last!)
        let txs = input.transactions.filter { $0.date <= input.asOf }

        let monthRows = ReportBuilder.monthlyTotals(txs, months: months, rule: rule).map { totals in
            AIPayload.MonthRow(
                month: totals.month.description,
                income: totals.income.lira,
                expense: totals.expense.lira,
                investment: totals.netInvestment.lira,
                savingsRatePercent: totals.savingsRate.map { ($0 * 100).rounded() }
            )
        }

        let categoryRows = ReportBuilder.categoryTotals(txs, kind: .expense, in: period).map { total in
            let trend = ReportBuilder.categoryTrend(txs, categoryID: total.categoryID, months: months, rule: rule)
            return AIPayload.CategoryRow(
                name: total.categoryID.flatMap { input.categoryNames[$0] } ?? "Kategorisiz",
                monthlyBudget: total.categoryID.flatMap { input.budgets[$0] }?.lira,
                amountsByMonth: trend.map(\.amount.lira),
                averagePerMonth: total.amount.scaled(numerator: 1, denominator: monthCount).lira
            )
        }

        // Taksitler takvim günüyle düşer; yük takvim aylarına göre verilir.
        let outlook = InstallmentScheduler.outlook(plans: input.installmentPlans,
                                                   from: YearMonth(date: input.asOf, calendar: calendar), monthCount: 6,
                                                   calendar: calendar)

        let merchants: [AIPayload.MerchantRow]? = includeMerchants
            ? ReportBuilder.topMerchants(txs, in: period, limit: 15).map {
                AIPayload.MerchantRow(name: $0.name, total: $0.amount.lira, count: $0.count)
            }
            : nil

        let day = calendar.dateComponents([.year, .month, .day], from: input.asOf)
        return AIPayload(
            currency: "TRY",
            today: String(format: "%04d-%02d-%02d", day.year!, day.month!, day.day!),
            currentMonthDay: rule.elapsedDays(in: current, asOf: input.asOf),
            monthStartDay: rule.startDay,
            months: monthRows,
            categories: categoryRows,
            subscriptions: input.subscriptions.map { .init(title: $0.title, monthly: $0.monthlyAmount.lira) },
            installmentLoad: outlook.months.map { .init(month: $0.month.description, amount: $0.amount.lira) },
            ruleBasedFindings: insights.map { insight in
                // Taksit bitişi bulgusu plan adlarını taşır (adı yoksa ekstredeki işyeri adı); işyeri izni yoksa
                // yalnızca başlık gider. Tutarlar zaten `installmentLoad` alanında.
                insight.kind == .installmentRelief && !includeMerchants
                    ? insight.title
                    : "\(insight.title): \(insight.message)"
            },
            topMerchants: merchants
        )
    }
}
