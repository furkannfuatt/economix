import Foundation

/// Eldeki net nakit ve henüz ödenmemiş kart borcu.
public struct CashPosition: Hashable, Sendable {
    /// Banka/nakit hesaplarında şu an olan para. Kart harcaması düşmez; karta ödeme (transfer) düşer.
    public let cash: Money
    /// Kredi kartlarında ödenmemiş harcama; ekstre ödenince nakitten düşecek.
    public let cardDebt: Money
}

public enum CashLedger {
    /// - Parameters:
    ///   - openingBalance: Nakit tarafındaki hesapların açılış bakiyeleri toplamı.
    ///   - cashAccountIDs: Nakit sayılan (kart olmayan, arşivlenmemiş) hesaplar. Hesapsız işlem de nakit sayılır.
    ///   - cardAccountIDs: Kredi kartı hesapları.
    ///   `asOf` sonrasındaki (gelecek tarihli) işlemler sayılmaz.
    public static func position(transactions: [TxSnapshot], openingBalance: Money, cashAccountIDs: Set<String>,
                                cardAccountIDs: Set<String>, asOf date: Date) -> CashPosition {
        var cash = openingBalance
        var debt = Money.zero

        func isCash(_ id: String?) -> Bool { id.map(cashAccountIDs.contains) ?? true }
        func isCard(_ id: String?) -> Bool { id.map(cardAccountIDs.contains) ?? false }

        for tx in transactions where tx.date <= date {
            switch tx.kind {
            case .expense, .investment:
                if isCash(tx.accountID) { cash -= tx.amount } else if isCard(tx.accountID) { debt += tx.amount }
            case .income, .divestment:
                // Karta dönen para (iade, bozma) borcu azaltır.
                if isCash(tx.accountID) { cash += tx.amount } else if isCard(tx.accountID) { debt -= tx.amount }
            case .transfer:
                // Çıkış tarafı: nakit hesaptan çıkan düşer; karttan çıkan (nakit avans) borca eklenir.
                if isCash(tx.accountID) { cash -= tx.amount } else if isCard(tx.accountID) { debt += tx.amount }
                // Giriş tarafı: karta ödeme borcu azaltır; nakit hesaba giren eklenir.
                if isCard(tx.toAccountID) {
                    debt -= tx.amount
                } else if let to = tx.toAccountID, isCash(to) {
                    cash += tx.amount
                }
            }
        }
        return CashPosition(cash: cash, cardDebt: debt)
    }
}
