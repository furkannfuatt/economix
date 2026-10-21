import Foundation
import SwiftData
import Testing
import EconomixCore
@testable import Economix

private func d(_ year: Int, _ month: Int, _ day: Int) -> Date {
    FinanceCalendar.calendar.date(from: DateComponents(year: year, month: month, day: day))!
}

private func tl(_ lira: Int) -> Money { Money(minor: lira * 100) }

@Suite("Yedekleme")
@MainActor
struct BackupServiceTests {
    /// Her model türünden ve her ilişkiden en az bir örnek.
    private func populate(_ f: Fixture) throws {
        let card = f.makeCard()
        card.creditLimitMinor = 50_000_00
        card.dueOffsetDays = 12
        let cash = Account(name: "Nakit", type: .cash)
        cash.seedKey = "nakit"
        cash.openingBalanceMinor = 1_250_00
        f.context.insert(cash)

        let market = f.makeCategory("Market")
        market.seedKey = "market"
        market.monthlyLimitMinor = 9_000_00
        let archived = f.makeCategory("Eski")
        archived.isArchived = true
        let salary = EntryCategory(name: "Maaş", icon: "banknote.fill", colorHex: "#34C759", kind: .income, sortOrder: 3)
        f.context.insert(salary)

        let ledger = f.service
        try ledger.addEntry(amount: tl(150), kind: .expense, date: d(2026, 10, 2), category: market, account: card,
                            merchant: "MIGROS", note: "haftalık", source: .imported, importHash: "abc")
        try ledger.addEntry(amount: tl(40_000), kind: .income, date: d(2026, 10, 1), category: salary, account: cash)
        try ledger.addEntry(amount: tl(5_000), kind: .transfer, date: d(2026, 10, 15), category: nil, account: cash,
                            toAccount: card)
        let plan = try ledger.addInstallmentPurchase(total: tl(12_000), count: 6, purchaseDate: d(2026, 9, 15),
                                                     category: archived, account: card, merchant: "TEKNOSA",
                                                     title: "Dizüstü")
        plan.isImported = true
        try ledger.closeEarly(plan, on: d(2026, 11, 20))

        let netflix = RecurringItem(title: "Netflix", amount: tl(230), kind: .expense, frequency: .monthly,
                                    dayOfMonth: 3, startDate: d(2026, 1, 3), isSubscription: true)
        netflix.account = card
        netflix.category = market
        netflix.lastGeneratedDate = d(2026, 10, 3)
        f.context.insert(netflix)
        let generated = try ledger.addEntry(amount: tl(230), kind: .expense, date: d(2026, 10, 3), category: market,
                                            account: card, merchant: "Netflix", source: .recurring)
        generated.recurringItem = netflix

        try ledger.learnCategory(merchant: "MIGROS KADIKOY", category: market)
        f.context.insert(AIAnalysis(periodStart: d(2026, 5, 1), periodEnd: d(2026, 10, 20), model: "gemini",
                                    resultJSON: "{\"summary\":\"ok\"}"))
        try f.context.save()
    }

    private func signature(_ context: ModelContext) throws -> [String] {
        func ids<T: PersistentModel>(_ type: T.Type, _ key: (T) -> String) throws -> [String] {
            try context.fetch(FetchDescriptor<T>()).map(key).sorted()
        }
        return try ids(Account.self) {
            "\($0.id) \($0.name) \($0.typeRaw) \($0.openingBalanceMinor) \($0.statementDay) \($0.dueOffsetDays) \(String(describing: $0.creditLimitMinor)) \($0.seedKey ?? "-") \($0.createdAt.timeIntervalSince1970)"
        } + ids(EntryCategory.self) {
            "\($0.id) \($0.name) \($0.kindRaw) \(String(describing: $0.monthlyLimitMinor)) \($0.isArchived) \($0.seedKey ?? "-") \($0.sortOrder)"
        } + ids(LedgerEntry.self) {
            "\($0.id) \($0.amountMinor) \($0.kindRaw) \($0.date.timeIntervalSince1970) \($0.merchant) \($0.note) \($0.sourceRaw) \($0.importHash ?? "-") \(String(describing: $0.installmentIndex)) a:\($0.account?.id.uuidString ?? "-") t:\($0.toAccount?.id.uuidString ?? "-") c:\($0.category?.id.uuidString ?? "-") p:\($0.installmentPlan?.id.uuidString ?? "-") r:\($0.recurringItem?.id.uuidString ?? "-")"
        } + ids(InstallmentPlan.self) {
            "\($0.id) \($0.title) \($0.totalMinor) \($0.count) \($0.purchaseDate.timeIntervalSince1970) \(String(describing: $0.closedEarlyAt?.timeIntervalSince1970)) \($0.isImported) a:\($0.account?.id.uuidString ?? "-") c:\($0.category?.id.uuidString ?? "-")"
        } + ids(RecurringItem.self) {
            "\($0.id) \($0.title) \($0.amountMinor) \($0.frequencyRaw) \($0.dayOfMonth) \($0.isSubscription) \($0.isActive) \(String(describing: $0.lastGeneratedDate?.timeIntervalSince1970)) a:\($0.account?.id.uuidString ?? "-") c:\($0.category?.id.uuidString ?? "-")"
        } + ids(MerchantRule.self) {
            "\($0.id) \($0.pattern) c:\($0.category?.id.uuidString ?? "-")"
        } + ids(AIAnalysis.self) {
            "\($0.id) \($0.model) \($0.resultJSON) \($0.periodStart.timeIntervalSince1970)"
        }
    }

    @Test("Yedek boş bir depoya her şeyi ilişkileriyle aynen geri yükler")
    func roundTrip() throws {
        let source = Fixture()
        try populate(source)
        let data = try BackupService.export(from: source.context, settings: [:])

        let target = Fixture()
        let summary = try BackupService.restore(data, into: target.context)
        #expect(try signature(target.context) == signature(source.context))
        #expect(summary.entries == (try source.context.fetchCount(FetchDescriptor<LedgerEntry>())))
        #expect(summary.accounts == 2)
    }

    @Test("Geri yükleme mevcut verilerin yerine geçer")
    func replacesExisting() throws {
        let source = Fixture()
        try populate(source)
        let data = try BackupService.export(from: source.context, settings: [:])

        let target = Fixture()
        try target.service.addEntry(amount: tl(1), kind: .expense, date: .now, category: target.makeCategory("Silinecek"),
                                    account: target.makeCard(), merchant: "ESKI")
        try BackupService.restore(data, into: target.context)
        #expect(try signature(target.context) == signature(source.context))
        #expect(try target.context.fetch(FetchDescriptor<LedgerEntry>()).allSatisfy { $0.merchant != "ESKI" })
    }

    @Test("Seçili ayarlar yedeğe girer ve geri yüklenir; kilit ve Gemini izni girmez")
    func settings() throws {
        let suite = "BackupServiceTests.\(UUID().uuidString)"
        let source = try #require(UserDefaults(suiteName: suite))
        defer { source.removePersistentDomain(forName: suite) }
        source.set(23, forKey: MonthSettings.key)
        source.set(false, forKey: NotificationPreferences.budgetKey)
        source.set("purchase", forKey: "reportMode")
        source.set(true, forKey: AppLock.enabledKey)
        source.set(true, forKey: AIConsent.key)
        source.set(true, forKey: "aiIncludeMerchants")

        let settings = BackupService.settings(from: source)
        #expect(settings[MonthSettings.key] == .int(23))
        #expect(settings[NotificationPreferences.budgetKey] == .bool(false))
        #expect(settings["reportMode"] == .string("purchase"))
        #expect(settings[AppLock.enabledKey] == nil)
        #expect(settings[AIConsent.key] == nil)
        #expect(settings["aiIncludeMerchants"] == nil, "Google'a daha fazla veri gönderen tercih yedekten açılmaz")

        let targetSuite = "BackupServiceTests.\(UUID().uuidString)"
        let target = try #require(UserDefaults(suiteName: targetSuite))
        defer { target.removePersistentDomain(forName: targetSuite) }
        // Depo değişkende tutulur; `Fixture().context` deposu hemen bırakılmış bir bağlam verir.
        let empty = Fixture(), restored = Fixture()
        let data = try BackupService.export(from: empty.context, settings: settings)
        try BackupService.restore(data, into: restored.context, defaults: target)
        #expect(target.integer(forKey: MonthSettings.key) == 23)
        #expect(target.object(forKey: NotificationPreferences.budgetKey) as? Bool == false)
        #expect(target.string(forKey: "reportMode") == "purchase")
        #expect(target.object(forKey: AppLock.enabledKey) == nil)
    }

    /// Geçerli bir yedeğin JSON'unda tek bir değeri değiştirir.
    private func tampered(_ data: Data, _ change: (inout [String: Any]) -> Void) throws -> Data {
        var json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        change(&json)
        return try JSONSerialization.data(withJSONObject: json)
    }

    private func modifyFirst(_ key: String, in json: inout [String: Any], _ change: (inout [String: Any]) -> Void) {
        var records = json[key] as? [[String: Any]] ?? []
        guard !records.isEmpty else { return }
        change(&records[0])
        json[key] = records
    }

    @Test("Uç değerli yedek reddedilir: binlerce işlem üretecek tarih, sıfır taksit, dev tutar; mevcut veri korunur")
    func rejectsExtremeValues() throws {
        let source = Fixture()
        try populate(source)
        let data = try BackupService.export(from: source.context, settings: [:])
        // JSONEncoder'ın varsayılan tarih biçimi: 2001-01-01'den bu yana saniye. 0001 yılı ≈ -63,1 milyar.
        let ancientRecurring = try tampered(data) { json in
            modifyFirst("recurringItems", in: &json) {
                $0["startDate"] = -63_113_904_000.0
                $0["lastGeneratedDate"] = nil
                $0["frequencyRaw"] = "weekly"
            }
        }
        let zeroInstallments = try tampered(data) { json in modifyFirst("plans", in: &json) { $0["count"] = 0 } }
        let hugeAmount = try tampered(data) { json in
            modifyFirst("entries", in: &json) { $0["amountMinor"] = 1_000_000_000_000_000 }
        }

        let target = Fixture()
        try target.service.addEntry(amount: tl(1), kind: .expense, date: .now, category: nil, account: nil,
                                    merchant: "KALSIN")
        for file in [ancientRecurring, zeroInstallments, hugeAmount] {
            #expect(throws: BackupService.BackupError.invalidValues) {
                try BackupService.restore(file, into: target.context)
            }
        }
        #expect(try target.context.fetch(FetchDescriptor<LedgerEntry>()).map(\.merchant) == ["KALSIN"])
        #expect(try target.context.fetchCount(FetchDescriptor<RecurringItem>()) == 0)
    }

    @Test("Yedek olmayan ya da daha yeni sürümlü dosya reddedilir; mevcut veriye dokunulmaz")
    func rejectsInvalid() throws {
        let target = Fixture()
        try target.service.addEntry(amount: tl(1), kind: .expense, date: .now, category: nil, account: nil,
                                    merchant: "KALSIN")
        #expect(throws: BackupService.BackupError.notABackup) {
            try BackupService.restore(Data("{\"merhaba\":1}".utf8), into: target.context)
        }
        #expect(throws: BackupService.BackupError.notABackup) {
            try BackupService.restore(Data("bozuk".utf8), into: target.context)
        }
        let future = Data("{\"format\":\"economix-backup\",\"version\":999}".utf8)
        #expect(throws: BackupService.BackupError.newerVersion) {
            try BackupService.restore(future, into: target.context)
        }
        #expect(try target.context.fetch(FetchDescriptor<LedgerEntry>()).map(\.merchant) == ["KALSIN"])
    }
}
