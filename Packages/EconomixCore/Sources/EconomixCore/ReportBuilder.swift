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
    /// Yatırıma ayrılan; gider ve nete dahil değildir.
    public let investment: Money
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
    public let investment: Money

    public var net: Money { income - expense }
}

/// Harcama grafiğinin bir çubuğu: dönem sınırına kırpılmış gün, hafta ya da bütçe ayı.
public struct SpendingBucket: Hashable, Sendable {
    public let period: DatePeriod
    public let amount: Money
    public let count: Int
}

public struct DayAmount: Hashable, Sendable {
    public let day: Date
    public let amount: Money
}

/// Bu dönemin bugüne kadarki harcaması ile önceki dönemin aynı gününe kadarki harcaması.
/// Dönem bittiyse iki dönemin tamamı kıyaslanır (günleri farklı uzunlukta aylar için).
public struct SpendingPace: Hashable, Sendable {
    public let current: Money
    public let previous: Money
    /// Dönem henüz bitmedi; önceki dönemin yalnızca aynı güne kadarki kısmı sayıldı.
    public let isPartial: Bool

    /// `current` ve `previous`: `cumulativeSpending` çıktıları (bu dönem bugüne kadar, önceki dönem tamamı).
    public init?(current: [DayAmount], previous: [DayAmount], periodDays: Int) {
        guard let spent = current.last, !previous.isEmpty else { return nil }
        isPartial = current.count < periodDays
        self.current = spent.amount
        self.previous = isPartial ? previous[min(current.count, previous.count) - 1].amount : previous.last!.amount
    }

    /// Göreli değişim (0,12 = %12 fazla). Önceki dönemde harcama yoksa nil.
    public var change: Double? {
        previous.isZero ? nil : Double(current.minor - previous.minor) / Double(previous.minor)
    }
}

/// Haftanın bir günündeki toplam gider ve o günün dönemde kaç kez geçtiği.
public struct WeekdayAverage: Hashable, Sendable {
    /// 0 = pazartesi … 6 = pazar
    public let index: Int
    public let total: Money
    public let dayCount: Int

    public var average: Money { dayCount == 0 ? .zero : total.scaled(numerator: 1, denominator: dayCount) }

    private static let titles = ["Pazartesi", "Salı", "Çarşamba", "Perşembe", "Cuma", "Cumartesi", "Pazar"]
    private static let shortTitles = ["Pzt", "Sal", "Çar", "Per", "Cum", "Cmt", "Paz"]

    public var title: String { Self.titles[index] }
    public var shortTitle: String { Self.shortTitles[index] }
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
        var income = Money.zero, expense = Money.zero, investment = Money.zero, count = 0
        for tx in txs where period.contains(tx.date) {
            switch tx.kind {
            case .income: income += tx.amount
            case .expense: expense += tx.amount
            case .investment: investment += tx.amount
            case .transfer: continue
            }
            count += 1
        }
        return PeriodSummary(income: income, expense: expense, investment: investment, transactionCount: count)
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

    /// `period` verilirse yalnızca o aralıktaki işlemler sayılır (özel aralığın kenar ayları).
    public static func monthlyTotals(_ txs: [TxSnapshot], months: [YearMonth],
                                     rule: MonthRule = .calendarMonths, in period: DatePeriod? = nil) -> [MonthlyTotals] {
        var income: [YearMonth: Money] = [:], expense: [YearMonth: Money] = [:], investment: [YearMonth: Money] = [:]
        for tx in txs where period?.contains(tx.date) ?? true {
            let month = rule.month(containing: tx.date)
            switch tx.kind {
            case .income: income[month, default: .zero] += tx.amount
            case .expense: expense[month, default: .zero] += tx.amount
            case .investment: investment[month, default: .zero] += tx.amount
            case .transfer: continue
            }
        }
        return months.map {
            MonthlyTotals(month: $0, income: income[$0] ?? .zero, expense: expense[$0] ?? .zero,
                          investment: investment[$0] ?? .zero)
        }
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

    // MARK: Harcama serileri

    /// Dönemdeki giderin gün, hafta (pazartesi başlar) ya da bütçe ayı kovaları. Boş kovalar sıfırdır;
    /// kenar kovalar dönem sınırına kırpılır, böylece toplam `summary(_:in:).expense` ile aynıdır.
    public static func spendingSeries(_ txs: [TxSnapshot], in period: DatePeriod, by granularity: ReportGranularity,
                                      rule: MonthRule = .calendarMonths) -> [SpendingBucket] {
        let starts = bucketStarts(in: period, by: granularity, rule: rule)
        var amounts = Array(repeating: Money.zero, count: starts.count)
        var counts = Array(repeating: 0, count: starts.count)
        for tx in txs where tx.kind == .expense && period.contains(tx.date) {
            guard let index = starts.lastIndex(where: { $0 <= tx.date }) else { continue }
            amounts[index] += tx.amount
            counts[index] += 1
        }
        return starts.indices.map { index in
            let end = index + 1 < starts.count ? starts[index + 1] : period.end
            return SpendingBucket(period: DatePeriod(start: starts[index], end: end), amount: amounts[index], count: counts[index])
        }
    }

    private static func bucketStarts(in period: DatePeriod, by granularity: ReportGranularity, rule: MonthRule) -> [Date] {
        let calendar = rule.calendar
        var starts = [period.start]
        while let last = starts.last {
            let next = switch granularity {
            case .day: calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: last))!
            case .week: calendar.dateInterval(of: .weekOfYear, for: last)!.end
            case .month: rule.end(of: rule.month(containing: last))
            }
            guard next < period.end else { break }
            starts.append(next)
        }
        return starts
    }

    /// Dönemin her günü için o güne kadar biriken gider. `asOf` verilirse o günden sonrası yoktur.
    public static func cumulativeSpending(_ txs: [TxSnapshot], in period: DatePeriod, asOf: Date? = nil,
                                          calendar: Calendar = FinanceCalendar.calendar) -> [DayAmount] {
        let window = asOf.map { period.elapsed(asOf: $0, calendar: calendar) } ?? period
        var running = Money.zero
        return spendingSeries(txs, in: window, by: .day, rule: MonthRule(calendar: calendar)).map {
            running += $0.amount
            return DayAmount(day: $0.period.start, amount: running)
        }
    }

    /// Pazartesiden pazara her gün için toplam gider ve dönemde (`asOf` gününe kadar) kaç kez geçtiği.
    public static func weekdayAverages(_ txs: [TxSnapshot], in period: DatePeriod, asOf: Date? = nil,
                                       calendar: Calendar = FinanceCalendar.calendar) -> [WeekdayAverage] {
        let window = asOf.map { period.elapsed(asOf: $0, calendar: calendar) } ?? period
        // Calendar.weekday: 1 = pazar … 7 = cumartesi → 0 = pazartesi … 6 = pazar
        func index(_ date: Date) -> Int { (calendar.component(.weekday, from: date) + 5) % 7 }
        var totals = Array(repeating: Money.zero, count: 7)
        var days = Array(repeating: 0, count: 7)
        for day in window.days(calendar: calendar) { days[index(day)] += 1 }
        for tx in txs where tx.kind == .expense && window.contains(tx.date) { totals[index(tx.date)] += tx.amount }
        return (0..<7).map { WeekdayAverage(index: $0, total: totals[$0], dayCount: days[$0]) }
    }
}
