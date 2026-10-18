import Foundation

public enum ReportMode: String, CaseIterable, Sendable {
    /// Taksitler ödendikleri aylara yayılır (ekstreyle uyumlu).
    case cashFlow
    /// Taksitli alım, alım ayında tek tutar olarak görünür.
    case purchase

    public var title: String {
        switch self {
        case .cashFlow: "Aylık yük"
        case .purchase: "Satın alma"
        }
    }
}

public struct PeriodSummary: Hashable, Sendable {
    public let income: Money
    public let expense: Money
    public let transactionCount: Int

    public var net: Money { income - expense }

    /// (gelir − gider) / gelir. Gelir yoksa nil.
    public var savingsRate: Double? {
        income.isZero ? nil : net.ratio(of: income)
    }
}

public struct CategoryTotal: Hashable, Sendable {
    public let categoryID: String?
    public let amount: Money
    public let count: Int
    public let share: Double
}

public struct MonthlyTotals: Hashable, Sendable {
    public let month: YearMonth
    public let income: Money
    public let expense: Money

    public var net: Money { income - expense }
}

public struct MerchantTotal: Hashable, Sendable {
    public let key: String
    public let name: String
    public let amount: Money
    public let count: Int
}

public enum ReportBuilder {
    /// Rapor moduna göre işlemleri hazırlar. Satın alma modunda her taksit planı tek işleme indirgenir.
    public static func normalized(_ txs: [TxSnapshot], mode: ReportMode) -> [TxSnapshot] {
        guard mode == .purchase else { return txs }
        var seenPlans = Set<String>()
        var result: [TxSnapshot] = []
        for tx in txs {
            guard let ref = tx.installment else {
                result.append(tx)
                continue
            }
            guard seenPlans.insert(ref.planID).inserted else { continue }
            var merged = tx
            merged.id = "plan-\(ref.planID)"
            merged.date = ref.purchaseDate
            merged.amount = ref.planTotal
            result.append(merged)
        }
        return result
    }

    public static func summary(_ txs: [TxSnapshot], in period: DatePeriod) -> PeriodSummary {
        var income = Money.zero, expense = Money.zero, count = 0
        for tx in txs where period.contains(tx.date) {
            switch tx.kind {
            case .income: income += tx.amount
            case .expense: expense += tx.amount
            case .transfer: continue
            }
            count += 1
        }
        return PeriodSummary(income: income, expense: expense, transactionCount: count)
    }

    public static func categoryTotals(_ txs: [TxSnapshot], kind: TxKind, in period: DatePeriod) -> [CategoryTotal] {
        var sums: [String?: (Money, Int)] = [:]
        for tx in txs where tx.kind == kind && period.contains(tx.date) {
            let entry = sums[tx.categoryID] ?? (.zero, 0)
            sums[tx.categoryID] = (entry.0 + tx.amount, entry.1 + 1)
        }
        let total = sums.values.map(\.0).sum()
        return sums
            .map { CategoryTotal(categoryID: $0.key, amount: $0.value.0, count: $0.value.1, share: $0.value.0.ratio(of: total)) }
            .sorted { $0.amount != $1.amount ? $0.amount > $1.amount : ($0.categoryID ?? "") < ($1.categoryID ?? "") }
    }

    public static func monthlyTotals(_ txs: [TxSnapshot], months: [YearMonth],
                                     rule: MonthRule = .calendarMonths) -> [MonthlyTotals] {
        var income: [YearMonth: Money] = [:], expense: [YearMonth: Money] = [:]
        for tx in txs {
            let month = rule.month(containing: tx.date)
            switch tx.kind {
            case .income: income[month, default: .zero] += tx.amount
            case .expense: expense[month, default: .zero] += tx.amount
            case .transfer: continue
            }
        }
        return months.map { MonthlyTotals(month: $0, income: income[$0] ?? .zero, expense: expense[$0] ?? .zero) }
    }

    public static func categoryTrend(_ txs: [TxSnapshot], categoryID: String?, months: [YearMonth],
                                     rule: MonthRule = .calendarMonths) -> [MonthAmount] {
        var sums: [YearMonth: Money] = [:]
        for tx in txs where tx.kind == .expense && tx.categoryID == categoryID {
            sums[rule.month(containing: tx.date), default: .zero] += tx.amount
        }
        return months.map { MonthAmount(month: $0, amount: sums[$0] ?? .zero) }
    }

    public static func topMerchants(_ txs: [TxSnapshot], in period: DatePeriod, limit: Int) -> [MerchantTotal] {
        var sums: [String: (name: String, amount: Money, count: Int)] = [:]
        for tx in txs where tx.kind == .expense && period.contains(tx.date) {
            let key = MerchantNormalizer.normalize(tx.merchant)
            guard !key.isEmpty else { continue }
            let name = tx.merchant.split(separator: " ").joined(separator: " ")
            let entry = sums[key] ?? (name, .zero, 0)
            sums[key] = (entry.name, entry.amount + tx.amount, entry.count + 1)
        }
        return sums
            .map { MerchantTotal(key: $0.key, name: $0.value.name, amount: $0.value.amount, count: $0.value.count) }
            .sorted { $0.amount != $1.amount ? $0.amount > $1.amount : $0.key < $1.key }
            .prefix(limit)
            .map { $0 }
    }
}
