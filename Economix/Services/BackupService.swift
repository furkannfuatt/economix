import Foundation
import SwiftData
import EconomixCore

/// Tüm verilerin tek JSON dosyası olarak yedeği ve geri yüklenmesi. Geliştirme sürümünden (iCloud Development)
/// mağaza sürümüne (Production) geçerken ya da iCloud dışında bir kopya istendiğinde kullanılır.
/// Gemini anahtarı, Gemini izni ve Face ID kilidi yedeğe girmez; yeni kurulumda yeniden verilir.
enum BackupService {
    static let format = "economix-backup"
    static let version = 1
    /// Yıllarca kayıt bile birkaç MB tutar; sınır bozuk bir dosyanın belleği doldurmasını önler.
    static let maxFileBytes = 20 * 1024 * 1024

    enum BackupError: LocalizedError, Equatable {
        case notABackup, newerVersion, tooLarge, invalidValues

        var errorDescription: String? {
            switch self {
            case .notABackup: "Bu dosya bir Economix yedeği değil ya da bozuk."
            case .newerVersion: "Bu yedek uygulamanın daha yeni bir sürümüyle alınmış. Önce uygulamayı güncelle."
            case .tooLarge: "Dosya bir yedek için fazla büyük."
            case .invalidValues: "Yedekte geçersiz değerler var; dosya bozuk olabilir."
            }
        }
    }

    nonisolated enum SettingValue: Codable, Equatable {
        case bool(Bool), int(Int), string(String)
    }

    struct Summary: Equatable {
        var accounts = 0, categories = 0, entries = 0, plans = 0, recurringItems = 0
    }

    /// Yedeğe giren ayarlar. Kilit, Gemini izni ve anahtarı, Google'a daha fazla veri gönderen "işyeri adlarını
    /// gönder" tercihi bilerek dışarıda: yeni kurulumda açıkça yeniden verilir.
    static let settingKeys = [
        MonthSettings.key, NotificationPreferences.budgetKey, NotificationPreferences.cardKey,
        NotificationPreferences.subscriptionKey, NotificationPreferences.monthlyKey, "reportMode", "reportRange",
        GeminiModel.storageKey, "lastAccountID", "paymentsSection",
    ]

    static func settings(from defaults: UserDefaults = .standard) -> [String: SettingValue] {
        var result: [String: SettingValue] = [:]
        for key in settingKeys {
            switch defaults.object(forKey: key) {
            case let number as NSNumber where CFGetTypeID(number) == CFBooleanGetTypeID():
                result[key] = .bool(number.boolValue)
            case let number as NSNumber:
                result[key] = .int(number.intValue)
            case let text as String:
                result[key] = .string(text)
            default:
                break
            }
        }
        return result
    }

    // MARK: Dışa aktarma

    static func export(from context: ModelContext, settings: [String: SettingValue] = settings()) throws -> Data {
        let payload = Payload(
            format: format, version: version, createdAt: .now, settings: settings,
            accounts: try context.fetch(FetchDescriptor<Account>()).map(AccountRecord.init),
            categories: try context.fetch(FetchDescriptor<EntryCategory>()).map(CategoryRecord.init),
            plans: try context.fetch(FetchDescriptor<InstallmentPlan>()).map(PlanRecord.init),
            recurringItems: try context.fetch(FetchDescriptor<RecurringItem>()).map(RecurringRecord.init),
            entries: try context.fetch(FetchDescriptor<LedgerEntry>()).map(EntryRecord.init),
            merchantRules: try context.fetch(FetchDescriptor<MerchantRule>()).map(RuleRecord.init),
            analyses: try context.fetch(FetchDescriptor<AIAnalysis>()).map(AnalysisRecord.init)
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(payload)
    }

    private static let filePrefix = "economix-yedek-"

    /// Paylaşım için geçici dosya: "economix-yedek-2026-10-21.json". Cihaz kilitliyken okunamaz;
    /// öncekiler silinir.
    static func writeTemporaryFile(from context: ModelContext) throws -> URL {
        removeTemporaryFiles()
        let c = FinanceCalendar.calendar.dateComponents([.year, .month, .day], from: .now)
        let name = String(format: "\(filePrefix)%04d-%02d-%02d.json", c.year!, c.month!, c.day!)
        let url = URL.temporaryDirectory.appending(path: name)
        try export(from: context).write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }

    static func removeTemporaryFiles() {
        let directory = URL.temporaryDirectory
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        for name in names where name.hasPrefix(filePrefix) && name.hasSuffix(".json") {
            try? FileManager.default.removeItem(at: directory.appending(path: name))
        }
    }

    // MARK: Geri yükleme

    /// Dosya önce bütünüyle çözülür; ancak geçerliyse mevcut tüm veriler silinip yedektekiler eklenir.
    /// Bir hata olursa bağlam geri alınır, mevcut veri korunur.
    @discardableResult
    static func restore(_ data: Data, into context: ModelContext, defaults: UserDefaults = .standard) throws -> Summary {
        guard data.count <= maxFileBytes else { throw BackupError.tooLarge }
        let decoder = JSONDecoder()
        guard let header = try? decoder.decode(Header.self, from: data), header.format == format,
              let fileVersion = header.version else { throw BackupError.notABackup }
        guard fileVersion <= version else { throw BackupError.newerVersion }
        guard let payload = try? decoder.decode(Payload.self, from: data) else { throw BackupError.notABackup }
        try validate(payload)

        do {
            try deleteAll(in: context)
            let summary = insert(payload, into: context)
            try context.save()
            for (key, value) in payload.settings where settingKeys.contains(key) {
                switch value {
                case .bool(let bool): defaults.set(bool, forKey: key)
                case .int(let int): defaults.set(int, forKey: key)
                case .string(let text): defaults.set(text, forKey: key)
                }
            }
            return summary
        } catch {
            context.rollback()
            throw error
        }
    }

    // MARK: Doğrulama

    private static let earliest = FinanceCalendar.calendar.date(from: DateComponents(year: 1970, month: 1, day: 1))!
    private static let latest = FinanceCalendar.calendar.date(from: DateComponents(year: 2200, month: 1, day: 1))!

    /// Dosya geçerli JSON olsa da değerler makul aralıkta olmalı. Örneğin 0001 yılında başlayan haftalık bir düzenli
    /// ödeme, geri yüklemenin hemen ardından yüz binlerce işlem üretirdi. Geçersizse hiçbir şeye dokunulmaz.
    private static func validate(_ p: Payload) throws {
        let limit = Money.maxMagnitude.minor
        func date(_ value: Date?) -> Bool { value.map { $0 >= earliest && $0 <= latest } ?? true }
        func amount(_ value: Int?) -> Bool { value.map { (0...limit).contains($0) } ?? true }
        func text(_ value: String?, _ max: Int = 2_000) -> Bool { (value?.count ?? 0) <= max }

        let recordCount = p.accounts.count + p.categories.count + p.plans.count + p.recurringItems.count
            + p.entries.count + p.merchantRules.count + p.analyses.count
        let valid = recordCount <= 200_000
            && p.accounts.allSatisfy {
                text($0.name) && text($0.typeRaw) && text($0.icon) && text($0.colorHex) && text($0.seedKey)
                    && (-limit...limit).contains($0.openingBalanceMinor) && amount($0.creditLimitMinor)
                    && (1...31).contains($0.statementDay) && (0...60).contains($0.dueOffsetDays) && date($0.createdAt)
            }
            && p.categories.allSatisfy {
                text($0.name) && text($0.icon) && text($0.colorHex) && text($0.kindRaw) && text($0.seedKey)
                    && amount($0.monthlyLimitMinor) && date($0.createdAt)
            }
            && p.plans.allSatisfy {
                text($0.title) && text($0.merchant) && amount($0.totalMinor) && (1...120).contains($0.count)
                    && date($0.purchaseDate) && date($0.closedEarlyAt) && date($0.createdAt)
            }
            && p.recurringItems.allSatisfy {
                text($0.title) && text($0.merchant) && text($0.kindRaw) && text($0.frequencyRaw)
                    && amount($0.amountMinor) && (1...31).contains($0.dayOfMonth) && date($0.startDate)
                    && date($0.endDate) && date($0.lastGeneratedDate) && date($0.createdAt)
            }
            && p.entries.allSatisfy {
                text($0.merchant) && text($0.note, 10_000) && text($0.kindRaw) && text($0.sourceRaw)
                    && text($0.importHash) && amount($0.amountMinor) && date($0.date) && date($0.createdAt)
                    && ($0.installmentIndex.map { (1...120).contains($0) } ?? true)
            }
            && p.merchantRules.allSatisfy { text($0.pattern) && date($0.createdAt) }
            && p.analyses.allSatisfy {
                text($0.model) && $0.resultJSON.utf8.count <= 200_000 && date($0.createdAt)
                    && date($0.periodStart) && date($0.periodEnd)
            }
        guard valid else { throw BackupError.invalidValues }
    }

    /// Nesneler tek tek silinir: toplu silme iCloud'a yansımayabilir.
    private static func deleteAll(in context: ModelContext) throws {
        try context.fetch(FetchDescriptor<LedgerEntry>()).forEach(context.delete)
        try context.fetch(FetchDescriptor<InstallmentPlan>()).forEach(context.delete)
        try context.fetch(FetchDescriptor<RecurringItem>()).forEach(context.delete)
        try context.fetch(FetchDescriptor<MerchantRule>()).forEach(context.delete)
        try context.fetch(FetchDescriptor<EntryCategory>()).forEach(context.delete)
        try context.fetch(FetchDescriptor<Account>()).forEach(context.delete)
        try context.fetch(FetchDescriptor<AIAnalysis>()).forEach(context.delete)
    }

    private static func insert(_ payload: Payload, into context: ModelContext) -> Summary {
        var accounts: [UUID: Account] = [:]
        for record in payload.accounts {
            let account = Account(name: record.name, type: .bank)
            account.id = record.id
            account.typeRaw = record.typeRaw
            account.icon = record.icon
            account.colorHex = record.colorHex
            account.openingBalanceMinor = record.openingBalanceMinor
            account.statementDay = record.statementDay
            account.dueOffsetDays = record.dueOffsetDays
            account.creditLimitMinor = record.creditLimitMinor
            account.isArchived = record.isArchived
            account.sortOrder = record.sortOrder
            account.seedKey = record.seedKey
            account.createdAt = record.createdAt
            context.insert(account)
            accounts[record.id] = account
        }

        var categories: [UUID: EntryCategory] = [:]
        for record in payload.categories {
            let category = EntryCategory(name: record.name, icon: record.icon, colorHex: record.colorHex, kind: .expense,
                                         sortOrder: record.sortOrder, seedKey: record.seedKey)
            category.id = record.id
            category.kindRaw = record.kindRaw
            category.monthlyLimitMinor = record.monthlyLimitMinor
            category.isArchived = record.isArchived
            category.createdAt = record.createdAt
            context.insert(category)
            categories[record.id] = category
        }

        var plans: [UUID: InstallmentPlan] = [:]
        for record in payload.plans {
            let plan = InstallmentPlan(title: record.title, merchant: record.merchant, total: Money(minor: record.totalMinor),
                                       count: record.count, purchaseDate: record.purchaseDate)
            plan.id = record.id
            plan.closedEarlyAt = record.closedEarlyAt
            plan.isImported = record.isImported
            plan.createdAt = record.createdAt
            context.insert(plan)
            plan.account = record.accountID.flatMap { accounts[$0] }
            plan.category = record.categoryID.flatMap { categories[$0] }
            plans[record.id] = plan
        }

        var recurringItems: [UUID: RecurringItem] = [:]
        for record in payload.recurringItems {
            let item = RecurringItem(title: record.title, amount: Money(minor: record.amountMinor), kind: .expense,
                                     frequency: .monthly, dayOfMonth: record.dayOfMonth, startDate: record.startDate,
                                     isSubscription: record.isSubscription)
            item.id = record.id
            item.merchant = record.merchant
            item.kindRaw = record.kindRaw
            item.frequencyRaw = record.frequencyRaw
            item.endDate = record.endDate
            item.isActive = record.isActive
            item.lastGeneratedDate = record.lastGeneratedDate
            item.createdAt = record.createdAt
            context.insert(item)
            item.account = record.accountID.flatMap { accounts[$0] }
            item.category = record.categoryID.flatMap { categories[$0] }
            recurringItems[record.id] = item
        }

        for record in payload.entries {
            let entry = LedgerEntry(amount: Money(minor: record.amountMinor), kind: .expense, date: record.date,
                                    merchant: record.merchant, note: record.note)
            entry.id = record.id
            entry.kindRaw = record.kindRaw
            entry.sourceRaw = record.sourceRaw
            entry.importHash = record.importHash
            entry.installmentIndex = record.installmentIndex
            entry.createdAt = record.createdAt
            context.insert(entry)
            entry.account = record.accountID.flatMap { accounts[$0] }
            entry.toAccount = record.toAccountID.flatMap { accounts[$0] }
            entry.category = record.categoryID.flatMap { categories[$0] }
            entry.installmentPlan = record.installmentPlanID.flatMap { plans[$0] }
            entry.recurringItem = record.recurringItemID.flatMap { recurringItems[$0] }
        }

        for record in payload.merchantRules {
            guard let category = record.categoryID.flatMap({ categories[$0] }) else { continue }
            let rule = MerchantRule(pattern: record.pattern, category: category)
            rule.id = record.id
            rule.createdAt = record.createdAt
            context.insert(rule)
        }

        for record in payload.analyses {
            let analysis = AIAnalysis(periodStart: record.periodStart, periodEnd: record.periodEnd, model: record.model,
                                      resultJSON: record.resultJSON)
            analysis.id = record.id
            analysis.createdAt = record.createdAt
            context.insert(analysis)
        }

        return Summary(accounts: payload.accounts.count, categories: payload.categories.count,
                       entries: payload.entries.count, plans: payload.plans.count,
                       recurringItems: payload.recurringItems.count)
    }
}

// MARK: Dosya biçimi (sürüm 1)

private nonisolated struct Header: Decodable {
    var format: String?
    var version: Int?
}

private nonisolated struct Payload: Codable {
    var format: String
    var version: Int
    var createdAt: Date
    var settings: [String: BackupService.SettingValue]
    var accounts: [AccountRecord]
    var categories: [CategoryRecord]
    var plans: [PlanRecord]
    var recurringItems: [RecurringRecord]
    var entries: [EntryRecord]
    var merchantRules: [RuleRecord]
    var analyses: [AnalysisRecord]
}

private nonisolated struct AccountRecord: Codable {
    var id: UUID, name: String, typeRaw: String, icon: String, colorHex: String
    var openingBalanceMinor: Int, statementDay: Int, dueOffsetDays: Int, creditLimitMinor: Int?
    var isArchived: Bool, sortOrder: Int, seedKey: String?, createdAt: Date
}

private nonisolated struct CategoryRecord: Codable {
    var id: UUID, name: String, icon: String, colorHex: String, kindRaw: String, monthlyLimitMinor: Int?
    var sortOrder: Int, seedKey: String?, isArchived: Bool, createdAt: Date
}

private nonisolated struct PlanRecord: Codable {
    var id: UUID, title: String, merchant: String, totalMinor: Int, count: Int, purchaseDate: Date
    var closedEarlyAt: Date?, createdAt: Date, isImported: Bool, accountID: UUID?, categoryID: UUID?
}

private nonisolated struct RecurringRecord: Codable {
    var id: UUID, title: String, merchant: String, amountMinor: Int, kindRaw: String, frequencyRaw: String
    var dayOfMonth: Int, startDate: Date, endDate: Date?, isSubscription: Bool, isActive: Bool
    var lastGeneratedDate: Date?, createdAt: Date, accountID: UUID?, categoryID: UUID?
}

private nonisolated struct EntryRecord: Codable {
    var id: UUID, amountMinor: Int, kindRaw: String, date: Date, merchant: String, note: String, sourceRaw: String
    var importHash: String?, installmentIndex: Int?, createdAt: Date
    var accountID: UUID?, toAccountID: UUID?, categoryID: UUID?, installmentPlanID: UUID?, recurringItemID: UUID?
}

private nonisolated struct RuleRecord: Codable {
    var id: UUID, pattern: String, createdAt: Date, categoryID: UUID?
}

private nonisolated struct AnalysisRecord: Codable {
    var id: UUID, createdAt: Date, periodStart: Date, periodEnd: Date, model: String, resultJSON: String
}

private extension AccountRecord {
    init(_ a: Account) {
        self.init(id: a.id, name: a.name, typeRaw: a.typeRaw, icon: a.icon, colorHex: a.colorHex,
                  openingBalanceMinor: a.openingBalanceMinor, statementDay: a.statementDay, dueOffsetDays: a.dueOffsetDays,
                  creditLimitMinor: a.creditLimitMinor, isArchived: a.isArchived, sortOrder: a.sortOrder,
                  seedKey: a.seedKey, createdAt: a.createdAt)
    }
}

private extension CategoryRecord {
    init(_ c: EntryCategory) {
        self.init(id: c.id, name: c.name, icon: c.icon, colorHex: c.colorHex, kindRaw: c.kindRaw,
                  monthlyLimitMinor: c.monthlyLimitMinor, sortOrder: c.sortOrder, seedKey: c.seedKey,
                  isArchived: c.isArchived, createdAt: c.createdAt)
    }
}

private extension PlanRecord {
    init(_ p: InstallmentPlan) {
        self.init(id: p.id, title: p.title, merchant: p.merchant, totalMinor: p.totalMinor, count: p.count,
                  purchaseDate: p.purchaseDate, closedEarlyAt: p.closedEarlyAt, createdAt: p.createdAt,
                  isImported: p.isImported, accountID: p.account?.id, categoryID: p.category?.id)
    }
}

private extension RecurringRecord {
    init(_ r: RecurringItem) {
        self.init(id: r.id, title: r.title, merchant: r.merchant, amountMinor: r.amountMinor, kindRaw: r.kindRaw,
                  frequencyRaw: r.frequencyRaw, dayOfMonth: r.dayOfMonth, startDate: r.startDate, endDate: r.endDate,
                  isSubscription: r.isSubscription, isActive: r.isActive, lastGeneratedDate: r.lastGeneratedDate,
                  createdAt: r.createdAt, accountID: r.account?.id, categoryID: r.category?.id)
    }
}

private extension EntryRecord {
    init(_ e: LedgerEntry) {
        self.init(id: e.id, amountMinor: e.amountMinor, kindRaw: e.kindRaw, date: e.date, merchant: e.merchant,
                  note: e.note, sourceRaw: e.sourceRaw, importHash: e.importHash, installmentIndex: e.installmentIndex,
                  createdAt: e.createdAt, accountID: e.account?.id, toAccountID: e.toAccount?.id,
                  categoryID: e.category?.id, installmentPlanID: e.installmentPlan?.id,
                  recurringItemID: e.recurringItem?.id)
    }
}

private extension RuleRecord {
    init(_ r: MerchantRule) {
        self.init(id: r.id, pattern: r.pattern, createdAt: r.createdAt, categoryID: r.category?.id)
    }
}

private extension AnalysisRecord {
    init(_ a: AIAnalysis) {
        self.init(id: a.id, createdAt: a.createdAt, periodStart: a.periodStart, periodEnd: a.periodEnd,
                  model: a.model, resultJSON: a.resultJSON)
    }
}
