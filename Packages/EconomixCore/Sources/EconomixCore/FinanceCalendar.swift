import Foundation

public enum FinanceCalendar {
    /// Uygulamanın tüm tarih hesaplarında kullandığı takvim: Gregoryen, İstanbul saati, hafta pazartesi başlar.
    public static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        calendar.locale = Locale(identifier: "tr_TR")
        calendar.firstWeekday = 2
        return calendar
    }()
}

/// Takvim ayı (yıl + ay). Raporların ve bütçelerin temel birimi.
public struct YearMonth: Hashable, Comparable, Sendable, Codable, CustomStringConvertible {
    public let year: Int
    public let month: Int

    public init(year: Int, month: Int) {
        let zeroBased = (year * 12 + (month - 1))
        self.year = zeroBased / 12
        self.month = zeroBased % 12 + 1
    }

    public init(date: Date, calendar: Calendar = FinanceCalendar.calendar) {
        let c = calendar.dateComponents([.year, .month], from: date)
        self.init(year: c.year!, month: c.month!)
    }

    public static func current(calendar: Calendar = FinanceCalendar.calendar) -> YearMonth {
        YearMonth(date: .now, calendar: calendar)
    }

    public static func < (lhs: YearMonth, rhs: YearMonth) -> Bool {
        (lhs.year, lhs.month) < (rhs.year, rhs.month)
    }

    public func adding(months: Int) -> YearMonth {
        YearMonth(year: year, month: month + months)
    }

    /// İki ay arasındaki fark (`other` - `self`).
    public func months(until other: YearMonth) -> Int {
        (other.year - year) * 12 + (other.month - month)
    }

    public func start(calendar: Calendar = FinanceCalendar.calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: 1))!
    }

    /// Bir sonraki ayın ilk anı (hariç sınır).
    public func end(calendar: Calendar = FinanceCalendar.calendar) -> Date {
        adding(months: 1).start(calendar: calendar)
    }

    public var start: Date { start() }
    public var end: Date { end() }

    public func dayCount(calendar: Calendar = FinanceCalendar.calendar) -> Int {
        calendar.range(of: .day, in: .month, for: start(calendar: calendar))!.count
    }

    public var dayCount: Int { dayCount() }

    /// Ayın verilen günü; gün sayısını aşarsa ayın son gününe çekilir (31 → 28/29/30).
    public func date(day: Int, calendar: Calendar = FinanceCalendar.calendar) -> Date {
        let clamped = min(max(day, 1), dayCount(calendar: calendar))
        return calendar.date(from: DateComponents(year: year, month: month, day: clamped))!
    }

    public func contains(_ date: Date, calendar: Calendar = FinanceCalendar.calendar) -> Bool {
        date >= start(calendar: calendar) && date < end(calendar: calendar)
    }

    public static func range(from: YearMonth, to: YearMonth) -> [YearMonth] {
        guard from <= to else { return [] }
        return (0...from.months(until: to)).map { from.adding(months: $0) }
    }

    private static let names = ["Ocak", "Şubat", "Mart", "Nisan", "Mayıs", "Haziran",
                                "Temmuz", "Ağustos", "Eylül", "Ekim", "Kasım", "Aralık"]
    private static let shortNames = ["Oca", "Şub", "Mar", "Nis", "May", "Haz",
                                     "Tem", "Ağu", "Eyl", "Eki", "Kas", "Ara"]

    private static let locativeNames = ["Ocak'ta", "Şubat'ta", "Mart'ta", "Nisan'da", "Mayıs'ta", "Haziran'da",
                                        "Temmuz'da", "Ağustos'ta", "Eylül'de", "Ekim'de", "Kasım'da", "Aralık'ta"]

    public var monthName: String { Self.names[month - 1] }
    /// "Eylül'de", "Nisan'da"
    public var locativeName: String { Self.locativeNames[month - 1] }
    public var title: String { "\(monthName) \(year)" }
    public var shortTitle: String { Self.shortNames[month - 1] }
    public var description: String { String(format: "%04d-%02d", year, month) }
}

/// Yarı açık tarih aralığı [start, end).
public struct DatePeriod: Hashable, Sendable {
    public let start: Date
    public let end: Date

    public init(start: Date, end: Date) {
        self.start = start
        self.end = end
    }

    public init(months: ClosedRange<YearMonth>, calendar: Calendar = FinanceCalendar.calendar) {
        self.start = months.lowerBound.start(calendar: calendar)
        self.end = months.upperBound.end(calendar: calendar)
    }

    public init(month: YearMonth, calendar: Calendar = FinanceCalendar.calendar) {
        self.init(months: month...month, calendar: calendar)
    }

    public func contains(_ date: Date) -> Bool { date >= start && date < end }

    public func months(calendar: Calendar = FinanceCalendar.calendar) -> [YearMonth] {
        let last = calendar.date(byAdding: .second, value: -1, to: end)!
        return YearMonth.range(from: YearMonth(date: start, calendar: calendar),
                               to: YearMonth(date: last, calendar: calendar))
    }
}

/// Bütçe ayı: her ayın `startDay`'inde başlar (maaş günü 23 ise 23 Ekim–22 Kasım). 1 = takvim ayı.
/// Dönemin adı, günlerinin çoğunun düştüğü aydır: 1–15 arası başlangıçta başladığı ay, 16–31 arasında bir sonraki ay
/// (23 Ekim–22 Kasım → Kasım). Ayda olmayan gün (29–31) o ayın son gününe çekilir; dönemler arasında boşluk kalmaz.
/// Kart hesap kesimi, taksit ve abonelik tarihleri bundan etkilenmez; onlar takvim günüyle hesaplanır.
public struct MonthRule: Hashable, Sendable {
    public let startDay: Int
    public let calendar: Calendar

    public init(startDay: Int = 1, calendar: Calendar = FinanceCalendar.calendar) {
        self.startDay = min(max(startDay, 1), 31)
        self.calendar = calendar
    }

    public static let calendarMonths = MonthRule()

    public var isCalendarMonth: Bool { startDay == 1 }

    /// "23'ü", "6'sı": sayının okunuşunun son sesine göre ek.
    public var startDayTitle: String {
        let units = ["", "'i", "'si", "'ü", "'ü", "'i", "'sı", "'si", "'i", "'u"]
        let tens = [1: "'u", 2: "'si", 3: "'u"]
        let suffix = startDay % 10 == 0 ? tens[startDay / 10] ?? "" : units[startDay % 10]
        return "\(startDay)\(suffix)"
    }

    /// Dönem, adını aldığı aydan önceki ayda mı başlar?
    private var startsInPreviousMonth: Bool { startDay > 15 }

    public func start(of month: YearMonth) -> Date {
        (startsInPreviousMonth ? month.adding(months: -1) : month).date(day: startDay, calendar: calendar)
    }

    /// Bir sonraki dönemin ilk anı (hariç sınır).
    public func end(of month: YearMonth) -> Date { start(of: month.adding(months: 1)) }

    public func period(of month: YearMonth) -> DatePeriod { DatePeriod(start: start(of: month), end: end(of: month)) }

    public func period(of months: ClosedRange<YearMonth>) -> DatePeriod {
        DatePeriod(start: start(of: months.lowerBound), end: end(of: months.upperBound))
    }

    public func month(containing date: Date) -> YearMonth {
        let calendarMonth = YearMonth(date: date, calendar: calendar)
        // Dönem başları sıralı ve bitişik: başlangıcı tarihten önce olan en geç dönem.
        return [calendarMonth.adding(months: 1), calendarMonth, calendarMonth.adding(months: -1)]
            .first { start(of: $0) <= date } ?? calendarMonth.adding(months: -1)
    }

    public func current(now: Date = .now) -> YearMonth { month(containing: now) }

    public func dayCount(of month: YearMonth) -> Int {
        calendar.dateComponents([.day], from: start(of: month), to: end(of: month)).day!
    }

    public func days(of month: YearMonth) -> [Date] {
        let first = start(of: month)
        return (0..<dayCount(of: month)).map { calendar.date(byAdding: .day, value: $0, to: first)! }
    }

    /// Dönemin bugün dahil kaçıncı günü.
    public func elapsedDays(in month: YearMonth, asOf date: Date) -> Int {
        let days = calendar.dateComponents([.day], from: start(of: month), to: calendar.startOfDay(for: date)).day!
        return min(max(days + 1, 1), dayCount(of: month))
    }

    /// Dönemin ayları: başlangıcın ve son anın düştüğü dönemler arası.
    public func months(in period: DatePeriod) -> [YearMonth] {
        let last = calendar.date(byAdding: .second, value: -1, to: period.end)!
        return YearMonth.range(from: month(containing: period.start), to: month(containing: last))
    }

    /// "23 Eki – 22 Kas"
    public func rangeTitle(of month: YearMonth) -> String { rangeTitle(of: month...month) }

    /// "23 Eyl – 22 Kas"
    public func rangeTitle(of months: ClosedRange<YearMonth>) -> String {
        let first = start(of: months.lowerBound)
        let last = calendar.date(byAdding: .day, value: -1, to: end(of: months.upperBound))!
        func short(_ date: Date) -> String {
            "\(calendar.component(.day, from: date)) \(YearMonth(date: date, calendar: calendar).shortTitle)"
        }
        return "\(short(first)) – \(short(last))"
    }
}
