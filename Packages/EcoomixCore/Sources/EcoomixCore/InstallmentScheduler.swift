import Foundation

public struct InstallmentLine: Hashable, Sendable {
    /// 1'den başlar.
    public let index: Int
    public let date: Date
    public let amount: Money

    public init(index: Int, date: Date, amount: Money) {
        self.index = index
        self.date = date
        self.amount = amount
    }
}

public struct InstallmentProgress: Hashable, Sendable {
    public let paidCount: Int
    public let remainingCount: Int
    public let paidAmount: Money
    public let remainingAmount: Money
    public let nextLine: InstallmentLine?
    public let lastMonth: YearMonth?

    public var totalCount: Int { paidCount + remainingCount }
    public var isFinished: Bool { remainingCount == 0 }
}

/// Bir taksit planının takvimi (görünüm hesapları için).
public struct PlanSchedule: Hashable, Sendable {
    public let id: String
    public let title: String
    public let lines: [InstallmentLine]

    public init(id: String, title: String, lines: [InstallmentLine]) {
        self.id = id
        self.title = title
        self.lines = lines
    }
}

public struct MonthAmount: Hashable, Sendable {
    public let month: YearMonth
    public let amount: Money

    public init(month: YearMonth, amount: Money) {
        self.month = month
        self.amount = amount
    }
}

/// Bir ayda biten taksitler sayesinde aylık yükün ne kadar azalacağı.
public struct InstallmentRelief: Hashable, Sendable {
    public let month: YearMonth
    public let amount: Money
    public let titles: [String]
}

public struct InstallmentOutlook: Hashable, Sendable {
    public let months: [MonthAmount]
    public let reliefs: [InstallmentRelief]
}

public enum InstallmentScheduler {
    /// Taksitler: ilki alım tarihinde, sonrakiler her ay aynı günde (kısa aylarda son gün).
    public static func schedule(total: Money, count: Int, purchaseDate: Date,
                                calendar: Calendar = FinanceCalendar.calendar) -> [InstallmentLine] {
        let amounts = total.split(into: max(count, 1))
        return amounts.enumerated().map { offset, amount in
            // Her taksit alım tarihinden hesaplanır; zincirleme eklemede 31 → 28 → 28 kayması olur.
            let date = calendar.date(byAdding: .month, value: offset, to: purchaseDate)!
            return InstallmentLine(index: offset + 1, date: date, amount: amount)
        }
    }

    public static func progress(of lines: [InstallmentLine], asOf date: Date,
                                calendar: Calendar = FinanceCalendar.calendar) -> InstallmentProgress {
        let paid = lines.filter { $0.date <= date }
        let remaining = lines.filter { $0.date > date }
        return InstallmentProgress(
            paidCount: paid.count,
            remainingCount: remaining.count,
            paidAmount: paid.map(\.amount).sum(),
            remainingAmount: remaining.map(\.amount).sum(),
            nextLine: remaining.min { $0.date < $1.date },
            lastMonth: lines.map(\.date).max().map { YearMonth(date: $0, calendar: calendar) }
        )
    }

    /// Erken kapatma: o tarihe kadarki taksitler kalır, kalan tutar tek satırda o tarihe yazılır.
    public static func closeEarly(_ lines: [InstallmentLine], on date: Date) -> [InstallmentLine] {
        let kept = lines.filter { $0.date <= date }
        let rest = lines.filter { $0.date > date }
        guard !rest.isEmpty else { return lines }
        return kept + [InstallmentLine(index: kept.count + 1, date: date, amount: rest.map(\.amount).sum())]
    }

    /// `from` ayından itibaren `monthCount` ay için aylık taksit yükü ve biten taksitler.
    public static func outlook(plans: [PlanSchedule], from: YearMonth, monthCount: Int,
                               calendar: Calendar = FinanceCalendar.calendar) -> InstallmentOutlook {
        let window = (0..<monthCount).map { from.adding(months: $0) }
        guard let lastWindowMonth = window.last else { return InstallmentOutlook(months: [], reliefs: []) }

        var totals: [YearMonth: Money] = [:]
        var reliefs: [YearMonth: (Money, [String])] = [:]

        for plan in plans {
            for line in plan.lines {
                totals[YearMonth(date: line.date, calendar: calendar), default: .zero] += line.amount
            }
            guard let last = plan.lines.max(by: { $0.date < $1.date }) else { continue }
            let reliefMonth = YearMonth(date: last.date, calendar: calendar).adding(months: 1)
            if reliefMonth > from, reliefMonth <= lastWindowMonth {
                var entry = reliefs[reliefMonth] ?? (.zero, [])
                entry.0 += last.amount
                entry.1.append(plan.title)
                reliefs[reliefMonth] = entry
            }
        }

        return InstallmentOutlook(
            months: window.map { MonthAmount(month: $0, amount: totals[$0] ?? .zero) },
            reliefs: reliefs.keys.sorted().map { InstallmentRelief(month: $0, amount: reliefs[$0]!.0, titles: reliefs[$0]!.1) }
        )
    }
}
