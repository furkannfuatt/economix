import Foundation

public enum Frequency: String, CaseIterable, Sendable, Codable {
    case weekly, monthly, yearly

    public var title: String {
        switch self {
        case .weekly: "Haftalık"
        case .monthly: "Aylık"
        case .yearly: "Yıllık"
        }
    }

    /// Bu sıklıktaki bir tutarın aylık karşılığı.
    public func monthlyEquivalent(of amount: Money) -> Money {
        switch self {
        case .weekly: amount.scaled(numerator: 52, denominator: 12)
        case .monthly: amount
        case .yearly: amount.scaled(numerator: 1, denominator: 12)
        }
    }

    public func yearlyEquivalent(of amount: Money) -> Money {
        switch self {
        case .weekly: amount * 52
        case .monthly: amount * 12
        case .yearly: amount
        }
    }
}

public struct RecurrenceRule: Hashable, Sendable {
    public var frequency: Frequency
    public var startDate: Date
    public var endDate: Date?
    /// Aylık ve yıllık için ayın günü. Haftalıkta başlangıç gününün haftanın günü kullanılır.
    public var dayOfMonth: Int

    public init(frequency: Frequency, startDate: Date, endDate: Date? = nil, dayOfMonth: Int) {
        self.frequency = frequency
        self.startDate = startDate
        self.endDate = endDate
        self.dayOfMonth = dayOfMonth
    }
}

public enum RecurrenceEngine {
    /// `after` (hariç) ile `through` (dahil) arasındaki vadeler. Tarihler gün başlangıcıdır.
    public static func occurrences(of rule: RecurrenceRule, after: Date?, through: Date,
                                   calendar: Calendar = FinanceCalendar.calendar) -> [Date] {
        let start = calendar.startOfDay(for: rule.startDate)
        var upper = through
        if let end = rule.endDate { upper = min(upper, end) }
        guard upper >= start else { return [] }

        func accepts(_ date: Date) -> Bool {
            date >= start && date <= upper && (after.map { date > $0 } ?? true)
        }

        var result: [Date] = []
        switch rule.frequency {
        case .monthly:
            var month = YearMonth(date: start, calendar: calendar)
            if let after, after > start { month = YearMonth(date: after, calendar: calendar) }
            while true {
                let date = month.date(day: rule.dayOfMonth, calendar: calendar)
                if date > upper { break }
                if accepts(date) { result.append(date) }
                month = month.adding(months: 1)
            }
        case .yearly:
            let startMonth = YearMonth(date: start, calendar: calendar)
            var year = startMonth.year
            while true {
                let date = YearMonth(year: year, month: startMonth.month).date(day: rule.dayOfMonth, calendar: calendar)
                if date > upper { break }
                if accepts(date) { result.append(date) }
                year += 1
            }
        case .weekly:
            var date = start
            if let after, after > start {
                let days = calendar.dateComponents([.day], from: start, to: after).day ?? 0
                date = calendar.date(byAdding: .day, value: (days / 7) * 7, to: start)!
            }
            while date <= upper {
                if accepts(date) { result.append(date) }
                date = calendar.date(byAdding: .day, value: 7, to: date)!
            }
        }
        return result
    }

    /// `after` tarihinden sonraki ilk vade (bitiş tarihi geçtiyse nil).
    public static func nextOccurrence(of rule: RecurrenceRule, after: Date,
                                      calendar: Calendar = FinanceCalendar.calendar) -> Date? {
        let horizon = calendar.date(byAdding: .year, value: 2, to: max(after, rule.startDate))!
        return occurrences(of: rule, after: after, through: horizon, calendar: calendar).first
    }
}
