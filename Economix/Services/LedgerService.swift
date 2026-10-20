import Foundation
import SwiftData
import EconomixCore

/// İşlem, taksit planı ve işyeri kuralı yazma işlemleri. Görünümler veriyi doğrudan değil bu servis üzerinden değiştirir.
struct LedgerService {
    let context: ModelContext
    var calendar: Calendar = FinanceCalendar.calendar
    /// Gider eklendiğinde/değiştiğinde çağrılır (bütçe bildirimleri için).
    var onExpenseChange: ((EntryCategory, Date) -> Void)?

    // MARK: İşlemler

    @discardableResult
    func addEntry(amount: Money, kind: TxKind, date: Date, category: EntryCategory?, account: Account?,
                  toAccount: Account? = nil, merchant: String = "", note: String = "",
                  source: EntrySource = .manual, importHash: String? = nil) throws -> LedgerEntry {
        let entry = LedgerEntry(amount: amount, kind: kind, date: date, merchant: merchant, note: note, source: source)
        entry.importHash = importHash
        context.insert(entry)
        entry.category = kind == .transfer ? nil : category
        entry.account = account
        entry.toAccount = kind == .transfer ? toAccount : nil
        try context.save()
        notifyExpenseChange(entry)
        return entry
    }

    func save(_ entry: LedgerEntry) throws {
        try context.save()
        notifyExpenseChange(entry)
    }

    func delete(_ entry: LedgerEntry) throws {
        context.delete(entry)
        try context.save()
    }

    // MARK: Taksitler

    @discardableResult
    func addInstallmentPurchase(total: Money, count: Int, purchaseDate: Date, category: EntryCategory?,
                                account: Account?, merchant: String, title: String = "") throws -> InstallmentPlan {
        let plan = InstallmentPlan(title: title, merchant: merchant, total: total, count: count, purchaseDate: purchaseDate)
        context.insert(plan)
        plan.account = account
        plan.category = category
        generateEntries(for: plan)
        try context.save()
        if let category { onExpenseChange?(category, purchaseDate) }
        return plan
    }

    /// Tutar, taksit sayısı veya tarih değişince taksitler baştan üretilir.
    func updatePlan(_ plan: InstallmentPlan, total: Money, count: Int, purchaseDate: Date) throws {
        removeEntries(of: plan, where: { _ in true })
        plan.totalMinor = total.minor
        plan.count = count
        plan.purchaseDate = purchaseDate
        plan.closedEarlyAt = nil
        generateEntries(for: plan)
        try context.save()
    }

    /// Kategori/hesap/başlık gibi tutar dışı alanları taksitlere yansıtır.
    func propagateDetails(of plan: InstallmentPlan) throws {
        for entry in plan.entries ?? [] {
            entry.category = plan.category
            entry.account = plan.account
            entry.merchant = plan.merchant
            entry.note = plan.title
        }
        try context.save()
    }

    /// Kalan taksitler `date` tarihinde tek işlemde kapatılır.
    func closeEarly(_ plan: InstallmentPlan, on date: Date) throws {
        let entries = plan.sortedEntries
        let remaining = entries.filter { $0.date > date }
        guard !remaining.isEmpty else { return }
        let keptCount = entries.count - remaining.count
        let remainingTotal = remaining.map(\.amount).sum()
        removeEntries(of: plan, where: { $0.date > date })

        let closing = makeEntry(for: plan, index: keptCount + 1, date: date, amount: remainingTotal)
        plan.entries?.append(closing)
        plan.count = keptCount + 1
        plan.closedEarlyAt = date
        try context.save()
    }

    func deletePlan(_ plan: InstallmentPlan) throws {
        context.delete(plan)
        try context.save()
    }

    private func generateEntries(for plan: InstallmentPlan) {
        let lines = InstallmentScheduler.schedule(total: plan.total, count: plan.count,
                                                  purchaseDate: plan.purchaseDate, calendar: calendar)
        for line in lines {
            let entry = makeEntry(for: plan, index: line.index, date: line.date, amount: line.amount)
            plan.entries?.append(entry)
        }
    }

    private func makeEntry(for plan: InstallmentPlan, index: Int, date: Date, amount: Money) -> LedgerEntry {
        let entry = LedgerEntry(amount: amount, kind: .expense, date: date, merchant: plan.merchant,
                                note: plan.title, source: .installment)
        context.insert(entry)
        entry.installmentIndex = index
        entry.installmentPlan = plan
        entry.account = plan.account
        entry.category = plan.category
        return entry
    }

    private func removeEntries(of plan: InstallmentPlan, where shouldRemove: (LedgerEntry) -> Bool) {
        let doomed = (plan.entries ?? []).filter(shouldRemove)
        plan.entries?.removeAll { entry in doomed.contains { $0 === entry } }
        doomed.forEach(context.delete)
    }

    // MARK: İşyeri kuralları

    /// Kullanıcının seçtiği kategoriyi bu işyeri için hatırlar.
    func learnCategory(merchant: String, category: EntryCategory) throws {
        let pattern = MerchantNormalizer.normalize(merchant)
        guard !pattern.isEmpty else { return }
        let descriptor = FetchDescriptor<MerchantRule>(predicate: #Predicate { $0.pattern == pattern })
        if let rule = try context.fetch(descriptor).first {
            rule.category = category
        } else {
            context.insert(MerchantRule(pattern: pattern, category: category))
        }
        try context.save()
    }

    /// Daha önce öğrenilmiş kategori: önce birebir işyeri, yoksa aynı marka (başka şube/şehir yazımı).
    func learnedCategory(for merchant: String) -> EntryCategory? {
        let pattern = MerchantNormalizer.normalize(merchant)
        guard !pattern.isEmpty else { return nil }
        let exact = FetchDescriptor<MerchantRule>(predicate: #Predicate { $0.pattern == pattern })
        if let category = (try? context.fetch(exact))?.first?.category { return category }

        let brand = MerchantNormalizer.brandKey(merchant)
        guard !brand.isEmpty else { return nil }
        let rules = (try? context.fetch(FetchDescriptor<MerchantRule>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)]))) ?? []
        return rules.first { MerchantNormalizer.brandKey($0.pattern) == brand }?.category
    }

    private func notifyExpenseChange(_ entry: LedgerEntry) {
        guard entry.kind == .expense, let category = entry.category else { return }
        onExpenseChange?(category, entry.date)
    }
}
