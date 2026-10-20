import Foundation
import Testing
@testable import EconomixCore

@Suite("AI özet verisi")
struct AIPayloadBuilderTests {
    let asOf = d(2026, 10, 18, hour: 12)

    func input() -> AnalysisInput {
        var txs: [TxSnapshot] = []
        for month in 5...10 {
            txs.append(TxSnapshot(id: "i\(month)", amount: tl(50_000), kind: .income, date: d(2026, month, 1),
                                  categoryID: "maas", accountID: nil, merchant: "ACME Maaş"))
            txs.append(TxSnapshot(id: "m\(month)", amount: tl(8_000), kind: .expense, date: d(2026, month, 10),
                                  categoryID: "market", accountID: nil, merchant: "Migros Kadıköy",))
            txs.append(TxSnapshot(id: "y\(month)", amount: tl(3_000), kind: .expense, date: d(2026, month, 12),
                                  categoryID: "yemek", accountID: nil, merchant: "Gizli Restoran"))
            txs.append(TxSnapshot(id: "v\(month)", amount: tl(5_000), kind: .investment, date: d(2026, month, 15),
                                  categoryID: "yatirim", accountID: nil, merchant: "MIDAS"))
        }
        let plan = PlanSchedule(id: "p", title: "Telefon",
                                lines: InstallmentScheduler.schedule(total: tl(12_000), count: 4, purchaseDate: d(2026, 9, 1)))
        return AnalysisInput(transactions: txs, asOf: asOf, budgets: ["market": tl(9_000)],
                             categoryNames: ["maas": "Maaş", "market": "Market", "yemek": "Yemek & Kafe"],
                             subscriptions: [SubscriptionInfo(title: "Netflix", monthlyAmount: Money(minor: 229_99), categoryID: nil)],
                             installmentPlans: [plan])
    }

    @Test("Son 6 ay sırayla, cari ay kısmi olarak işaretli")
    func months() {
        let payload = AIPayloadBuilder.build(from: input(), insights: [], includeMerchants: false)
        #expect(payload.months.map(\.month) == ["2026-05", "2026-06", "2026-07", "2026-08", "2026-09", "2026-10"])
        #expect(payload.months.last?.income == 50_000)
        #expect(payload.months.last?.expense == 11_000)
        #expect(payload.months.last?.investment == 5_000, "Yatırım ayrı; gider ve tasarruf oranına girmez")
        #expect(payload.months.last?.savingsRatePercent == 78)
        #expect(payload.currentMonthDay == 18)
        #expect(payload.currency == "TRY")
    }

    @Test("Kategoriler toplam harcamaya göre sıralı, bütçe ve aylık seri dahil")
    func categories() {
        let payload = AIPayloadBuilder.build(from: input(), insights: [], includeMerchants: false)
        #expect(payload.categories.map(\.name) == ["Market", "Yemek & Kafe"])
        #expect(payload.categories[0].monthlyBudget == 9_000)
        #expect(payload.categories[0].amountsByMonth == [8_000, 8_000, 8_000, 8_000, 8_000, 8_000])
    }

    @Test("Abonelikler, taksit yükü ve kural önerileri eklenir")
    func extras() {
        let insight = Insight(id: "x", kind: .savingsRate, severity: .warning, title: "Başlık", message: "Mesaj",
                              estimatedMonthlySaving: nil, categoryID: nil)
        let payload = AIPayloadBuilder.build(from: input(), insights: [insight], includeMerchants: false)
        #expect(payload.subscriptions.first?.title == "Netflix")
        #expect(payload.subscriptions.first?.monthly == 229.99)
        #expect(payload.installmentLoad.map(\.amount) == [3_000, 3_000, 3_000, 0, 0, 0])
        #expect(payload.ruleBasedFindings == ["Başlık: Mesaj"])
    }

    @Test("İşyeri adları yalnızca izin verilirse gönderilir")
    func merchantsOptIn() throws {
        let hidden = AIPayloadBuilder.build(from: input(), insights: [], includeMerchants: false)
        #expect(hidden.topMerchants == nil)
        let json = String(decoding: try JSONEncoder().encode(hidden), as: UTF8.self)
        #expect(!json.contains("Migros"))
        #expect(!json.contains("Gizli Restoran"))

        let shown = AIPayloadBuilder.build(from: input(), insights: [], includeMerchants: true)
        #expect(shown.topMerchants?.first?.name == "Migros Kadıköy")
    }
}
