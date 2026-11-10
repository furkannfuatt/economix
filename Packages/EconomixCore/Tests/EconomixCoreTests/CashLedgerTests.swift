import Foundation
import Testing
@testable import EconomixCore

@Suite("Net nakit")
struct CashLedgerTests {
    func tx(_ lira: Int, _ kind: TxKind, from: String?, to: String? = nil, _ date: Date = d(2026, 10, 10)) -> TxSnapshot {
        TxSnapshot(id: UUID().uuidString, amount: tl(lira), kind: kind, date: date, categoryID: nil,
                   accountID: from, toAccountID: to, merchant: "")
    }

    func position(_ txs: [TxSnapshot]) -> CashPosition {
        CashLedger.position(transactions: txs, openingBalance: tl(1_000), cashAccountIDs: ["vadesiz"],
                            cardAccountIDs: ["kart"], asOf: d(2026, 10, 20))
    }

    @Test("Kart harcaması nakitten düşmez, borca yazılır")
    func cardSpendingIsDebt() {
        let p = position([tx(5_000, .income, from: "vadesiz"), tx(300, .expense, from: "vadesiz"),
                          tx(700, .expense, from: "kart")])
        #expect(p.cash == tl(5_700))
        #expect(p.cardDebt == tl(700))
    }

    @Test("Ekstre ödemesi (transfer) nakitten düşer, borcu azaltır")
    func statementPayment() {
        let p = position([tx(5_000, .income, from: "vadesiz"), tx(700, .expense, from: "kart"),
                          tx(700, .transfer, from: "vadesiz", to: "kart")])
        #expect(p.cash == tl(5_300))
        #expect(p.cardDebt == .zero)
    }

    @Test("Karta iade borcu azaltır; yatırım karttan nakdi değiştirmez")
    func refundAndInvestment() {
        let p = position([tx(500, .expense, from: "kart"), tx(100, .income, from: "kart"),
                          tx(200, .investment, from: "kart"), tx(150, .investment, from: "vadesiz")])
        #expect(p.cash == tl(850))
        #expect(p.cardDebt == tl(600))
    }

    @Test("Gelecek tarihli işlemler sayılmaz")
    func ignoresFuture() {
        let p = position([tx(400, .expense, from: "vadesiz", d(2026, 11, 1))])
        #expect(p.cash == tl(1_000))
    }
}
