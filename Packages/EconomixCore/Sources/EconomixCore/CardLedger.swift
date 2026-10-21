import Foundation

public struct CardSummary: Hashable, Sendable {
    public let openStatement: CardStatement
    public let lastStatement: CardStatement
    /// Açık dönemde biriken harcama (bir sonraki ekstreye girecek).
    public let openPeriodSpending: Money
    /// Son kesilen ekstrenin tutarı.
    public let lastStatementTotal: Money
    /// Son kesimden sonra karta yapılan ödemeler.
    public let paidSinceClosing: Money
    /// Açık dönemden sonraki ekstrelere düşecek taksitler.
    public let futureInstallments: Money

    /// Son ekstreden kalan ödenecek tutar.
    public var remainingDue: Money { max(.zero, lastStatementTotal - paidSinceClosing) }
    /// Limitten kullanılan yaklaşık tutar (bankalar taksitlerin tamamını limitten düşer).
    public var usedLimit: Money { remainingDue + openPeriodSpending + futureInstallments }
}

public enum CardLedger {
    public static func summary(cardID: String, cycle: CardCycle, transactions: [TxSnapshot], asOf date: Date,
                               calendar: Calendar = FinanceCalendar.calendar) -> CardSummary {
        let open = cycle.statement(containing: date, calendar: calendar)
        let last = cycle.lastClosedStatement(asOf: date, calendar: calendar)

        var lastTotal = Money.zero, openSpending = Money.zero, future = Money.zero, paid = Money.zero

        for tx in transactions {
            // Karta ödeme
            if tx.kind == .transfer, tx.toAccountID == cardID {
                if open.period.contains(tx.date) { paid += tx.amount }
                continue
            }
            guard tx.accountID == cardID else { continue }

            let signed: Money = switch tx.kind {
            case .expense, .investment, .transfer: tx.amount // transfer: karttan nakit avans
            case .income, .divestment: -tx.amount // iade ya da karta dönen yatırım
            }

            if last.period.contains(tx.date) {
                lastTotal += signed
            } else if open.period.contains(tx.date) {
                openSpending += signed
            } else if tx.date >= open.period.end, tx.installment != nil {
                future += signed
            }
        }

        return CardSummary(openStatement: open, lastStatement: last, openPeriodSpending: openSpending,
                           lastStatementTotal: lastTotal, paidSinceClosing: paid, futureInstallments: future)
    }
}
