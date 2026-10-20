import Foundation
import SwiftData
import Testing
import EconomixCore
@testable import Economix

private func d(_ y: Int, _ m: Int, _ day: Int, hour: Int = 0) -> Date {
    FinanceCalendar.calendar.date(from: DateComponents(year: y, month: m, day: day, hour: hour))!
}

@Suite("RecurringGenerator")
@MainActor
struct RecurringGeneratorTests {
    func makeNetflix(_ f: Fixture) -> RecurringItem {
        let item = RecurringItem(title: "Netflix", amount: Money(minor: 229_99), kind: .expense, frequency: .monthly,
                                 dayOfMonth: 5, startDate: d(2026, 1, 1), isSubscription: true)
        f.context.insert(item)
        item.category = f.makeCategory("Abonelikler")
        item.account = f.makeCard()
        return item
    }

    func entries(_ f: Fixture) throws -> [LedgerEntry] {
        try f.context.fetch(FetchDescriptor<LedgerEntry>(sortBy: [SortDescriptor(\.date)]))
    }

    @Test("Kaçırılan vadeleri üretir ve son üretim tarihini işaretler")
    func generatesMissed() throws {
        let f = Fixture()
        let item = makeNetflix(f)
        let count = try RecurringGenerator(context: f.context).run(asOf: d(2026, 3, 10, hour: 9))
        let all = try entries(f)
        #expect(count == 3)
        #expect(all.map(\.date) == [d(2026, 1, 5), d(2026, 2, 5), d(2026, 3, 5)])
        #expect(all.allSatisfy { $0.recurringItem === item && $0.source == .recurring })
        #expect(all.allSatisfy { $0.amount == Money(minor: 229_99) && $0.merchant == "Netflix" })
        #expect(all.allSatisfy { $0.category === item.category && $0.account === item.account })
        #expect(item.lastGeneratedDate == d(2026, 3, 5))
    }

    @Test("Tekrar çalışınca çift kayıt oluşmaz")
    func idempotent() throws {
        let f = Fixture()
        _ = makeNetflix(f)
        let generator = RecurringGenerator(context: f.context)
        try generator.run(asOf: d(2026, 3, 10))
        #expect(try generator.run(asOf: d(2026, 3, 20)) == 0)
        #expect(try entries(f).count == 3)
    }

    @Test("Pasif kalem üretilmez")
    func inactive() throws {
        let f = Fixture()
        makeNetflix(f).isActive = false
        #expect(try RecurringGenerator(context: f.context).run(asOf: d(2026, 3, 10)) == 0)
    }

    @Test("Fiyat değişikliği yalnızca sonraki vadeleri etkiler")
    func priceChange() throws {
        let f = Fixture()
        let item = makeNetflix(f)
        let generator = RecurringGenerator(context: f.context)
        try generator.run(asOf: d(2026, 2, 10))
        item.amount = Money(minor: 279_99)
        try generator.run(asOf: d(2026, 3, 10))
        #expect(try entries(f).map(\.amount.minor) == [229_99, 229_99, 279_99])
    }

    @Test("Geçmiş ödemeler istenmezse yalnızca bugünden itibaren üretilir")
    func skipPast() throws {
        let f = Fixture()
        let item = makeNetflix(f)
        item.skipPastOccurrences(asOf: d(2026, 3, 5, hour: 14))
        try RecurringGenerator(context: f.context).run(asOf: d(2026, 4, 6))
        #expect(try entries(f).map(\.date) == [d(2026, 3, 5), d(2026, 4, 5)])
    }
}
