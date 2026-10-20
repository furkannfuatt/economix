import Foundation
import Testing
@testable import EconomixCore

@Suite("Rapor dönemleri")
struct ReportPeriodTests {
    /// 21 Ekim 2026 çarşamba.
    let now = d(2026, 10, 21, hour: 14)
    let calendarMonths = MonthRule.calendarMonths
    let payday = MonthRule(startDay: 23)

    @Test("Hafta pazartesi başlar; offset önceki haftalara gider")
    func week() {
        let thisWeek = DatePeriod(start: d(2026, 10, 19), end: d(2026, 10, 26))
        #expect(ReportRange.week.period(offset: 0, rule: calendarMonths, now: now) == thisWeek)
        #expect(ReportRange.week.period(offset: 0, rule: calendarMonths, now: d(2026, 10, 25, hour: 23)) == thisWeek)
        #expect(ReportRange.week.period(offset: -1, rule: calendarMonths, now: now)
                == DatePeriod(start: d(2026, 10, 12), end: d(2026, 10, 19)))
        #expect(ReportRange.week.months(offset: 0, rule: calendarMonths, now: now).isEmpty)
    }

    @Test("Ay tabanlı aralıklar bütçe ayına uyar")
    func monthBased() {
        #expect(ReportRange.month.period(offset: 0, rule: payday, now: now) == DatePeriod(start: d(2026, 9, 23), end: d(2026, 10, 23)))
        #expect(ReportRange.month.period(offset: -1, rule: payday, now: now) == DatePeriod(start: d(2026, 8, 23), end: d(2026, 9, 23)))
        #expect(ReportRange.quarter.months(offset: 0, rule: calendarMonths, now: now)
                == [YearMonth(year: 2026, month: 8), YearMonth(year: 2026, month: 9), YearMonth(year: 2026, month: 10)])
        #expect(ReportRange.quarter.period(offset: -1, rule: calendarMonths, now: now)
                == DatePeriod(start: d(2026, 5, 1), end: d(2026, 8, 1)))
        #expect(ReportRange.year.months(offset: 0, rule: calendarMonths, now: now).count == 12)
        #expect(ReportRange.custom.period(offset: 0, rule: calendarMonths, now: now) == nil)
    }

    @Test("Özel aralık: gün sayısı, kaydırma, önceki dönem, geçen gün")
    func custom() {
        let range = DatePeriod(from: d(2026, 10, 5), through: d(2026, 10, 18, hour: 9))
        #expect(range == DatePeriod(start: d(2026, 10, 5), end: d(2026, 10, 19)))
        #expect(DatePeriod(from: d(2026, 10, 18), through: d(2026, 10, 5)) == range)
        #expect(range.dayCount() == 14)
        #expect(range.days().first == d(2026, 10, 5))
        #expect(range.days().count == 14)
        #expect(range.preceding() == DatePeriod(start: d(2026, 9, 21), end: d(2026, 10, 5)))
        #expect(range.shifted(by: 1) == DatePeriod(start: d(2026, 10, 19), end: d(2026, 11, 2)))
        #expect(range.elapsedDays(asOf: d(2026, 10, 7, hour: 20)) == 3)
        #expect(range.elapsedDays(asOf: d(2026, 11, 30)) == 14)
        #expect(range.elapsedDays(asOf: d(2026, 9, 1)) == 0)
    }

    @Test("Kısa başlık: aynı ay, farklı ay, farklı yıl, tek gün")
    func titles() {
        #expect(DatePeriod(from: d(2026, 10, 13), through: d(2026, 10, 19)).shortTitle() == "13–19 Eki")
        #expect(DatePeriod(from: d(2026, 10, 28), through: d(2026, 11, 3)).shortTitle() == "28 Eki – 3 Kas")
        #expect(DatePeriod(from: d(2025, 12, 29), through: d(2026, 1, 4)).shortTitle() == "29 Ara 2025 – 4 Oca 2026")
        #expect(DatePeriod(from: d(2026, 10, 18), through: d(2026, 10, 18)).shortTitle() == "18 Eki")
    }

    @Test("Gruplama seçenekleri aralık uzunluğuna göre", arguments: [
        (7, [.day], .day),
        (31, [.day, .week], .day),
        (92, [.day, .week, .month], .week),
        (183, [.week, .month], .month),
        (366, [.week, .month], .month),
        (400, [.month], .month),
    ] as [(Int, [ReportGranularity], ReportGranularity)])
    func granularity(days: Int, options: [ReportGranularity], preferred: ReportGranularity) {
        let first = d(2026, 1, 1)
        let period = DatePeriod(from: first, through: FinanceCalendar.calendar.date(byAdding: .day, value: days - 1, to: first)!)
        #expect(period.dayCount() == days)
        #expect(ReportGranularity.options(for: period) == options)
        #expect(ReportGranularity.preferred(for: period) == preferred)
    }
}
