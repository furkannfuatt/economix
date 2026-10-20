import Foundation
import SwiftData
import EconomixCore

/// Abonelik, maaş, kira gibi düzenli kalemlerin vadesi gelen işlemlerini üretir.
/// Uygulama açıldığında ve öne geldiğinde çalışır; kaçırılan vadeleri de yakalar.
struct RecurringGenerator {
    let context: ModelContext
    var calendar: Calendar = FinanceCalendar.calendar

    @discardableResult
    func run(asOf date: Date = .now) throws -> Int {
        let items = try context.fetch(FetchDescriptor<RecurringItem>(predicate: #Predicate { $0.isActive }))
        var created = 0
        for item in items {
            let dates = RecurrenceEngine.occurrences(of: item.rule, after: item.lastGeneratedDate,
                                                     through: date, calendar: calendar)
            for occurrence in dates {
                let entry = LedgerEntry(amount: item.amount, kind: item.kind, date: occurrence,
                                        merchant: item.merchant.isEmpty ? item.title : item.merchant,
                                        source: .recurring)
                context.insert(entry)
                entry.recurringItem = item
                entry.category = item.category
                entry.account = item.account
                created += 1
            }
            if let last = dates.last { item.lastGeneratedDate = last }
        }
        if context.hasChanges { try context.save() }
        return created
    }
}

extension RecurringItem {
    /// Yeni eklenen kalemin geçmiş vadeleri üretilmesin; bugünkü vade dahil sonrakiler üretilsin.
    func skipPastOccurrences(asOf date: Date = .now, calendar: Calendar = FinanceCalendar.calendar) {
        lastGeneratedDate = calendar.startOfDay(for: date).addingTimeInterval(-1)
    }
}
