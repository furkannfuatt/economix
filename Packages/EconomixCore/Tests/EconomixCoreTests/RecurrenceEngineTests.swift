import Foundation
import Testing
@testable import EconomixCore

@Suite("Düzenli işlemler")
struct RecurrenceEngineTests {
    @Test("Aylık 31: kısa aylarda son gün")
    func monthlyClamped() {
        let rule = RecurrenceRule(frequency: .monthly, startDate: d(2027, 1, 15), dayOfMonth: 31)
        let dates = RecurrenceEngine.occurrences(of: rule, after: nil, through: d(2027, 4, 30))
        #expect(dates == [d(2027, 1, 31), d(2027, 2, 28), d(2027, 3, 31), d(2027, 4, 30)])
    }

    @Test("Başlangıçtan önceki gün atlanır")
    func monthlySkipsBeforeStart() {
        let rule = RecurrenceRule(frequency: .monthly, startDate: d(2027, 1, 10), dayOfMonth: 5)
        let dates = RecurrenceEngine.occurrences(of: rule, after: nil, through: d(2027, 3, 4))
        #expect(dates == [d(2027, 2, 5)])
    }

    @Test("Son üretimden sonraki kaçırılan vadeler")
    func catchUp() {
        let rule = RecurrenceRule(frequency: .monthly, startDate: d(2026, 1, 1), dayOfMonth: 5)
        let dates = RecurrenceEngine.occurrences(of: rule, after: d(2026, 7, 5), through: d(2026, 10, 18))
        #expect(dates == [d(2026, 8, 5), d(2026, 9, 5), d(2026, 10, 5)])
    }

    @Test("Bitiş tarihi sonrası üretilmez")
    func respectsEnd() {
        let rule = RecurrenceRule(frequency: .monthly, startDate: d(2026, 1, 1), endDate: d(2026, 3, 10), dayOfMonth: 10)
        let dates = RecurrenceEngine.occurrences(of: rule, after: nil, through: d(2026, 12, 31))
        #expect(dates == [d(2026, 1, 10), d(2026, 2, 10), d(2026, 3, 10)])
    }

    @Test("Haftalık")
    func weekly() {
        let rule = RecurrenceRule(frequency: .weekly, startDate: d(2026, 10, 5), dayOfMonth: 1)
        let dates = RecurrenceEngine.occurrences(of: rule, after: nil, through: d(2026, 10, 20))
        #expect(dates == [d(2026, 10, 5), d(2026, 10, 12), d(2026, 10, 19)])
    }

    @Test("Yıllık")
    func yearly() {
        let rule = RecurrenceRule(frequency: .yearly, startDate: d(2026, 3, 1), dayOfMonth: 15)
        let dates = RecurrenceEngine.occurrences(of: rule, after: nil, through: d(2028, 6, 1))
        #expect(dates == [d(2026, 3, 15), d(2027, 3, 15), d(2028, 3, 15)])
    }

    @Test("Bir sonraki vade")
    func next() {
        let rule = RecurrenceRule(frequency: .monthly, startDate: d(2026, 1, 1), dayOfMonth: 20)
        #expect(RecurrenceEngine.nextOccurrence(of: rule, after: d(2026, 10, 18)) == d(2026, 10, 20))
        #expect(RecurrenceEngine.nextOccurrence(of: rule, after: d(2026, 10, 20)) == d(2026, 11, 20))
    }

    @Test("Aylık karşılık")
    func monthlyEquivalent() {
        #expect(Frequency.weekly.monthlyEquivalent(of: tl(100)) == Money(minor: 43_333))
        #expect(Frequency.yearly.monthlyEquivalent(of: tl(1_200)) == tl(100))
        #expect(Frequency.monthly.monthlyEquivalent(of: tl(250)) == tl(250))
    }
}
