import Foundation
import Testing
@testable import EconomixCore

@Suite("Hesap kesim döngüsü")
struct StatementCycleTests {
    let card = CardCycle(statementDay: 15, dueOffsetDays: 10)

    @Test("Kesim gününden önceki alım o ayın ekstresine düşer")
    func beforeClosing() {
        let s = card.statement(containing: d(2026, 10, 10, hour: 14))
        #expect(s.closingDate == d(2026, 10, 15))
        #expect(s.dueDate == d(2026, 10, 25))
        #expect(s.closingMonth == YearMonth(year: 2026, month: 10))
    }

    @Test("Kesim günündeki alım o ayın ekstresine dahildir")
    func onClosingDay() {
        #expect(card.statement(containing: d(2026, 10, 15, hour: 23)).closingDate == d(2026, 10, 15))
    }

    @Test("Kesimden sonraki alım bir sonraki ekstreye düşer")
    func afterClosing() {
        let s = card.statement(containing: d(2026, 10, 16))
        #expect(s.closingDate == d(2026, 11, 15))
        #expect(s.periodStart == d(2026, 10, 16))
    }

    @Test("Aralık kesimi yılı devreder")
    func yearRollover() {
        #expect(card.statement(containing: d(2026, 12, 20)).closingDate == d(2027, 1, 15))
    }

    @Test("31 kesim günü kısa aylarda son güne çekilir")
    func clampsShortMonths() {
        let lastDay = CardCycle(statementDay: 31, dueOffsetDays: 10)
        #expect(lastDay.statement(containing: d(2027, 2, 10)).closingDate == d(2027, 2, 28))
        let march = lastDay.statement(containing: d(2027, 3, 1))
        #expect(march.closingDate == d(2027, 3, 31))
        #expect(march.periodStart == d(2027, 3, 1))
    }

    @Test("30 kesim günü: 31 Ocak alımı Şubat sonuna düşer")
    func day30() {
        let c = CardCycle(statementDay: 30, dueOffsetDays: 10)
        #expect(c.statement(containing: d(2027, 1, 31)).closingDate == d(2027, 2, 28))
    }

    @Test("Son kesilen ekstre ve açık dönem")
    func lastClosedAndOpen() {
        #expect(card.lastClosedStatement(asOf: d(2026, 10, 20)).closingDate == d(2026, 10, 15))
        #expect(card.statement(containing: d(2026, 10, 20)).closingDate == d(2026, 11, 15))
        // Kesim günü henüz bitmedi: son kesilen bir önceki ay
        #expect(card.lastClosedStatement(asOf: d(2026, 10, 15, hour: 12)).closingDate == d(2026, 9, 15))
    }

    @Test("Ekstre dönemi içerme kontrolü")
    func periodContains() {
        let s = card.statement(closingIn: YearMonth(year: 2026, month: 11))
        #expect(s.period.contains(d(2026, 10, 16)))
        #expect(s.period.contains(d(2026, 11, 15, hour: 23)))
        #expect(!s.period.contains(d(2026, 11, 16)))
        #expect(!s.period.contains(d(2026, 10, 15)))
    }
}
