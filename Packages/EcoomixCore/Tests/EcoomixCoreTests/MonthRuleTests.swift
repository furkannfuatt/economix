import Foundation
import Testing
@testable import EcoomixCore

@Suite("Bütçe ayı başlangıç günü")
struct MonthRuleTests {
    let payday = MonthRule(startDay: 23)

    @Test("1 seçilince takvim ayıdır")
    func calendarMonths() {
        let rule = MonthRule(startDay: 1)
        #expect(rule.month(containing: d(2026, 10, 15)) == YearMonth(year: 2026, month: 10))
        #expect(rule.period(of: YearMonth(year: 2026, month: 10)) == DatePeriod(start: d(2026, 10, 1), end: d(2026, 11, 1)))
        #expect(rule.dayCount(of: YearMonth(year: 2026, month: 2)) == 28)
    }

    @Test("23 seçilince dönem 23'ünden ertesi ayın 22'sine; adı günlerin çoğunun düştüğü ay")
    func payday23() {
        let november = YearMonth(year: 2026, month: 11)
        #expect(payday.start(of: november) == d(2026, 10, 23))
        #expect(payday.end(of: november) == d(2026, 11, 23))
        #expect(payday.month(containing: d(2026, 10, 23)) == november)
        #expect(payday.month(containing: d(2026, 11, 22, hour: 23)) == november)
        #expect(payday.month(containing: d(2026, 10, 22)) == YearMonth(year: 2026, month: 10))
        #expect(payday.month(containing: d(2026, 11, 23)) == YearMonth(year: 2026, month: 12))
        #expect(payday.dayCount(of: november) == 31)
        #expect(payday.days(of: november).first == d(2026, 10, 23))
        #expect(payday.days(of: november).count == 31)
        #expect(payday.elapsedDays(in: november, asOf: d(2026, 10, 25, hour: 10)) == 3)
        #expect(payday.rangeTitle(of: november) == "23 Eki – 22 Kas")
        #expect(payday.rangeTitle(of: november.adding(months: -1)...november) == "23 Eyl – 22 Kas")
    }

    @Test("Ayın ilk yarısında başlayan dönem başladığı ayın adını alır")
    func earlyStart() {
        let rule = MonthRule(startDay: 10)
        #expect(rule.month(containing: d(2026, 10, 10)) == YearMonth(year: 2026, month: 10))
        #expect(rule.month(containing: d(2026, 10, 9)) == YearMonth(year: 2026, month: 9))
        #expect(rule.start(of: YearMonth(year: 2026, month: 10)) == d(2026, 10, 10))
    }

    @Test("29–31 kısa aylarda ayın son gününe çekilir; dönemler arada boşluk bırakmaz")
    func clampedStart() {
        let rule = MonthRule(startDay: 31)
        let march = YearMonth(year: 2027, month: 3)
        #expect(rule.start(of: march) == d(2027, 2, 28))
        #expect(rule.end(of: march) == d(2027, 3, 31))
        #expect(rule.end(of: march.adding(months: -1)) == rule.start(of: march))
        #expect(rule.month(containing: d(2027, 3, 1)) == march)
    }

    @Test("Birden çok ay ve geçerli dönem")
    func periods() {
        let months = YearMonth(year: 2026, month: 10)...YearMonth(year: 2026, month: 12)
        #expect(payday.period(of: months) == DatePeriod(start: d(2026, 9, 23), end: d(2026, 12, 23)))
        #expect(payday.current(now: d(2026, 10, 24)) == YearMonth(year: 2026, month: 11))
        #expect(MonthRule(startDay: 0).startDay == 1 && MonthRule(startDay: 40).startDay == 31)
    }

    @Test("Aylık toplamlar ve kategori eğilimi dönemlere göre toplanır")
    func reports() {
        func tx(_ id: String, _ lira: Int, _ kind: TxKind, _ date: Date, _ category: String?) -> TxSnapshot {
            TxSnapshot(id: id, amount: tl(lira), kind: kind, date: date, categoryID: category, accountID: nil, merchant: "")
        }
        let txs = [tx("1", 100, .expense, d(2026, 10, 22), "a"), tx("2", 40, .expense, d(2026, 10, 25), "a"),
                   tx("3", 5_000, .income, d(2026, 10, 23), nil)]
        let months = [YearMonth(year: 2026, month: 10), YearMonth(year: 2026, month: 11)]
        let totals = ReportBuilder.monthlyTotals(txs, months: months, rule: payday)
        #expect(totals.map(\.expense) == [tl(100), tl(40)])
        #expect(totals.map(\.income) == [.zero, tl(5_000)])
        #expect(ReportBuilder.categoryTrend(txs, categoryID: "a", months: months, rule: payday).map(\.amount) == [tl(100), tl(40)])
    }

    @Test("Bütçe tahmini dönemin geçen gününe göre yapılır")
    func budgetProjection() {
        let november = YearMonth(year: 2026, month: 11)
        let status = BudgetEvaluator.evaluate(limit: tl(3_100), spent: tl(300), month: november,
                                              asOf: d(2026, 10, 25, hour: 10), rule: payday)
        #expect(status.projected == tl(3_100))  // 3 günde 300 → 31 günde 3.100
    }

    @Test("Ayın günü Türkçe ekle yazılır", arguments: [
        (1, "1'i"), (2, "2'si"), (3, "3'ü"), (4, "4'ü"), (5, "5'i"), (6, "6'sı"), (7, "7'si"), (8, "8'i"), (9, "9'u"),
        (10, "10'u"), (16, "16'sı"), (20, "20'si"), (23, "23'ü"), (29, "29'u"), (30, "30'u"), (31, "31'i"),
    ])
    func dayTitle(day: Int, expected: String) {
        #expect(MonthRule(startDay: day).startDayTitle == expected)
    }
}

