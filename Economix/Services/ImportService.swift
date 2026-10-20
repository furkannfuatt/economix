import Foundation
import SwiftData
import EconomixCore

/// Önizleme ekranındaki bir ekstre satırı.
struct ImportCandidate: Identifiable {
    enum Status {
        /// Yeni işlem.
        case new
        /// Aynı satır daha önce içe aktarılmış.
        case duplicate
        /// Elle girilmiş aynı tutarlı işlem var (±2 gün).
        case possibleDuplicate
        /// Elle girilmiş yakın tutarlı işlem var (±2 gün, fark ±5 ₺ ya da ±%2).
        case similarAmount
        /// Taksit, mevcut bir plana ait.
        case installmentKnown
        /// Taksit; yeni plan oluşturulacak.
        case newInstallmentPlan
        /// Karta yapılan ödeme.
        case payment
        /// Kampanya ödülü, bonus, puan ya da chip-para kullanımı.
        case reward
    }

    let row: StatementRow
    var status: Status
    var include: Bool
    var category: EntryCategory?
    /// Satırın eşleştiği elle girilmiş (ya da plandaki) işlem.
    var matchedEntry: LedgerEntry?
    /// Yakın tutar eşleşmesinde ekstre ile kayıt arasındaki fark.
    var amountDifference: Money?
    /// Kategoriyi kullanıcı ya da Gemini seçti: içe aktarınca bu işyeri için öğrenilir.
    /// Sözlükten gelen öneriler öğrenilmez; sözlük düzeldiğinde eski hatalı öneri kural olarak kalmasın.
    var learnsCategory = false

    var id: Int { row.lineNumber }

    /// Seçilen kategoriyi satıra ve aynı markanın kategorisiz gider satırlarına uygular; kaç satırın daha güncellendiğini döner.
    @discardableResult
    static func applyCategory(_ category: EntryCategory?, at index: Int, in candidates: inout [ImportCandidate]) -> Int {
        candidates[index].category = category
        candidates[index].learnsCategory = category != nil
        let brand = MerchantNormalizer.brandKey(candidates[index].row.description)
        guard category != nil, !brand.isEmpty else { return 0 }
        var updated = 0
        for other in candidates.indices where other != index && candidates[other].category == nil
            && candidates[other].row.kind == .expense
            && MerchantNormalizer.brandKey(candidates[other].row.description) == brand {
            candidates[other].category = category
            candidates[other].learnsCategory = true
            updated += 1
        }
        return updated
    }
}

struct ImportSummary {
    var added = 0
    var plansCreated = 0
    var skipped = 0
    /// Elle girilmiş kayıtla eşleştirilip işaretlenen satırlar.
    var linked = 0
    /// Tutarı ekstredeki kuruşlu tutara düzeltilen elle kayıtlar.
    var amountsCorrected = 0
}

/// Bir hesaba daha önce içe aktarılmış kayıtlar.
struct ImportedRecords {
    /// Ekstreden eklenen işlemler (harcama, iade, ödeme…).
    var entries = 0
    /// Ekstreden oluşturulan taksit planları.
    var plans = 0
    /// Ekstreyle eşleştirilmiş elle girilen kayıtlar (silinmez, yalnızca eşleşme kaldırılır).
    var linked = 0
    /// Bu kayıtların işyerleri için öğrenilmiş kategoriler.
    var rules = 0

    var isEmpty: Bool { entries == 0 && plans == 0 && linked == 0 }
}

struct ImportService {
    let context: ModelContext
    var calendar: Calendar = FinanceCalendar.calendar

    /// Elle girilen tutar ile ekstre tutarı arasında kabul edilen fark: en az 5 ₺, en az %2.
    static func tolerance(for amount: Money) -> Money {
        max(Money(minor: 500), amount.scaled(numerator: 2, denominator: 100))
    }

    /// Banka hesabı/kartı dökümlerinde para çıkışları eksi gelir; kart ekstresinde otomatik tahmin edilir.
    static func expenseSign(for account: Account) -> ExpenseSign {
        account.isCreditCard ? .auto : .negative
    }

    private var ledger: LedgerService { LedgerService(context: context) }

    func prepare(_ result: StatementParseResult, account: Account) throws -> [ImportCandidate] {
        let entries = try context.fetch(FetchDescriptor<LedgerEntry>())
        let knownHashes = Set(entries.compactMap(\.importHash))
        let pool = entries.filter { $0.importHash == nil && belongsToPool($0.account, target: account) }
        let categories = try context.fetch(FetchDescriptor<EntryCategory>())

        var candidates = result.rows.map { row in
            ImportCandidate(row: row, status: .new, include: true, category: nil)
        }

        // 1) Kesin durumlar: daha önce aktarılmış, karta ödeme, taksit.
        var usedPlanEntries = Set<ObjectIdentifier>()
        for index in candidates.indices {
            let row = candidates[index].row
            if knownHashes.contains(row.importHash) {
                candidates[index].status = .duplicate
                candidates[index].include = false
            } else if row.kind == .payment {
                candidates[index].status = .payment
                candidates[index].include = false
            } else if row.kind == .reward {
                candidates[index].status = .reward
                candidates[index].include = false
            } else if let marker = row.installment, row.kind == .expense {
                if let entry = planEntry(for: row, marker: marker, account: account, excluding: usedPlanEntries) {
                    usedPlanEntries.insert(ObjectIdentifier(entry))
                    candidates[index].status = .installmentKnown
                    candidates[index].matchedEntry = entry
                    candidates[index].include = false
                } else {
                    candidates[index].status = .newInstallmentPlan
                }
            }
        }

        // 2) Elle girilenlerle bire bir eşleştirme: önce tam tutar, sonra en küçük fark ve tarih farkı.
        let open = candidates.indices.filter { candidates[$0].status == .new }
        assignManualMatches(rows: open.map { candidates[$0].row }, pool: pool).forEach { offset, match in
            let index = open[offset]
            candidates[index].matchedEntry = match.entry
            if match.difference.isZero {
                candidates[index].status = .possibleDuplicate
                candidates[index].include = false
            } else {
                candidates[index].status = .similarAmount
                candidates[index].amountDifference = match.difference
                // İşyeri de tutuyorsa aynı alışveriş sayılır; tutmuyorsa karar kullanıcıya bırakılır.
                candidates[index].include = !match.merchantMatches
            }
        }

        // 3) Kategori önerisi.
        for index in candidates.indices where candidates[index].row.kind == .expense {
            let description = candidates[index].row.description
            candidates[index].category = ledger.learnedCategory(for: description)
                ?? MerchantCategorizer.suggestedSeedKey(for: description).flatMap { key in
                    // Aracı kurum/kripto alımları yatırım kategorisine düşer.
                    categories.first { $0.seedKey == key && ($0.kind == .expense || $0.kind == .investment) }
                }
        }
        return candidates
    }

    @discardableResult
    func commit(_ candidates: [ImportCandidate], account: Account) throws -> ImportSummary {
        var summary = ImportSummary()
        for candidate in candidates {
            let row = candidate.row
            guard candidate.include else {
                if let entry = candidate.matchedEntry, link(entry, to: candidate) {
                    summary.linked += 1
                    if candidate.status == .similarAmount, entry.amount != row.amount {
                        entry.amount = row.amount
                        summary.amountsCorrected += 1
                    }
                } else {
                    summary.skipped += 1
                }
                continue
            }
            switch (candidate.status, row.kind) {
            case (.newInstallmentPlan, _):
                guard let marker = row.installment else { continue }
                let purchase = calendar.date(byAdding: .month, value: -(marker.current - 1), to: row.date)!
                let plan = try ledger.addInstallmentPurchase(total: row.amount * marker.total, count: marker.total,
                                                             purchaseDate: purchase, category: candidate.category,
                                                             account: account, merchant: row.description)
                plan.isImported = true
                plan.sortedEntries.first { $0.installmentIndex == marker.current }?.importHash = row.importHash
                summary.plansCreated += 1
            case (_, .payment):
                try ledger.addEntry(amount: row.amount, kind: .transfer, date: row.date, category: nil, account: nil,
                                    toAccount: account, merchant: row.description, source: .imported,
                                    importHash: row.importHash)
            case (_, .refund):
                try ledger.addEntry(amount: row.amount, kind: .income, date: row.date, category: candidate.category,
                                    account: account, merchant: row.description, note: "İade", source: .imported,
                                    importHash: row.importHash)
            case (_, .reward):
                try ledger.addEntry(amount: row.amount, kind: .income, date: row.date, category: nil,
                                    account: account, merchant: row.description, note: "Ödül / bonus", source: .imported,
                                    importHash: row.importHash)
            case (_, .income):
                try ledger.addEntry(amount: row.amount, kind: .income, date: row.date, category: candidate.category,
                                    account: account, merchant: row.description, source: .imported,
                                    importHash: row.importHash)
            case (_, .expense):
                let kind: TxKind = candidate.category?.kind == .investment ? .investment : .expense
                try ledger.addEntry(amount: row.amount, kind: kind, date: row.date, category: candidate.category,
                                    account: account, merchant: row.description, source: .imported,
                                    importHash: row.importHash)
                if let category = candidate.category, candidate.learnsCategory {
                    try ledger.learnCategory(merchant: row.description, category: category)
                }
            }
            summary.added += 1
        }
        try context.save()
        return summary
    }

    // MARK: Eşleştirme

    /// Eşleşen kaydı ekstre satırıyla işaretler; aynı ekstre tekrar yüklenirse "zaten eklenmiş" görünür.
    private func link(_ entry: LedgerEntry, to candidate: ImportCandidate) -> Bool {
        switch candidate.status {
        case .possibleDuplicate, .similarAmount, .installmentKnown:
            if entry.importHash == nil { entry.importHash = candidate.row.importHash }
            return true
        default:
            return false
        }
    }

    /// Kredi kartı ekstresi yalnızca o kartın kayıtlarıyla; banka dökümü ise tüm banka hesabı ve
    /// banka kartı kayıtlarıyla karşılaştırılır (banka kartı harcamaları vadesiz hesaptan çekilir).
    private func belongsToPool(_ entryAccount: Account?, target: Account) -> Bool {
        guard let entryAccount else { return false }
        if entryAccount === target { return true }
        switch target.type {
        case .bank, .debitCard: return entryAccount.type == .bank || entryAccount.type == .debitCard
        case .creditCard, .cash: return false
        }
    }

    private struct ManualMatch {
        let entry: LedgerEntry
        let difference: Money
        let merchantMatches: Bool
    }

    /// Satır ↔ kayıt çiftlerini puanlayıp bire bir atar.
    private func assignManualMatches(rows: [StatementRow], pool: [LedgerEntry]) -> [(Int, ManualMatch)] {
        struct Pair {
            let row: Int
            let entry: Int
            let difference: Money
            let days: Int
            let merchantMatches: Bool
        }

        var pairs: [Pair] = []
        for (rowIndex, row) in rows.enumerated() {
            for (entryIndex, entry) in pool.enumerated() where kindMatches(entry, row) {
                let difference = Money(minor: abs(entry.amountMinor - row.amount.minor))
                guard difference <= Self.tolerance(for: row.amount) else { continue }
                let days = abs(calendar.dateComponents([.day], from: calendar.startOfDay(for: entry.date),
                                                       to: calendar.startOfDay(for: row.date)).day ?? 99)
                guard days <= 2 else { continue }
                pairs.append(Pair(row: rowIndex, entry: entryIndex, difference: difference, days: days,
                                  merchantMatches: Self.merchantsMatch(manual: entry.merchant, statement: row.description)))
            }
        }

        pairs.sort { a, b in
            if a.difference != b.difference { return a.difference < b.difference }
            if a.days != b.days { return a.days < b.days }
            if a.merchantMatches != b.merchantMatches { return a.merchantMatches }
            return (a.row, a.entry) < (b.row, b.entry)
        }

        var usedRows = Set<Int>(), usedEntries = Set<Int>()
        var result: [(Int, ManualMatch)] = []
        for pair in pairs where !usedRows.contains(pair.row) && !usedEntries.contains(pair.entry) {
            usedRows.insert(pair.row)
            usedEntries.insert(pair.entry)
            result.append((pair.row, ManualMatch(entry: pool[pair.entry], difference: pair.difference,
                                                 merchantMatches: pair.merchantMatches)))
        }
        return result
    }

    /// "Migros" ↔ "MIGROS SANAL MARKET" tutar; işyeri yazılmamışsa da tutmuş sayılır.
    static func merchantsMatch(manual: String, statement: String) -> Bool {
        let manualWords = MerchantNormalizer.normalize(manual).split(separator: " ").filter { $0.count >= 3 }
        guard !manualWords.isEmpty else { return MerchantNormalizer.normalize(manual).isEmpty }
        let statementText = MerchantNormalizer.normalize(statement)
        return manualWords.contains { statementText.contains($0) }
    }

    private func kindMatches(_ entry: LedgerEntry, _ row: StatementRow) -> Bool {
        switch row.kind {
        case .expense: entry.kind == .expense || entry.kind == .investment
        case .income, .refund, .reward: entry.kind == .income
        case .payment: entry.kind == .transfer
        }
    }

    /// Planın aynı sıradaki taksiti bu satırla tarih (±20 gün) ve tutar (±1 ₺) olarak örtüşüyor mu?
    private func planEntry(for row: StatementRow, marker: InstallmentMarker, account: Account,
                           excluding used: Set<ObjectIdentifier>) -> LedgerEntry? {
        for plan in account.installmentPlans ?? [] where plan.count == marker.total {
            guard let entry = plan.sortedEntries.first(where: { $0.installmentIndex == marker.current }),
                  !used.contains(ObjectIdentifier(entry)) else { continue }
            let days = abs(calendar.dateComponents([.day], from: entry.date, to: row.date).day ?? 99)
            if days <= 20 && abs(entry.amountMinor - row.amount.minor) <= 100 { return entry }
        }
        return nil
    }
}

// MARK: - İçe aktarımı geri alma

extension ImportService {
    private struct ImportedSet {
        var entries: [LedgerEntry] = []
        var plans: [InstallmentPlan] = []
        var linked: [LedgerEntry] = []
        var rules: [MerchantRule] = []
    }

    func importedRecords(for account: Account) throws -> ImportedRecords {
        let set = try collectImported(for: account)
        return ImportedRecords(entries: set.entries.count, plans: set.plans.count, linked: set.linked.count,
                               rules: set.rules.count)
    }

    /// Hesaba içe aktarılmış işlemleri ve ekstreden oluşturulan taksit planlarını siler; elle girilen kayıtlar kalır,
    /// yalnızca ekstreyle eşleşmeleri kaldırılır (ekstre yeniden aktarılınca tekrar eşleşirler).
    /// `forgetLearned`: bu işyerleri için öğrenilmiş kategoriler de unutulur.
    func removeImported(for account: Account, forgetLearned: Bool) throws {
        let set = try collectImported(for: account)
        set.entries.forEach(context.delete)
        set.plans.forEach(context.delete)
        for entry in set.linked { entry.importHash = nil }
        if forgetLearned { set.rules.forEach(context.delete) }
        try context.save()
    }

    private func collectImported(for account: Account) throws -> ImportedSet {
        var set = ImportedSet()
        let entries = try context.fetch(FetchDescriptor<LedgerEntry>())
        set.entries = entries.filter { $0.source == .imported && ($0.account === account || $0.toAccount === account) }

        let plans = try context.fetch(FetchDescriptor<InstallmentPlan>()).filter { $0.account === account }
        set.plans = plans.filter { $0.isImported || Self.wasCreatedByLegacyImport($0) }

        let removed = Set(set.entries.map(ObjectIdentifier.init))
            .union(set.plans.flatMap { $0.entries ?? [] }.map(ObjectIdentifier.init))
        set.linked = entries.filter { entry in
            entry.importHash != nil && !removed.contains(ObjectIdentifier(entry))
                && (entry.account === account || entry.toAccount === account || entry.installmentPlan?.account === account)
        }

        let merchants = Set((set.entries.map(\.merchant) + set.plans.map(\.merchant)).map(MerchantNormalizer.normalize))
        set.rules = try context.fetch(FetchDescriptor<MerchantRule>()).filter { merchants.contains($0.pattern) }
        return set
    }

    /// İşaretten önceki sürümler: ekstreden oluşan planda, ekstredeki taksitin parmak izi plan adıyla birebir tutar.
    /// Elle girilip ekstreyle eşleşen planda parmak izi ekstredeki açıklamadan gelir, plan adı kullanıcınınkidir.
    private static func wasCreatedByLegacyImport(_ plan: InstallmentPlan) -> Bool {
        (plan.entries ?? []).contains { entry in
            entry.importHash != nil && entry.importHash == StatementParser.importHash(date: entry.date, amount: entry.amount,
                                                                                     description: plan.merchant)
        }
    }
}

