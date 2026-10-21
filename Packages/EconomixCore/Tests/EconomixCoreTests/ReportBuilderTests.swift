import Foundation
import Testing
@testable import EconomixCore

private func tx(_ kind: TxKind, _ lira: Int, _ date: Date, category: String? = nil, merchant: String = "",
                plan: InstallmentRef? = nil, id: String = UUID().uuidString) -> TxSnapshot {
    TxSnapshot(id: id, amount: tl(lira), kind: kind, date: date, categoryID: category, accountID: nil,
               merchant: merchant, installment: plan)
}

private func planTxs(total: Int, count: Int, purchase: Date, category: String) -> [TxSnapshot] {
    let ref = InstallmentRef(planID: "plan-1", purchaseDate: purchase, planTotal: tl(total))
    return InstallmentScheduler.schedule(total: tl(total), count: count, purchaseDate: purchase).map {
        TxSnapshot(id: "plan-1-\($0.index)", amount: $0.amount, kind: .expense, date: $0.date,
                   categoryID: category, accountID: nil, merchant: "TEKNOSA", installment: ref)
    }
}

/// Yatırım bozma: gelir sayılmaz, kalana eklenir.
private func investmentReturn(_ lira: Int, _ date: Date) -> TxSnapshot {
    TxSnapshot(id: UUID().uuidString, amount: tl(lira), kind: .divestment, date: date, categoryID: "yatirim-alim",
               accountID: nil, merchant: "MIDAS")
}

@Suite("Raporlar")
struct ReportBuilderTests {
    let october = DatePeriod(month: YearMonth(year: 2026, month: 10))

    @Test("Özet transferleri saymaz, tasarruf oranını hesaplar")
    func summary() {
        let txs = [
            tx(.income, 40_000, d(2026, 10, 1)),
            tx(.expense, 10_000, d(2026, 10, 3)),
            tx(.expense, 20_000, d(2026, 10, 20)),
            tx(.transfer, 15_000, d(2026, 10, 25)),
            tx(.expense, 999, d(2026, 11, 1)),
        ]
        let s = ReportBuilder.summary(txs, in: october)
        #expect(s.income == tl(40_000))
        #expect(s.expense == tl(30_000))
        #expect(s.net == tl(10_000))
        #expect(s.savingsRate == 0.25)
    }

    @Test("Yatırım gider sayılmaz ama kalandan düşülür; tasarruf oranında tasarruf sayılır")
    func investments() {
        let txs = [
            tx(.income, 40_000, d(2026, 10, 1)),
            tx(.expense, 30_000, d(2026, 10, 3)),
            tx(.investment, 6_000, d(2026, 10, 10)),
            tx(.investment, 1_000, d(2026, 11, 2)),
        ]
        let s = ReportBuilder.summary(txs, in: october)
        #expect(s.expense == tl(30_000))
        #expect(s.investment == tl(6_000))
        #expect(s.net == tl(4_000))
        #expect(s.savingsRate == 0.25)
        #expect(s.remainingRate == 0.1)
        #expect(s.transactionCount == 3)
        #expect(ReportBuilder.categoryTotals(txs, kind: .expense, in: october).map(\.amount) == [tl(30_000)])

        let months = [YearMonth(year: 2026, month: 10), YearMonth(year: 2026, month: 11)]
        let monthly = ReportBuilder.monthlyTotals(txs, months: months)
        #expect(monthly.map(\.investment) == [tl(6_000), tl(1_000)])
        #expect(monthly.map(\.expense) == [tl(30_000), .zero])
        #expect(monthly.map(\.net) == [tl(4_000), tl(-1_000)])
        #expect(monthly.first?.savingsRate == 0.25)
        #expect(TxKind.investment.title == "Yatırım")
    }

    @Test("Yatırım bozma gelir sayılmaz; kalana eklenir, alımla aynı ayda birbirini götürür")
    func investmentReturns() {
        let base = [tx(.income, 40_000, d(2026, 10, 1)), tx(.expense, 30_000, d(2026, 10, 3))]

        let roundTrip = ReportBuilder.summary(base + [tx(.investment, 6_000, d(2026, 10, 10)),
                                                      investmentReturn(6_000, d(2026, 10, 20))], in: october)
        #expect(roundTrip.income == tl(40_000))
        #expect(roundTrip.investment == tl(6_000))
        #expect(roundTrip.investmentReturn == tl(6_000))
        #expect(roundTrip.netInvestment == .zero)
        #expect(roundTrip.net == ReportBuilder.summary(base, in: october).net)
        #expect(roundTrip.savingsRate == 0.25)
        #expect(roundTrip.transactionCount == 4)

        let sale = ReportBuilder.summary(base + [investmentReturn(5_000, d(2026, 10, 20))], in: october)
        #expect(sale.income == tl(40_000))
        #expect(sale.netInvestment == tl(-5_000))
        #expect(sale.net == tl(15_000))
        #expect(sale.savingsRate == 0.25)

        let monthly = ReportBuilder.monthlyTotals(base + [investmentReturn(5_000, d(2026, 10, 20))],
                                                  months: [YearMonth(year: 2026, month: 10)])
        #expect(monthly.first?.income == tl(40_000))
        #expect(monthly.first?.investmentReturn == tl(5_000))
        #expect(monthly.first?.net == tl(15_000))
    }

    @Test("Dev tutarlar toplanırken özet çökmez")
    func hugeAmountsDoNotCrash() {
        let huge = Money(minor: 9_000_000_000_000_000_000)
        let txs = (0..<3).map {
            TxSnapshot(id: "\($0)", amount: huge, kind: .expense, date: d(2026, 10, 2), categoryID: nil,
                       accountID: nil, merchant: "X")
        }
        #expect(ReportBuilder.summary(txs, in: october).expense == Money(minor: .max))
        #expect(ReportBuilder.spendingSeries(txs, in: october, by: .week).map(\.amount).sum() == Money(minor: .max))
    }

    @Test("Gelir yoksa tasarruf ve kalan oranı nil")
    func noIncome() {
        let s = ReportBuilder.summary([tx(.expense, 100, d(2026, 10, 1))], in: october)
        #expect(s.savingsRate == nil)
        #expect(s.remainingRate == nil)
    }

    @Test("Aylık yük modunda taksit aylara yayılır, satın alma modunda alım ayında tek tutar")
    func modes() {
        let txs = planTxs(total: 12_000, count: 6, purchase: d(2026, 9, 15), category: "elektronik")
        let september = DatePeriod(month: YearMonth(year: 2026, month: 9))

        let cash = ReportBuilder.normalized(txs, mode: .cashFlow)
        #expect(ReportBuilder.summary(cash, in: october).expense == tl(2_000))

        let purchase = ReportBuilder.normalized(txs, mode: .purchase)
        #expect(purchase.count == 1)
        #expect(ReportBuilder.summary(purchase, in: september).expense == tl(12_000))
        #expect(ReportBuilder.summary(purchase, in: october).expense == .zero)
    }

    @Test("Kategori toplamları büyükten küçüğe, paylar toplamı 1")
    func categories() {
        let txs = [
            tx(.expense, 3_000, d(2026, 10, 2), category: "market"),
            tx(.expense, 1_000, d(2026, 10, 5), category: "yemek"),
            tx(.expense, 1_000, d(2026, 10, 9), category: "market"),
            tx(.income, 50_000, d(2026, 10, 1), category: "maas"),
        ]
        let totals = ReportBuilder.categoryTotals(txs, kind: .expense, in: october)
        #expect(totals.map(\.categoryID) == ["market", "yemek"])
        #expect(totals.map(\.amount) == [tl(4_000), tl(1_000)])
        #expect(totals[0].count == 2)
        #expect(abs(totals.map(\.share).reduce(0, +) - 1) < 0.0001)
    }

    @Test("Aylık gelir-gider serisi boş ayları sıfırla doldurur")
    func monthly() {
        let txs = [tx(.expense, 500, d(2026, 8, 3)), tx(.income, 1_000, d(2026, 10, 3))]
        let months = YearMonth.range(from: YearMonth(year: 2026, month: 8), to: YearMonth(year: 2026, month: 10))
        let series = ReportBuilder.monthlyTotals(txs, months: months)
        #expect(series.map(\.expense) == [tl(500), .zero, .zero])
        #expect(series.map(\.income) == [.zero, .zero, tl(1_000)])
    }

    @Test("Aylık toplamlar isteğe bağlı aralıkla kırpılır")
    func monthlyClipped() {
        let txs = [tx(.expense, 100, d(2026, 9, 5)), tx(.expense, 200, d(2026, 9, 20)), tx(.expense, 300, d(2026, 10, 25))]
        let months = [YearMonth(year: 2026, month: 9), YearMonth(year: 2026, month: 10)]
        let clipped = ReportBuilder.monthlyTotals(txs, months: months, in: DatePeriod(start: d(2026, 9, 15), end: d(2026, 10, 20)))
        #expect(clipped.map(\.expense) == [tl(200), .zero])
    }

    @Test("Harcama serisi: günlük kovalar boşları sıfırla doldurur, yalnız gider sayılır")
    func dailySeries() {
        let txs = [
            tx(.expense, 100, d(2026, 10, 3, hour: 10)),
            tx(.expense, 50, d(2026, 10, 3, hour: 20)),
            tx(.income, 9_000, d(2026, 10, 3)),
            tx(.investment, 700, d(2026, 10, 4)),
            tx(.transfer, 300, d(2026, 10, 5)),
            tx(.expense, 25, d(2026, 10, 31, hour: 23)),
            tx(.expense, 999, d(2026, 11, 1)),
        ]
        let series = ReportBuilder.spendingSeries(txs, in: october, by: .day)
        #expect(series.count == 31)
        #expect(series[2].period == DatePeriod(start: d(2026, 10, 3), end: d(2026, 10, 4)))
        #expect(series[2].amount == tl(150))
        #expect(series[2].count == 2)
        #expect(series[3].amount == .zero)
        #expect(series.last?.amount == tl(25))
        #expect(series.map(\.amount).sum() == ReportBuilder.summary(txs, in: october).expense)
    }

    @Test("Haftalık kovalar pazartesi başlar, dönem sınırında kırpılır")
    func weeklySeries() {
        // Ekim 2026: 1'i perşembe.
        let txs = [
            tx(.expense, 100, d(2026, 10, 1)),
            tx(.expense, 200, d(2026, 10, 4, hour: 23)),
            tx(.expense, 300, d(2026, 10, 5)),
            tx(.expense, 400, d(2026, 10, 31)),
            tx(.expense, 999, d(2026, 11, 1)),
        ]
        let series = ReportBuilder.spendingSeries(txs, in: october, by: .week)
        #expect(series.map(\.period.start) == [d(2026, 10, 1), d(2026, 10, 5), d(2026, 10, 12), d(2026, 10, 19), d(2026, 10, 26)])
        #expect(series.first?.period.end == d(2026, 10, 5))
        #expect(series.last?.period.end == d(2026, 11, 1))
        #expect(series.map(\.amount) == [tl(300), tl(300), .zero, .zero, tl(400)])
    }

    @Test("Aylık kovalar bütçe ayı sınırlarını izler")
    func monthlySeries() {
        let payday = MonthRule(startDay: 23)
        let period = DatePeriod(start: d(2026, 9, 10), end: d(2026, 11, 5))
        let txs = [
            tx(.expense, 100, d(2026, 9, 22)),
            tx(.expense, 200, d(2026, 9, 23)),
            tx(.expense, 300, d(2026, 10, 23)),
            tx(.expense, 50, d(2026, 11, 4)),
        ]
        let series = ReportBuilder.spendingSeries(txs, in: period, by: .month, rule: payday)
        #expect(series.map(\.period) == [
            DatePeriod(start: d(2026, 9, 10), end: d(2026, 9, 23)),
            DatePeriod(start: d(2026, 9, 23), end: d(2026, 10, 23)),
            DatePeriod(start: d(2026, 10, 23), end: d(2026, 11, 5)),
        ])
        #expect(series.map(\.amount) == [tl(100), tl(200), tl(350)])
    }

    @Test("Kümülatif harcama artarak toplam gidere ulaşır; asOf sonrası günler yok")
    func cumulative() {
        let txs = [
            tx(.expense, 100, d(2026, 10, 2)),
            tx(.expense, 50, d(2026, 10, 4)),
            tx(.income, 1_000, d(2026, 10, 4)),
            tx(.expense, 70, d(2026, 10, 20)),
        ]
        let full = ReportBuilder.cumulativeSpending(txs, in: october)
        #expect(full.count == 31)
        #expect(full.map(\.amount).prefix(4) == [.zero, tl(100), tl(100), tl(150)])
        #expect(full.last?.amount == tl(220))

        let partial = ReportBuilder.cumulativeSpending(txs, in: october, asOf: d(2026, 10, 10, hour: 12))
        #expect(partial.count == 10)
        #expect(partial.last?.day == d(2026, 10, 10))
        #expect(partial.last?.amount == tl(150))
    }

    @Test("Önceki dönemle kıyas: devam eden dönemde aynı güne kadar, biten dönemde tamamıyla")
    func pace() {
        let previousTxs = [tx(.expense, 100, d(2026, 9, 2)), tx(.expense, 300, d(2026, 9, 20))]
        let september = DatePeriod(month: YearMonth(year: 2026, month: 9))
        let previous = ReportBuilder.cumulativeSpending(previousTxs, in: september)
        let txs = [tx(.expense, 150, d(2026, 10, 3)), tx(.expense, 500, d(2026, 10, 25))]

        let ongoing = ReportBuilder.cumulativeSpending(txs, in: october, asOf: d(2026, 10, 10))
        let paced = SpendingPace(current: ongoing, previous: previous, periodDays: 31)
        #expect(paced?.current == tl(150))
        #expect(paced?.previous == tl(100))
        #expect(paced?.isPartial == true)
        #expect(paced?.change == 0.5)

        let finished = SpendingPace(current: ReportBuilder.cumulativeSpending(txs, in: october), previous: previous, periodDays: 31)
        #expect(finished?.current == tl(650))
        #expect(finished?.previous == tl(400))
        #expect(finished?.isPartial == false)

        #expect(SpendingPace(current: ongoing, previous: [], periodDays: 31) == nil)
        #expect(SpendingPace(current: ongoing, previous: ReportBuilder.cumulativeSpending([], in: september), periodDays: 31)?.change == nil)
    }

    @Test("Haftanın günleri: toplam, gün sayısına bölünmüş ortalama, asOf kırpması")
    func weekdays() {
        // Ekim 2026: pazartesiler 5, 12, 19, 26; perşembeler 1, 8, 15, 22, 29.
        let txs = [
            tx(.expense, 400, d(2026, 10, 5)),
            tx(.expense, 200, d(2026, 10, 12)),
            tx(.expense, 600, d(2026, 10, 26)),
            tx(.expense, 90, d(2026, 10, 1)),
            tx(.income, 5_000, d(2026, 10, 5)),
        ]
        let all = ReportBuilder.weekdayAverages(txs, in: october)
        #expect(all.map(\.index) == Array(0..<7))
        #expect(all[0].total == tl(1_200))
        #expect(all[0].dayCount == 4)
        #expect(all[0].average == tl(300))
        #expect(all[3].total == tl(90))
        #expect(all[3].dayCount == 5)
        #expect(all.map(\.dayCount).reduce(0, +) == 31)
        #expect(all[0].shortTitle == "Pzt" && all[6].title == "Pazar")

        let early = ReportBuilder.weekdayAverages(txs, in: october, asOf: d(2026, 10, 14))
        #expect(early[0].total == tl(600))
        #expect(early[0].dayCount == 2)
        #expect(early.map(\.dayCount).reduce(0, +) == 14)
    }

    @Test("Kategori trendi")
    func trend() {
        let txs = [
            tx(.expense, 100, d(2026, 9, 3), category: "market"),
            tx(.expense, 200, d(2026, 10, 3), category: "market"),
            tx(.expense, 999, d(2026, 10, 3), category: "yemek"),
        ]
        let months = [YearMonth(year: 2026, month: 9), YearMonth(year: 2026, month: 10)]
        #expect(ReportBuilder.categoryTrend(txs, categoryID: "market", months: months).map(\.amount) == [tl(100), tl(200)])
    }

    @Test("İşyerleri normalize edilerek gruplanır")
    func merchants() {
        let txs = [
            tx(.expense, 300, d(2026, 10, 2), merchant: "MIGROS KADIKOY"),
            tx(.expense, 200, d(2026, 10, 4), merchant: "Migros  Kadıköy"),
            tx(.expense, 400, d(2026, 10, 6), merchant: "Starbucks"),
            tx(.expense, 50, d(2026, 10, 6), merchant: ""),
        ]
        let top = ReportBuilder.topMerchants(txs, in: october, limit: 5)
        #expect(top.map(\.amount) == [tl(500), tl(400)])
        #expect(top[0].count == 2)
        #expect(top[0].name == "MIGROS KADIKOY")
    }
}

@Suite("İşyeri normalleştirme")
struct MerchantNormalizerTests {
    @Test("Türkçe karakter, büyük harf, sayı ve noktalama temizlenir", arguments: [
        ("Migros  Kadıköy", "MIGROS KADIKOY"),
        ("ŞOK MARKET-1234 İSTANBUL", "SOK MARKET ISTANBUL"),
        ("getir*yemek 34", "GETIR YEMEK"),
        ("  ", ""),
    ])
    func normalizes(input: String, expected: String) {
        #expect(MerchantNormalizer.normalize(input) == expected)
    }
}
