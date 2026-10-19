import Foundation
import Testing
@testable import EcoomixCore

@Suite("Kart özeti")
struct CardLedgerTests {
    let card = "bonus"
    let cycle = CardCycle(statementDay: 15, dueOffsetDays: 10)

    func charge(_ lira: Int, _ date: Date, kind: TxKind = .expense, plan: InstallmentRef? = nil) -> TxSnapshot {
        TxSnapshot(id: UUID().uuidString, amount: tl(lira), kind: kind, date: date, categoryID: nil,
                   accountID: card, merchant: "", installment: plan)
    }

    @Test("Son ekstre, ödeme, açık dönem ve gelecek taksitler")
    func summary() {
        let ref = InstallmentRef(planID: "p", purchaseDate: d(2026, 10, 5), planTotal: tl(3_000))
        var txs = [
            charge(1_000, d(2026, 9, 20)),
            charge(500, d(2026, 10, 1)),
            charge(200, d(2026, 10, 3), kind: .income), // iade
            charge(300, d(2026, 10, 19)),
            TxSnapshot(id: "pay", amount: tl(800), kind: .transfer, date: d(2026, 10, 18), categoryID: nil,
                       accountID: "vadesiz", toAccountID: card, merchant: ""),
            // Başka kartın harcaması sayılmaz
            TxSnapshot(id: "x", amount: tl(9_999), kind: .expense, date: d(2026, 10, 1), categoryID: nil,
                       accountID: "world", merchant: ""),
        ]
        txs += InstallmentScheduler.schedule(total: tl(3_000), count: 3, purchaseDate: d(2026, 10, 5))
            .map { charge($0.amount.minor / 100, $0.date, plan: ref) }

        let s = CardLedger.summary(cardID: card, cycle: cycle, transactions: txs, asOf: d(2026, 10, 20))
        #expect(s.lastStatement.closingDate == d(2026, 10, 15))
        #expect(s.lastStatement.dueDate == d(2026, 10, 25))
        #expect(s.lastStatementTotal == tl(2_300))
        #expect(s.paidSinceClosing == tl(800))
        #expect(s.remainingDue == tl(1_500))
        #expect(s.openPeriodSpending == tl(1_300))
        #expect(s.futureInstallments == tl(1_000))
        #expect(s.usedLimit == tl(3_800))
    }

    @Test("Kartla yapılan yatırım alımı kart borcuna eklenir")
    func investmentOnCard() {
        let s = CardLedger.summary(cardID: card, cycle: cycle,
                                   transactions: [charge(1_000, d(2026, 10, 1)), charge(2_000, d(2026, 10, 3), kind: .investment)],
                                   asOf: d(2026, 10, 18))
        #expect(s.lastStatementTotal == tl(3_000))
    }

    @Test("Fazla ödeme kalan borcu eksiye düşürmez")
    func overpayment() {
        let txs = [
            charge(1_000, d(2026, 10, 1)),
            TxSnapshot(id: "pay", amount: tl(1_500), kind: .transfer, date: d(2026, 10, 18), categoryID: nil,
                       accountID: "vadesiz", toAccountID: card, merchant: ""),
        ]
        let s = CardLedger.summary(cardID: card, cycle: cycle, transactions: txs, asOf: d(2026, 10, 20))
        #expect(s.remainingDue == .zero)
    }
}
