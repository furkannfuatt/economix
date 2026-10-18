import Foundation
import Testing
import EcoomixCore
@testable import Ecoomix

/// Gerçek Gemini API'sine istek atar. Yalnızca `make gemini-live` ile (anahtar ortam değişkeniyle) çalışır;
/// normal `make test` sırasında atlanır.
@Suite("Gemini canlı", .enabled(if: ProcessInfo.processInfo.environment["GEMINI_LIVE_KEY"]?.isEmpty == false))
@MainActor
struct GeminiLiveTests {
    @Test("Uygulamanın gerçek isteğiyle analiz alınır ve çözülür")
    func analyze() async throws {
        let key = try #require(ProcessInfo.processInfo.environment["GEMINI_LIVE_KEY"])
        let current = YearMonth.current()
        var txs: [TxSnapshot] = []
        for offset in 0..<6 {
            let month = current.adding(months: -offset)
            func day(_ d: Int) -> Date { month.date(day: d) }
            txs.append(TxSnapshot(id: "maas\(offset)", amount: Money(minor: 62_000_00), kind: .income, date: day(1),
                                  categoryID: "maas", accountID: nil, merchant: "Maaş"))
            txs.append(TxSnapshot(id: "kira\(offset)", amount: Money(minor: 18_000_00), kind: .expense, date: day(5),
                                  categoryID: "kira", accountID: nil, merchant: "Kira"))
            txs.append(TxSnapshot(id: "market\(offset)", amount: Money(minor: (8_000 + offset * 600) * 100), kind: .expense,
                                  date: day(10), categoryID: "market", accountID: nil, merchant: "Migros"))
            txs.append(TxSnapshot(id: "yemek\(offset)", amount: Money(minor: (4_500 + offset * 300) * 100), kind: .expense,
                                  date: day(12), categoryID: "yemek", accountID: nil, merchant: "Yemeksepeti"))
        }
        let plan = PlanSchedule(id: "p", title: "Telefon",
                                lines: InstallmentScheduler.schedule(total: Money(minor: 72_000_00), count: 12,
                                                                     purchaseDate: current.adding(months: -3).date(day: 10)))
        let input = AnalysisInput(
            transactions: txs, asOf: .now, budgets: ["market": Money(minor: 9_000_00)],
            categoryNames: ["maas": "Maaş", "kira": "Kira", "market": "Market", "yemek": "Yemek & Kafe"],
            subscriptions: [SubscriptionInfo(title: "Netflix", monthlyAmount: Money(minor: 229_99), categoryID: nil),
                            SubscriptionInfo(title: "Amazon Prime Video", monthlyAmount: Money(minor: 149_90), categoryID: nil)],
            installmentPlans: [plan])
        let payload = AIPayloadBuilder.build(from: input, insights: SavingsAnalyzer.analyze(input), includeMerchants: false)

        let advice = try await GeminiAdvisor(apiKey: key, model: GeminiModel.flash.rawValue).analyze(payload: payload)

        #expect(!advice.summary.isEmpty)
        #expect(!advice.insights.isEmpty)
        #expect(advice.insights.allSatisfy { ["high", "medium", "low"].contains($0.priority) })
        #expect(!advice.nextMonthPlan.isEmpty)
        print("GEMINI_CANLI_OZET: \(advice.summary)")
        for item in advice.insights {
            print("GEMINI_CANLI_ONERI: [\(item.priority)] \(item.title) — ayda ~\(Int(item.estimatedMonthlySaving)) TL")
        }
    }
}
