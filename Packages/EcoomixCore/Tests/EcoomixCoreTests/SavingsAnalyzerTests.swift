import Foundation
import Testing
@testable import EcoomixCore

private func exp(_ lira: Int, _ date: Date, _ category: String, merchant: String = "") -> TxSnapshot {
    TxSnapshot(id: UUID().uuidString, amount: tl(lira), kind: .expense, date: date, categoryID: category,
               accountID: nil, merchant: merchant)
}

private func inc(_ lira: Int, _ date: Date) -> TxSnapshot {
    TxSnapshot(id: UUID().uuidString, amount: tl(lira), kind: .income, date: date, categoryID: "maas",
               accountID: nil, merchant: "")
}

/// Ekim 2026 ortası; geçen tam ay Eylül, önceki üç ay Haziran–Ağustos.
private let asOf = d(2026, 10, 18, hour: 12)
private let names = ["market": "Market", "yemek": "Yemek & Kafe", "abonelik": "Abonelikler", "kira": "Kira"]

private func salaries() -> [TxSnapshot] {
    (6...10).map { inc(50_000, d(2026, $0, 1)) }
}

private func analyze(_ txs: [TxSnapshot], budgets: [String: Money] = [:], subscriptions: [SubscriptionInfo] = [],
                     plans: [PlanSchedule] = []) -> [Insight] {
    SavingsAnalyzer.analyze(AnalysisInput(transactions: txs, asOf: asOf, budgets: budgets, categoryNames: names,
                                          subscriptions: subscriptions, installmentPlans: plans))
}

@Suite("Tasarruf analizi")
struct SavingsAnalyzerTests {
    @Test("Bütçe aşıldıysa kritik uyarı")
    func budgetExceeded() {
        let insights = analyze(salaries() + [exp(9_500, d(2026, 10, 10), "market")], budgets: ["market": tl(9_000)])
        let insight = insights.first { $0.kind == .budgetPace }
        #expect(insight?.severity == .critical)
        #expect(insight?.title == "Market bütçesi aşıldı")
        #expect(insight?.categoryID == "market")
    }

    @Test("Gidişata göre aşılacaksa uyarı ve fark kadar tasarruf tahmini")
    func budgetPace() {
        // 18 günde 6.000 → ay sonu 6.000 × 31 / 18 = 10.333,33
        let insights = analyze(salaries() + [exp(6_000, d(2026, 10, 5), "market")], budgets: ["market": tl(9_000)])
        let insight = insights.first { $0.kind == .budgetPace }
        #expect(insight?.severity == .warning)
        #expect(insight?.estimatedMonthlySaving == Money(minor: 133_333))
    }

    @Test("Bütçe rahatsa uyarı yok")
    func budgetFine() {
        let insights = analyze(salaries() + [exp(2_000, d(2026, 10, 5), "market")], budgets: ["market": tl(9_000)])
        #expect(!insights.contains { $0.kind == .budgetPace })
    }

    @Test("Geçen ay kategori harcaması önceki 3 ay ortalamasından belirgin yüksekse")
    func categoryIncrease() {
        var txs = salaries()
        for month in 6...8 { txs.append(exp(4_000, d(2026, month, 10), "yemek")) }
        txs.append(exp(6_000, d(2026, 9, 10), "yemek"))
        let insight = analyze(txs).first { $0.kind == .categoryIncrease }
        #expect(insight?.categoryID == "yemek")
        #expect(insight?.estimatedMonthlySaving == tl(2_000))
        #expect(insight?.message.contains("%50") == true)
    }

    @Test("Küçük artış uyarı üretmez")
    func smallIncreaseIgnored() {
        var txs = salaries()
        for month in 6...8 { txs.append(exp(1_000, d(2026, month, 10), "yemek")) }
        txs.append(exp(1_400, d(2026, 9, 10), "yemek")) // %40 ama yalnızca 400 ₺
        #expect(!analyze(txs).contains { $0.kind == .categoryIncrease })
    }

    @Test("Aynı türde iki abonelik mükerrer sayılır")
    func duplicateSubscriptions() {
        let subs = [SubscriptionInfo(title: "Netflix", monthlyAmount: Money(minor: 229_99), categoryID: "abonelik"),
                    SubscriptionInfo(title: "Amazon Prime Video", monthlyAmount: Money(minor: 149_90), categoryID: "abonelik"),
                    SubscriptionInfo(title: "Spotify", monthlyAmount: Money(minor: 99_99), categoryID: "abonelik")]
        let insights = analyze(salaries(), subscriptions: subs)
        let duplicate = insights.first { $0.kind == .duplicateSubscriptions }
        #expect(duplicate?.estimatedMonthlySaving == Money(minor: 149_90))
        #expect(duplicate?.message.contains("Netflix") == true)
        let total = insights.first { $0.kind == .subscriptions }
        #expect(total?.message.contains("479,88 ₺") == true)
    }

    @Test("Taksit yükü gelirin %25'ini aşarsa uyarı")
    func installmentLoad() {
        let plan = PlanSchedule(id: "p", title: "Telefon",
                                lines: InstallmentScheduler.schedule(total: tl(90_000), count: 6, purchaseDate: d(2026, 9, 1)))
        let insight = analyze(salaries(), plans: [plan]).first { $0.kind == .installmentLoad }
        #expect(insight?.severity == .warning)
        #expect(insight?.message.contains("%30") == true)
    }

    @Test("Yaklaşan taksit bitişi bilgi olarak gösterilir")
    func installmentRelief() {
        let plan = PlanSchedule(id: "p", title: "Koltuk",
                                lines: InstallmentScheduler.schedule(total: tl(6_000), count: 3, purchaseDate: d(2026, 9, 1)))
        let insight = analyze(salaries(), plans: [plan]).first { $0.kind == .installmentRelief }
        #expect(insight?.severity == .info)
        #expect(insight?.title.contains("Aralık") == true)
    }

    @Test("Son 30 günde sık küçük harcamalar: yarısı tasarruf potansiyeli")
    func smallFrequent() {
        var txs = salaries()
        for day in 1...12 { txs.append(exp(150, d(2026, 10, day), "yemek", merchant: "Starbucks")) }
        let insight = analyze(txs).first { $0.kind == .smallFrequent }
        #expect(insight?.categoryID == "yemek")
        #expect(insight?.estimatedMonthlySaving == tl(900))
    }

    @Test("Düşük tasarruf oranı uyarısı ve hedefe kalan fark")
    func lowSavingsRate() {
        var txs = salaries()
        txs.append(exp(46_000, d(2026, 9, 15), "kira"))
        let insight = analyze(txs).first { $0.kind == .savingsRate }
        #expect(insight?.severity == .warning)
        #expect(insight?.message.contains("%8") == true)
        #expect(insight?.estimatedMonthlySaving == tl(6_000))
    }

    @Test("Harcama gelirden fazlaysa kritik")
    func negativeSavings() {
        var txs = salaries()
        txs.append(exp(60_000, d(2026, 9, 15), "kira"))
        #expect(analyze(txs).first { $0.kind == .savingsRate }?.severity == .critical)
    }

    @Test("Öneriler önem ve tasarruf tutarına göre sıralanır")
    func ordering() {
        var txs = salaries() + [exp(9_500, d(2026, 10, 10), "market"), exp(46_000, d(2026, 9, 15), "kira")]
        for day in 1...12 { txs.append(exp(150, d(2026, 10, day), "yemek")) }
        let insights = analyze(txs, budgets: ["market": tl(9_000)])
        let severities = insights.map(\.severity.rawValue)
        #expect(severities == severities.sorted(by: >))
        #expect(insights.first?.kind == .budgetPace)
    }
}
