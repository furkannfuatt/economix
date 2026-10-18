import Foundation
import SwiftData
import EcoomixCore

// CloudKit kuralları: her alanın varsayılanı var ya da optional, unique yok, ilişkiler optional ve inverse'li.

nonisolated enum AccountType: String, CaseIterable, Identifiable {
    case cash, bank, debitCard, creditCard

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cash: "Nakit"
        case .bank: "Banka hesabı"
        case .debitCard: "Banka kartı"
        case .creditCard: "Kredi kartı"
        }
    }

    var defaultIcon: String {
        switch self {
        case .cash: "banknote.fill"
        case .bank: "building.columns.fill"
        case .debitCard: "creditcard.and.123"
        case .creditCard: "creditcard.fill"
        }
    }
}

nonisolated enum EntrySource: String {
    case manual, imported, recurring, installment
}

@Model
final class Account {
    var id: UUID = UUID()
    var name: String = ""
    var typeRaw: String = AccountType.bank.rawValue
    var icon: String = "building.columns.fill"
    var colorHex: String = "#0A84FF"
    var openingBalanceMinor: Int = 0
    var statementDay: Int = 15
    var dueOffsetDays: Int = 10
    var creditLimitMinor: Int?
    var isArchived: Bool = false
    var sortOrder: Int = 0
    var seedKey: String?
    var createdAt: Date = Date.now

    @Relationship(deleteRule: .nullify, inverse: \LedgerEntry.account)
    var entries: [LedgerEntry]? = []
    @Relationship(deleteRule: .nullify, inverse: \LedgerEntry.toAccount)
    var incomingTransfers: [LedgerEntry]? = []
    @Relationship(deleteRule: .nullify, inverse: \InstallmentPlan.account)
    var installmentPlans: [InstallmentPlan]? = []
    @Relationship(deleteRule: .nullify, inverse: \RecurringItem.account)
    var recurringItems: [RecurringItem]? = []

    init(name: String, type: AccountType) {
        self.name = name
        self.typeRaw = type.rawValue
        self.icon = type.defaultIcon
    }

    var type: AccountType {
        get { AccountType(rawValue: typeRaw) ?? .bank }
        set { typeRaw = newValue.rawValue }
    }

    var isCreditCard: Bool { type == .creditCard }
    var cycle: CardCycle { CardCycle(statementDay: statementDay, dueOffsetDays: dueOffsetDays) }
    var openingBalance: Money { Money(minor: openingBalanceMinor) }
    var creditLimit: Money? { creditLimitMinor.map(Money.init(minor:)) }
}

@Model
final class EntryCategory {
    var id: UUID = UUID()
    var name: String = ""
    var icon: String = "tag.fill"
    var colorHex: String = "#8E8E93"
    var kindRaw: String = TxKind.expense.rawValue
    /// Aylık bütçe limiti (kuruş). nil = limit yok.
    var monthlyLimitMinor: Int?
    var sortOrder: Int = 0
    var seedKey: String?
    var isArchived: Bool = false
    var createdAt: Date = Date.now

    @Relationship(deleteRule: .nullify, inverse: \LedgerEntry.category)
    var entries: [LedgerEntry]? = []
    @Relationship(deleteRule: .nullify, inverse: \InstallmentPlan.category)
    var installmentPlans: [InstallmentPlan]? = []
    @Relationship(deleteRule: .nullify, inverse: \RecurringItem.category)
    var recurringItems: [RecurringItem]? = []
    @Relationship(deleteRule: .cascade, inverse: \MerchantRule.category)
    var merchantRules: [MerchantRule]? = []

    init(name: String, icon: String, colorHex: String, kind: TxKind, sortOrder: Int = 0, seedKey: String? = nil) {
        self.name = name
        self.icon = icon
        self.colorHex = colorHex
        self.kindRaw = kind.rawValue
        self.sortOrder = sortOrder
        self.seedKey = seedKey
    }

    var kind: TxKind {
        get { TxKind(rawValue: kindRaw) ?? .expense }
        set { kindRaw = newValue.rawValue }
    }

    var monthlyLimit: Money? {
        get { monthlyLimitMinor.map(Money.init(minor:)) }
        set { monthlyLimitMinor = newValue?.minor }
    }
}

@Model
final class LedgerEntry {
    var id: UUID = UUID()
    /// Her zaman pozitif (kuruş); yönü `kind` belirler.
    var amountMinor: Int = 0
    var kindRaw: String = TxKind.expense.rawValue
    var date: Date = Date.now
    var merchant: String = ""
    var note: String = ""
    var sourceRaw: String = EntrySource.manual.rawValue
    var importHash: String?
    /// Taksit planındaki sırası (1'den başlar).
    var installmentIndex: Int?
    var createdAt: Date = Date.now

    var account: Account?
    var toAccount: Account?
    var category: EntryCategory?
    var installmentPlan: InstallmentPlan?
    var recurringItem: RecurringItem?

    init(amount: Money, kind: TxKind, date: Date, merchant: String = "", note: String = "",
         source: EntrySource = .manual) {
        self.amountMinor = amount.minor
        self.kindRaw = kind.rawValue
        self.date = date
        self.merchant = merchant
        self.note = note
        self.sourceRaw = source.rawValue
    }

    var amount: Money {
        get { Money(minor: amountMinor) }
        set { amountMinor = newValue.minor }
    }

    var kind: TxKind {
        get { TxKind(rawValue: kindRaw) ?? .expense }
        set { kindRaw = newValue.rawValue }
    }

    var source: EntrySource { EntrySource(rawValue: sourceRaw) ?? .manual }

    /// Listelerde görünen başlık: işyeri, yoksa kategori adı.
    var displayTitle: String {
        if let plan = installmentPlan, !plan.title.isEmpty { return plan.title }
        if !merchant.isEmpty { return merchant }
        if kind == .transfer { return "Transfer" }
        return category?.name ?? "Kategorisiz"
    }

    var installmentLabel: String? {
        guard let plan = installmentPlan, let index = installmentIndex else { return nil }
        if plan.closedEarlyAt != nil, index == plan.count { return "Erken kapama" }
        return "Taksit \(index)/\(plan.count)"
    }

    var snapshot: TxSnapshot {
        TxSnapshot(
            id: id.uuidString,
            amount: amount,
            kind: kind,
            date: date,
            categoryID: category?.id.uuidString,
            accountID: account?.id.uuidString,
            toAccountID: toAccount?.id.uuidString,
            merchant: merchant,
            installment: installmentPlan.map {
                InstallmentRef(planID: $0.id.uuidString, purchaseDate: $0.purchaseDate, planTotal: $0.total)
            },
            isSubscription: recurringItem?.isSubscription ?? false
        )
    }
}

@Model
final class InstallmentPlan {
    var id: UUID = UUID()
    var title: String = ""
    var merchant: String = ""
    var totalMinor: Int = 0
    var count: Int = 1
    var purchaseDate: Date = Date.now
    var closedEarlyAt: Date?
    var createdAt: Date = Date.now
    /// Ekstreden oluşturuldu; içe aktarım geri alınırsa silinir.
    var isImported: Bool = false

    var account: Account?
    var category: EntryCategory?
    @Relationship(deleteRule: .cascade, inverse: \LedgerEntry.installmentPlan)
    var entries: [LedgerEntry]? = []

    init(title: String, merchant: String, total: Money, count: Int, purchaseDate: Date) {
        self.title = title
        self.merchant = merchant
        self.totalMinor = total.minor
        self.count = count
        self.purchaseDate = purchaseDate
    }

    var total: Money { Money(minor: totalMinor) }

    var sortedEntries: [LedgerEntry] {
        (entries ?? []).sorted { ($0.installmentIndex ?? 0) < ($1.installmentIndex ?? 0) }
    }

    var lines: [InstallmentLine] {
        sortedEntries.map { InstallmentLine(index: $0.installmentIndex ?? 0, date: $0.date, amount: $0.amount) }
    }

    func progress(asOf date: Date = .now) -> InstallmentProgress {
        InstallmentScheduler.progress(of: lines, asOf: date)
    }

    var monthlyAmount: Money { total.split(into: max(count, 1)).last ?? .zero }
}

@Model
final class RecurringItem {
    var id: UUID = UUID()
    var title: String = ""
    var merchant: String = ""
    var amountMinor: Int = 0
    var kindRaw: String = TxKind.expense.rawValue
    var frequencyRaw: String = Frequency.monthly.rawValue
    var dayOfMonth: Int = 1
    var startDate: Date = Date.now
    var endDate: Date?
    var isSubscription: Bool = false
    var isActive: Bool = true
    /// Otomatik üretilen son vade.
    var lastGeneratedDate: Date?
    var createdAt: Date = Date.now

    var account: Account?
    var category: EntryCategory?
    @Relationship(deleteRule: .nullify, inverse: \LedgerEntry.recurringItem)
    var entries: [LedgerEntry]? = []

    init(title: String, amount: Money, kind: TxKind, frequency: Frequency, dayOfMonth: Int, startDate: Date,
         isSubscription: Bool) {
        self.title = title
        self.amountMinor = amount.minor
        self.kindRaw = kind.rawValue
        self.frequencyRaw = frequency.rawValue
        self.dayOfMonth = dayOfMonth
        self.startDate = startDate
        self.isSubscription = isSubscription
    }

    var amount: Money {
        get { Money(minor: amountMinor) }
        set { amountMinor = newValue.minor }
    }

    var kind: TxKind {
        get { TxKind(rawValue: kindRaw) ?? .expense }
        set { kindRaw = newValue.rawValue }
    }

    var frequency: Frequency {
        get { Frequency(rawValue: frequencyRaw) ?? .monthly }
        set { frequencyRaw = newValue.rawValue }
    }

    var rule: RecurrenceRule {
        RecurrenceRule(frequency: frequency, startDate: startDate, endDate: endDate, dayOfMonth: dayOfMonth)
    }

    func nextDate(after date: Date = .now) -> Date? {
        guard isActive else { return nil }
        return RecurrenceEngine.nextOccurrence(of: rule, after: date)
    }

    var monthlyEquivalent: Money { frequency.monthlyEquivalent(of: amount) }
    var yearlyEquivalent: Money { frequency.yearlyEquivalent(of: amount) }
}

@Model
final class MerchantRule {
    var id: UUID = UUID()
    /// `MerchantNormalizer.normalize` çıktısı.
    var pattern: String = ""
    var createdAt: Date = Date.now
    var category: EntryCategory?

    init(pattern: String, category: EntryCategory) {
        self.pattern = pattern
        self.category = category
    }
}

@Model
final class AIAnalysis {
    var id: UUID = UUID()
    var createdAt: Date = Date.now
    var periodStart: Date = Date.now
    var periodEnd: Date = Date.now
    var model: String = ""
    var resultJSON: String = ""

    init(periodStart: Date, periodEnd: Date, model: String, resultJSON: String) {
        self.periodStart = periodStart
        self.periodEnd = periodEnd
        self.model = model
        self.resultJSON = resultJSON
    }
}

enum EcoomixSchema {
    static let models: [any PersistentModel.Type] = [
        Account.self, EntryCategory.self, LedgerEntry.self, InstallmentPlan.self,
        RecurringItem.self, MerchantRule.self, AIAnalysis.self,
    ]
}
