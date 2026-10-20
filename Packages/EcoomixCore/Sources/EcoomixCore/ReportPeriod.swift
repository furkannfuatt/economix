import Foundation

/// Raporlar ekranının dönem seçimi.
public enum ReportRange: String, CaseIterable, Sendable {
    case week, month, quarter, half, year, custom

    public var title: String {
        switch self {
        case .week: "Hafta"
        case .month: "Ay"
        case .quarter: "3 Ay"
        case .half: "6 Ay"
        case .year: "Yıl"
        case .custom: "Özel"
        }
    }

    /// Ay tabanlı aralığın ay sayısı; hafta ve özel aralıkta nil.
    public var monthCount: Int? {
        switch self {
        case .month: 1
        case .quarter: 3
        case .half: 6
        case .year: 12
        case .week, .custom: nil
        }
    }

    /// İçinde bulunulan dönemden `offset` adım uzaktaki dönem (0 = bu dönem, -1 = bir önceki). Özel aralıkta nil.
    /// Hafta pazartesi başlar; ay tabanlı aralıklar bütçe ayına (`rule`) uyar.
    public func period(offset: Int, rule: MonthRule, now: Date = .now) -> DatePeriod? {
        switch self {
        case .custom:
            return nil
        case .week:
            let calendar = rule.calendar
            let week = calendar.dateInterval(of: .weekOfYear, for: now)!
            let start = calendar.date(byAdding: .day, value: 7 * offset, to: week.start)!
            return DatePeriod(start: start, end: calendar.date(byAdding: .day, value: 7, to: start)!)
        case .month, .quarter, .half, .year:
            let months = months(offset: offset, rule: rule, now: now)
            return rule.period(of: months.first!...months.last!)
        }
    }

    /// Ay tabanlı aralığın ayları, eskiden yeniye. Hafta ve özel aralıkta boş.
    public func months(offset: Int, rule: MonthRule, now: Date = .now) -> [YearMonth] {
        guard let count = monthCount else { return [] }
        let last = rule.current(now: now).adding(months: offset * count)
        return (0..<count).map { last.adding(months: $0 - count + 1) }
    }
}

/// Harcama grafiğinin çubuk başına süresi.
public enum ReportGranularity: String, CaseIterable, Sendable {
    case day, week, month

    public var title: String {
        switch self {
        case .day: "Günlük"
        case .week: "Haftalık"
        case .month: "Aylık"
        }
    }

    /// Aralığın uzunluğuna göre okunaklı gruplamalar: gün ≤ 92 gün, hafta 14–371 gün, ay ≥ 56 gün.
    public static func options(for period: DatePeriod, calendar: Calendar = FinanceCalendar.calendar) -> [ReportGranularity] {
        let days = period.dayCount(calendar: calendar)
        var result: [ReportGranularity] = []
        if days <= 92 { result.append(.day) }
        if (14...371).contains(days) { result.append(.week) }
        if days >= 56 { result.append(.month) }
        return result
    }

    /// Varsayılan gruplama: bir aya kadar günlük, üç aya kadar haftalık, üstü aylık.
    public static func preferred(for period: DatePeriod, calendar: Calendar = FinanceCalendar.calendar) -> ReportGranularity {
        let days = period.dayCount(calendar: calendar)
        return days <= 31 ? .day : days <= 92 ? .week : .month
    }
}

extension DatePeriod {
    /// İki günü de kapsayan tam günler: [ilk günün başı, son günün ertesi). Sıra önemsizdir.
    public init(from first: Date, through last: Date, calendar: Calendar = FinanceCalendar.calendar) {
        let a = calendar.startOfDay(for: min(first, last))
        let b = calendar.startOfDay(for: max(first, last))
        self.init(start: a, end: calendar.date(byAdding: .day, value: 1, to: b)!)
    }

    public func dayCount(calendar: Calendar = FinanceCalendar.calendar) -> Int {
        calendar.dateComponents([.day], from: start, to: end).day!
    }

    /// Aralıktaki her günün başı.
    public func days(calendar: Calendar = FinanceCalendar.calendar) -> [Date] {
        (0..<dayCount(calendar: calendar)).map { calendar.date(byAdding: .day, value: $0, to: start)! }
    }

    /// Aralığı kendi gün sayısı kadar `steps` adım kaydırır (-1 = hemen önceki eş uzunluktaki aralık).
    public func shifted(by steps: Int, calendar: Calendar = FinanceCalendar.calendar) -> DatePeriod {
        let days = dayCount(calendar: calendar) * steps
        return DatePeriod(start: calendar.date(byAdding: .day, value: days, to: start)!,
                          end: calendar.date(byAdding: .day, value: days, to: end)!)
    }

    /// Aynı gün sayısında, hemen önceki aralık.
    public func preceding(calendar: Calendar = FinanceCalendar.calendar) -> DatePeriod {
        shifted(by: -1, calendar: calendar)
    }

    /// `date` günü dahil o güne kadarki kısım; dönem henüz başlamadıysa boş.
    public func elapsed(asOf date: Date, calendar: Calendar = FinanceCalendar.calendar) -> DatePeriod {
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date))!
        return DatePeriod(start: start, end: max(start, min(end, endOfDay)))
    }

    /// Bugün dahil geçen gün sayısı (0…dayCount).
    public func elapsedDays(asOf date: Date, calendar: Calendar = FinanceCalendar.calendar) -> Int {
        elapsed(asOf: date, calendar: calendar).dayCount(calendar: calendar)
    }

    /// "13–19 Eki", "28 Eki – 3 Kas", "29 Ara 2025 – 4 Oca 2026", tek günse "18 Eki".
    public func shortTitle(calendar: Calendar = FinanceCalendar.calendar) -> String {
        let last = max(start, calendar.date(byAdding: .day, value: -1, to: end)!)
        let first = (calendar.component(.day, from: start), YearMonth(date: start, calendar: calendar))
        let final = (calendar.component(.day, from: last), YearMonth(date: last, calendar: calendar))
        if first == final { return "\(first.0) \(first.1.shortTitle)" }
        if first.1 == final.1 { return "\(first.0)–\(final.0) \(final.1.shortTitle)" }
        if first.1.year == final.1.year { return "\(first.0) \(first.1.shortTitle) – \(final.0) \(final.1.shortTitle)" }
        return "\(first.0) \(first.1.shortTitle) \(first.1.year) – \(final.0) \(final.1.shortTitle) \(final.1.year)"
    }
}
