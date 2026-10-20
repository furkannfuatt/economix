import Foundation

/// Kredi kartının hesap kesim ayarı.
public struct CardCycle: Hashable, Sendable, Codable {
    /// Hesap kesim günü (1–31). Ayın gün sayısını aşarsa son güne çekilir.
    public var statementDay: Int
    /// Kesimden kaç gün sonra son ödeme günü geldiği.
    public var dueOffsetDays: Int

    public init(statementDay: Int, dueOffsetDays: Int = 10) {
        self.statementDay = statementDay
        self.dueOffsetDays = dueOffsetDays
    }

    public func closingDate(in month: YearMonth, calendar: Calendar = FinanceCalendar.calendar) -> Date {
        month.date(day: statementDay, calendar: calendar)
    }

    /// Belirtilen ayda kesilen ekstre.
    public func statement(closingIn month: YearMonth, calendar: Calendar = FinanceCalendar.calendar) -> CardStatement {
        let closing = closingDate(in: month, calendar: calendar)
        let previousClosing = closingDate(in: month.adding(months: -1), calendar: calendar)
        let periodStart = calendar.date(byAdding: .day, value: 1, to: previousClosing)!
        let periodEnd = calendar.date(byAdding: .day, value: 1, to: closing)!
        let due = calendar.date(byAdding: .day, value: dueOffsetDays, to: closing)!
        return CardStatement(closingMonth: month, closingDate: closing, dueDate: due,
                             period: DatePeriod(start: periodStart, end: periodEnd))
    }

    /// Bu tarihte yapılan bir harcamanın düşeceği ekstre.
    public func statement(containing date: Date, calendar: Calendar = FinanceCalendar.calendar) -> CardStatement {
        let month = YearMonth(date: date, calendar: calendar)
        let candidate = statement(closingIn: month, calendar: calendar)
        return date < candidate.period.end ? candidate : statement(closingIn: month.adding(months: 1), calendar: calendar)
    }

    /// Verilen tarih itibarıyla kesilmiş son ekstre.
    public func lastClosedStatement(asOf date: Date, calendar: Calendar = FinanceCalendar.calendar) -> CardStatement {
        let open = statement(containing: date, calendar: calendar)
        return statement(closingIn: open.closingMonth.adding(months: -1), calendar: calendar)
    }
}

public struct CardStatement: Hashable, Sendable {
    public let closingMonth: YearMonth
    public let closingDate: Date
    public let dueDate: Date
    /// Ekstreye giren harcamaların aralığı: [önceki kesim + 1 gün, bu kesim + 1 gün)
    public let period: DatePeriod

    public var periodStart: Date { period.start }
}
