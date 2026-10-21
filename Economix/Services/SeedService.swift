import Foundation
import SwiftData
import EconomixCore

struct CategorySeed {
    let key: String
    let name: String
    let icon: String
    let color: String
    let kind: TxKind
}

enum SeedService {
    static let categories: [CategorySeed] = [
        .init(key: "market", name: "Market", icon: "cart.fill", color: "#34C759", kind: .expense),
        .init(key: "online", name: "Online Alışveriş", icon: "shippingbox.fill", color: "#00C7BE", kind: .expense),
        .init(key: "yemek", name: "Yemek & Kafe", icon: "fork.knife", color: "#FF9500", kind: .expense),
        .init(key: "ulasim", name: "Ulaşım & Yakıt", icon: "car.fill", color: "#32ADE6", kind: .expense),
        .init(key: "kira", name: "Kira", icon: "house.fill", color: "#AF52DE", kind: .expense),
        .init(key: "fatura", name: "Faturalar", icon: "bolt.fill", color: "#FFB800", kind: .expense),
        .init(key: "abonelik", name: "Abonelikler", icon: "play.rectangle.fill", color: "#FF2D55", kind: .expense),
        .init(key: "giyim", name: "Giyim", icon: "tshirt.fill", color: "#FF6482", kind: .expense),
        .init(key: "saglik", name: "Sağlık", icon: "cross.case.fill", color: "#FF3B30", kind: .expense),
        .init(key: "egitim", name: "Eğitim", icon: "book.fill", color: "#5856D6", kind: .expense),
        .init(key: "eglence", name: "Eğlence", icon: "gamecontroller.fill", color: "#BF5AF2", kind: .expense),
        .init(key: "elektronik", name: "Elektronik", icon: "iphone", color: "#0A84FF", kind: .expense),
        .init(key: "ev", name: "Ev & Yaşam", icon: "sofa.fill", color: "#A2845E", kind: .expense),
        .init(key: "bakim", name: "Kişisel Bakım", icon: "sparkles", color: "#FF9F0A", kind: .expense),
        .init(key: "hediye", name: "Hediye", icon: "gift.fill", color: "#FF375F", kind: .expense),
        .init(key: "seyahat", name: "Seyahat", icon: "airplane", color: "#64D2FF", kind: .expense),
        .init(key: "diger-gider", name: "Diğer", icon: "ellipsis.circle.fill", color: "#8E8E93", kind: .expense),
        .init(key: "maas", name: "Maaş", icon: "banknote.fill", color: "#30A46C", kind: .income),
        .init(key: "burs", name: "Burs", icon: "graduationcap.fill", color: "#BF5AF2", kind: .income),
        .init(key: "ek-gelir", name: "Ek Gelir", icon: "plus.circle.fill", color: "#32ADE6", kind: .income),
        .init(key: "freelance", name: "Freelance", icon: "laptopcomputer", color: "#5AC8FA", kind: .income),
        .init(key: "yatirim-alim", name: "Yatırım", icon: "chart.line.uptrend.xyaxis", color: "#9E66ED", kind: .investment),
        .init(key: "diger-gelir", name: "Diğer", icon: "ellipsis.circle.fill", color: "#8E8E93", kind: .income),
    ]

    /// Eksik varsayılan kategorileri ve "Nakit" hesabını ekler.
    static func seedDefaults(in context: ModelContext) throws {
        let existing = try context.fetch(FetchDescriptor<EntryCategory>())
        let existingKeys = Set(existing.compactMap(\.seedKey))
        for (index, seed) in categories.enumerated() where !existingKeys.contains(seed.key) {
            context.insert(EntryCategory(name: seed.name, icon: seed.icon, colorHex: seed.color, kind: seed.kind,
                                         sortOrder: index, seedKey: seed.key))
        }

        let accounts = try context.fetch(FetchDescriptor<Account>())
        if !accounts.contains(where: { $0.seedKey == "nakit" }) {
            let cash = Account(name: "Nakit", type: .cash)
            cash.colorHex = "#30A46C"
            cash.seedKey = "nakit"
            context.insert(cash)
        }
        try context.save()
    }

    /// İlk sürümden sonra eklenen varsayılan kategoriler.
    static let addedLater = ["online", "burs", "yatirim-alim"]

    /// Eskiden gelirde duran yatırım kategorisinin anahtarı ("Yatırım" → "Yatırım getirisi" → "Yatırım bozma").
    private static let legacyReturnsKey = "yatirim"
    private static let legacyReturnsNames: Set<String> = ["Yatırım", "Yatırım getirisi", "Yatırım bozma"]

    /// Yatırım önce gider kategorisi olarak eklenmişti; artık ayrı türdür (gider sayılmaz, kalandan düşülür).
    /// Kategori, kayıtları ve düzenli işlemleri yatırım türüne taşınır.
    /// Yatırım bozma da artık gelir değil ayrı türdür: gelirdeki eski yatırım kategorisinin kayıtları yatırım bozma
    /// türüne ve "Yatırım" kategorisine taşınır, boşalan kategori arşivlenir. Adı kullanıcı tarafından değiştirilmiş
    /// (ör. "Temettü") kategoriye dokunulmaz; o gerçek gelir olarak kalır.
    static func migrateInvestmentCategory(in context: ModelContext) throws {
        let categories = try context.fetch(FetchDescriptor<EntryCategory>())
        for category in categories where category.seedKey == "yatirim-gider" {
            category.seedKey = "yatirim-alim"
            category.kind = .investment
            category.monthlyLimitMinor = nil
            for entry in category.entries ?? [] where entry.kind == .expense { entry.kind = .investment }
            for item in category.recurringItems ?? [] where item.kind == .expense {
                item.kind = .investment
                item.isSubscription = false
            }
        }
        for returns in categories where returns.seedKey == legacyReturnsKey && returns.kind == .income
            && legacyReturnsNames.contains(returns.name) && !returns.isArchived {
            let target: EntryCategory
            if let existing = categories.first(where: { $0.seedKey == "yatirim-alim" && !$0.isArchived }) {
                target = existing
            } else {
                // Yatırım kategorisi yoksa bu kategori onun yerine geçer.
                returns.kind = .investment
                returns.name = "Yatırım"
                returns.seedKey = "yatirim-alim"
                target = returns
            }
            for entry in returns.entries ?? [] where entry.kind == .income {
                entry.kind = .divestment
                entry.category = target
            }
            for item in returns.recurringItems ?? [] where item.kind == .income {
                item.kind = .divestment
                item.category = target
            }
            for rule in returns.merchantRules ?? [] { rule.category = target }
            if target !== returns { returns.isArchived = true }
        }
        if context.hasChanges { try context.save() }
    }

    /// Sonradan eklenen varsayılanları mevcut kuruluma bir kez ekler; kullanıcı silerse geri gelmez.
    /// Kurulum yapılmamışsa (hiç varsayılan kategori yoksa) dokunmaz: kurulum hepsini ekler.
    static func addNewDefaults(in context: ModelContext, defaults: UserDefaults = .standard) throws {
        let keys = Set(try context.fetch(FetchDescriptor<EntryCategory>()).compactMap(\.seedKey))
        guard !keys.isEmpty else { return }
        for key in addedLater where !defaults.bool(forKey: "seed.added.\(key)") {
            defaults.set(true, forKey: "seed.added.\(key)")
            guard !keys.contains(key), let index = categories.firstIndex(where: { $0.key == key }) else { continue }
            let seed = categories[index]
            context.insert(EntryCategory(name: seed.name, icon: seed.icon, colorHex: seed.color, kind: seed.kind,
                                         sortOrder: index, seedKey: seed.key))
        }
        if context.hasChanges { try context.save() }
    }

    /// iCloud'dan gelen kopyalarla çift oluşan varsayılanları birleştirir.
    /// En eski kayıt kalır; diğerlerinin işlemleri ona taşınır.
    static func deduplicate(in context: ModelContext) throws {
        let categories = try context.fetch(FetchDescriptor<EntryCategory>(sortBy: [SortDescriptor(\.createdAt)]))
        var keepers: [String: EntryCategory] = [:]
        for category in categories {
            guard let key = category.seedKey else { continue }
            guard let keeper = keepers[key] else {
                keepers[key] = category
                continue
            }
            for entry in category.entries ?? [] { entry.category = keeper }
            for plan in category.installmentPlans ?? [] { plan.category = keeper }
            for item in category.recurringItems ?? [] { item.category = keeper }
            for rule in category.merchantRules ?? [] { rule.category = keeper }
            if keeper.monthlyLimitMinor == nil { keeper.monthlyLimitMinor = category.monthlyLimitMinor }
            context.delete(category)
        }

        let accounts = try context.fetch(FetchDescriptor<Account>(sortBy: [SortDescriptor(\.createdAt)]))
        var accountKeepers: [String: Account] = [:]
        for account in accounts {
            guard let key = account.seedKey else { continue }
            guard let keeper = accountKeepers[key] else {
                accountKeepers[key] = account
                continue
            }
            for entry in account.entries ?? [] { entry.account = keeper }
            for entry in account.incomingTransfers ?? [] { entry.toAccount = keeper }
            for plan in account.installmentPlans ?? [] { plan.account = keeper }
            for item in account.recurringItems ?? [] { item.account = keeper }
            context.delete(account)
        }
        if context.hasChanges { try context.save() }
    }
}
