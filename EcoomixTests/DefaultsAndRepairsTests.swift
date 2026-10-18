import Foundation
import SwiftData
import Testing
import EcoomixCore
@testable import Ecoomix

@Suite("Varsayılanlar ve onarımlar")
@MainActor
struct NewDefaultsAndRepairsTests {
    let f = Fixture()
    let defaults: UserDefaults = {
        let name = "seed-tests-\(UUID().uuidString)"
        return UserDefaults(suiteName: name)!
    }()

    func seededKeys() throws -> [String] {
        try f.context.fetch(FetchDescriptor<EntryCategory>()).compactMap(\.seedKey)
    }

    @Test("Varsayılanlarda Online Alışveriş, gelirde Burs, giderde Yatırım var")
    func newSeeds() {
        #expect(SeedService.categories.contains { $0.key == "online" && $0.name == "Online Alışveriş" && $0.kind == .expense })
        #expect(SeedService.categories.contains { $0.key == "burs" && $0.name == "Burs" && $0.kind == .income })
        #expect(SeedService.categories.contains { $0.key == "yatirim-gider" && $0.name == "Yatırım" && $0.kind == .expense })
        #expect(Set(SeedService.categories.map(\.key)).count == SeedService.categories.count, "Anahtarlar tekil")
    }

    @Test("Burs ve Yatırım mevcut kuruluma eklenir")
    func addsScholarshipAndInvestment() throws {
        f.context.insert(EntryCategory(name: "Market", icon: "cart", colorHex: "#000", kind: .expense, seedKey: "market"))
        try SeedService.addNewDefaults(in: f.context, defaults: defaults)
        let categories = try f.context.fetch(FetchDescriptor<EntryCategory>())
        #expect(categories.contains { $0.seedKey == "burs" && $0.kind == .income })
        #expect(categories.contains { $0.seedKey == "yatirim-gider" && $0.kind == .expense })
    }

    @Test("Sonradan eklenen varsayılan kategori mevcut kuruluma bir kez eklenir")
    func addsNewDefaultsOnce() throws {
        f.context.insert(EntryCategory(name: "Market", icon: "cart", colorHex: "#000", kind: .expense, seedKey: "market"))
        try SeedService.addNewDefaults(in: f.context, defaults: defaults)
        #expect(try seededKeys().filter { $0 == "online" }.count == 1)

        // Kullanıcı silerse bir daha eklenmez.
        for category in try f.context.fetch(FetchDescriptor<EntryCategory>()) where category.seedKey == "online" {
            f.context.delete(category)
        }
        try SeedService.addNewDefaults(in: f.context, defaults: defaults)
        #expect(!(try seededKeys()).contains("online"))
    }

    @Test("Henüz kurulum yapılmadıysa (varsayılan kategori yok) bir şey eklenmez")
    func skipsBeforeOnboarding() throws {
        try SeedService.addNewDefaults(in: f.context, defaults: defaults)
        #expect(try seededKeys().isEmpty)
    }

    @Test("Taksit yazısının taksi sanılmasından kalan kural ve kategoriler düzeltilir")
    func repairsInstallmentTaxiBug() throws {
        let card = f.makeCard()
        let transport = EntryCategory(name: "Ulaşım", icon: "car", colorHex: "#000", kind: .expense, seedKey: "ulasim")
        let online = EntryCategory(name: "Online Alışveriş", icon: "bag", colorHex: "#000", kind: .expense, seedKey: "online")
        f.context.insert(transport)
        f.context.insert(online)
        let service = LedgerService(context: f.context)
        let merchant = "HEPSIPAY/HEPSIBU (1,500.00 TL) 3/3.taksit"
        try service.learnCategory(merchant: merchant, category: transport)
        try service.learnCategory(merchant: "SARI TAKSI", category: transport)
        let plan = try service.addInstallmentPurchase(total: Money(minor: 150_000), count: 3, purchaseDate: .now,
                                                      category: transport, account: card, merchant: merchant)
        let taxi = try service.addEntry(amount: Money(minor: 20_000), kind: .expense, date: .now, category: transport,
                                        account: card, merchant: "SARI TAKSI", source: .imported)

        try DataRepairs.run(in: f.context, defaults: defaults)

        let rules = try f.context.fetch(FetchDescriptor<MerchantRule>())
        #expect(rules.map(\.pattern) == ["SARI TAKSI"])
        #expect(plan.category === online)
        #expect(plan.sortedEntries.allSatisfy { $0.category === online })
        #expect(taxi.category === transport, "Gerçek taksi yerinde kalır")
    }
}
