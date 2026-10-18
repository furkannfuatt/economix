import Foundation
import SwiftData
import EcoomixCore

/// Önizleme ekranındaki bir ekstre satırı.
struct ImportCandidate: Identifiable {
    enum Status {
        /// Yeni işlem.
        case new
        /// Aynı satır daha önce içe aktarılmış.
        case duplicate
        /// Elle girilmiş benzer bir işlem var (aynı tutar, ±2 gün).
        case possibleDuplicate
        /// Taksit, mevcut bir plana ait.
        case installmentKnown
        /// Taksit; yeni plan oluşturulacak.
        case newInstallmentPlan
        /// Karta yapılan ödeme.
        case payment
    }

    let row: StatementRow
    var status: Status
    var include: Bool
    var category: EntryCategory?

    var id: Int { row.lineNumber }
}

struct ImportSummary {
    var added = 0
    var plansCreated = 0
    var skipped = 0
}

struct ImportService {
    let context: ModelContext
    var calendar: Calendar = FinanceCalendar.calendar

    private var ledger: LedgerService { LedgerService(context: context) }

    func prepare(_ result: StatementParseResult, account: Account) throws -> [ImportCandidate] {
        let entries = try context.fetch(FetchDescriptor<LedgerEntry>())
        let knownHashes = Set(entries.compactMap(\.importHash))
        let accountEntries = entries.filter { $0.account === account && $0.importHash == nil }
        let plans = (account.installmentPlans ?? [])
        let categories = try context.fetch(FetchDescriptor<EntryCategory>())

        return result.rows.map { row in
            var candidate = ImportCandidate(row: row, status: .new, include: true, category: nil)

            if knownHashes.contains(row.importHash) {
                candidate.status = .duplicate
                candidate.include = false
            } else if row.kind == .payment {
                candidate.status = .payment
                candidate.include = false
            } else if let marker = row.installment, row.kind == .expense {
                candidate.status = matchesPlan(row: row, marker: marker, plans: plans) ? .installmentKnown : .newInstallmentPlan
                candidate.include = candidate.status == .newInstallmentPlan
            } else if accountEntries.contains(where: { isSimilar($0, to: row) }) {
                candidate.status = .possibleDuplicate
                candidate.include = false
            }

            if row.kind == .expense {
                candidate.category = ledger.learnedCategory(for: row.description)
                    ?? MerchantCategorizer.suggestedSeedKey(for: row.description).flatMap { key in
                        categories.first { $0.seedKey == key && $0.kind == .expense }
                    }
            }
            return candidate
        }
    }

    @discardableResult
    func commit(_ candidates: [ImportCandidate], account: Account) throws -> ImportSummary {
        var summary = ImportSummary()
        for candidate in candidates {
            guard candidate.include else {
                summary.skipped += 1
                continue
            }
            let row = candidate.row
            switch (candidate.status, row.kind) {
            case (.newInstallmentPlan, _):
                guard let marker = row.installment else { continue }
                let purchase = calendar.date(byAdding: .month, value: -(marker.current - 1), to: row.date)!
                let plan = try ledger.addInstallmentPurchase(total: row.amount * marker.total, count: marker.total,
                                                             purchaseDate: purchase, category: candidate.category,
                                                             account: account, merchant: row.description)
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
            case (_, .income):
                try ledger.addEntry(amount: row.amount, kind: .income, date: row.date, category: candidate.category,
                                    account: account, merchant: row.description, source: .imported,
                                    importHash: row.importHash)
            case (_, .expense):
                try ledger.addEntry(amount: row.amount, kind: .expense, date: row.date, category: candidate.category,
                                    account: account, merchant: row.description, source: .imported,
                                    importHash: row.importHash)
                if let category = candidate.category {
                    try ledger.learnCategory(merchant: row.description, category: category)
                }
            }
            summary.added += 1
        }
        try context.save()
        return summary
    }

    // MARK: Eşleştirme

    /// Planın aynı sıradaki taksiti bu satırla tarih (±20 gün) ve tutar (±1 ₺) olarak örtüşüyor mu?
    private func matchesPlan(row: StatementRow, marker: InstallmentMarker, plans: [InstallmentPlan]) -> Bool {
        plans.contains { plan in
            guard plan.count == marker.total,
                  let entry = plan.sortedEntries.first(where: { $0.installmentIndex == marker.current }) else { return false }
            let days = abs(calendar.dateComponents([.day], from: entry.date, to: row.date).day ?? 99)
            return days <= 20 && abs(entry.amountMinor - row.amount.minor) <= 100
        }
    }

    private func isSimilar(_ entry: LedgerEntry, to row: StatementRow) -> Bool {
        guard entry.amountMinor == row.amount.minor else { return false }
        let kindMatches = switch row.kind {
        case .expense: entry.kind == .expense
        case .income, .refund: entry.kind == .income
        case .payment: entry.kind == .transfer
        }
        guard kindMatches else { return false }
        let days = abs(calendar.dateComponents([.day], from: calendar.startOfDay(for: entry.date),
                                               to: calendar.startOfDay(for: row.date)).day ?? 99)
        return days <= 2
    }
}
