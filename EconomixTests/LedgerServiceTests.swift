import Foundation
import SwiftData
import Testing
import EconomixCore
@testable import Economix

private func d(_ y: Int, _ m: Int, _ day: Int) -> Date {
    FinanceCalendar.calendar.date(from: DateComponents(year: y, month: m, day: day))!
}

private func tl(_ lira: Int) -> Money { Money(minor: lira * 100) }

@MainActor
struct Fixture {
    let container = ModelContainerFactory.make(.inMemory)
    var context: ModelContext { container.mainContext }
    var service: LedgerService { LedgerService(context: context) }

    func makeCard() -> Account {
        let card = Account(name: "Bonus", type: .creditCard)
        card.statementDay = 15
        context.insert(card)
        return card
    }

    func makeCategory(_ name: String = "Elektronik") -> EntryCategory {
        let category = EntryCategory(name: name, icon: "iphone", colorHex: "#0A84FF", kind: .expense)
        context.insert(category)
        return category
    }
}

@Suite("LedgerService")
@MainActor
struct LedgerServiceTests {
    @Test("Taksitli alım plan ve aylık işlemler üretir")
    func installmentPurchase() throws {
        let f = Fixture()
        let card = f.makeCard(), category = f.makeCategory()
        let plan = try f.service.addInstallmentPurchase(total: tl(12_000), count: 6, purchaseDate: d(2026, 9, 15),
                                                        category: category, account: card, merchant: "TEKNOSA")
        let entries = plan.sortedEntries
        #expect(entries.count == 6)
        #expect(entries.map(\.installmentIndex) == [1, 2, 3, 4, 5, 6])
        #expect(entries.map(\.date) == [d(2026, 9, 15), d(2026, 10, 15), d(2026, 11, 15),
                                        d(2026, 12, 15), d(2027, 1, 15), d(2027, 2, 15)])
        #expect(entries.allSatisfy { $0.amount == tl(2_000) && $0.account === card && $0.category === category })
        #expect(entries.allSatisfy { $0.source == .installment && $0.kind == .expense })
        #expect(entries[1].installmentLabel == "Taksit 2/6")
        #expect(entries[0].snapshot.installment?.planTotal == tl(12_000))
    }

    @Test("Erken kapatma kalan taksitleri tek işlemde toplar")
    func closeEarly() throws {
        let f = Fixture()
        let plan = try f.service.addInstallmentPurchase(total: tl(6_000), count: 6, purchaseDate: d(2026, 8, 10),
                                                        category: f.makeCategory(), account: f.makeCard(), merchant: "")
        try f.service.closeEarly(plan, on: d(2026, 10, 20))
        let entries = plan.sortedEntries
        #expect(entries.count == 4)
        #expect(entries.last?.amount == tl(3_000))
        #expect(entries.last?.date == d(2026, 10, 20))
        #expect(entries.map(\.amount).sum() == tl(6_000))
        #expect(plan.closedEarlyAt == d(2026, 10, 20))
    }

    @Test("Plan düzenlenince taksitler yeniden üretilir")
    func updatePlan() throws {
        let f = Fixture()
        let plan = try f.service.addInstallmentPurchase(total: tl(6_000), count: 6, purchaseDate: d(2026, 8, 10),
                                                        category: f.makeCategory(), account: f.makeCard(), merchant: "")
        try f.service.updatePlan(plan, total: tl(9_000), count: 3, purchaseDate: d(2026, 8, 10))
        #expect(plan.sortedEntries.map(\.amount) == [tl(3_000), tl(3_000), tl(3_000)])
        #expect(try f.context.fetchCount(FetchDescriptor<LedgerEntry>()) == 3)
    }

    @Test("Plan silinince taksit işlemleri de silinir")
    func deletePlan() throws {
        let f = Fixture()
        let plan = try f.service.addInstallmentPurchase(total: tl(3_000), count: 3, purchaseDate: d(2026, 8, 10),
                                                        category: nil, account: f.makeCard(), merchant: "")
        try f.service.deletePlan(plan)
        #expect(try f.context.fetchCount(FetchDescriptor<LedgerEntry>()) == 0)
        #expect(try f.context.fetchCount(FetchDescriptor<InstallmentPlan>()) == 0)
    }

    @Test("İşyeri kategorisi öğrenilir ve güncellenir, çift kural oluşmaz")
    func learnsMerchant() throws {
        let f = Fixture()
        let market = f.makeCategory("Market"), food = f.makeCategory("Yemek")
        try f.service.learnCategory(merchant: "Migros Kadıköy", category: market)
        try f.service.learnCategory(merchant: "MIGROS KADIKOY", category: food)
        let rules = try f.context.fetch(FetchDescriptor<MerchantRule>())
        #expect(rules.count == 1)
        #expect(rules[0].pattern == "MIGROS KADIKOY")
        #expect(rules[0].category === food)
    }
}

@Suite("SeedService")
@MainActor
struct SeedServiceTests {
    @Test("Varsayılanlar iki kez yüklense de çift oluşmaz")
    func idempotent() throws {
        let f = Fixture()
        try SeedService.seedDefaults(in: f.context)
        try SeedService.seedDefaults(in: f.context)
        #expect(try f.context.fetchCount(FetchDescriptor<EntryCategory>()) == SeedService.categories.count)
        #expect(try f.context.fetchCount(FetchDescriptor<Account>()) == 1)
    }

    @Test("iCloud'dan gelen kopyalar birleştirilir, işlemler korunur")
    func deduplicates() throws {
        let f = Fixture()
        let first = EntryCategory(name: "Market", icon: "cart", colorHex: "#000", kind: .expense, seedKey: "market")
        first.createdAt = d(2026, 1, 1)
        let copy = EntryCategory(name: "Market", icon: "cart", colorHex: "#000", kind: .expense, seedKey: "market")
        copy.createdAt = d(2026, 5, 1)
        f.context.insert(first)
        f.context.insert(copy)
        let entry = try f.service.addEntry(amount: tl(100), kind: .expense, date: d(2026, 5, 2),
                                           category: copy, account: nil)
        try SeedService.deduplicate(in: f.context)

        let categories = try f.context.fetch(FetchDescriptor<EntryCategory>())
        #expect(categories.count == 1)
        #expect(entry.category === categories[0])
    }
}
