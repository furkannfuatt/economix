import Foundation
import Testing
@testable import EcoomixCore

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

    @Test("Gelir yoksa tasarruf oranı nil")
    func noIncome() {
        #expect(ReportBuilder.summary([tx(.expense, 100, d(2026, 10, 1))], in: october).savingsRate == nil)
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
