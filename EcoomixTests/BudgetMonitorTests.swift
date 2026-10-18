import Foundation
import SwiftData
import Testing
import EcoomixCore
@testable import Ecoomix

private func d(_ y: Int, _ m: Int, _ day: Int) -> Date {
    FinanceCalendar.calendar.date(from: DateComponents(year: y, month: m, day: day, hour: 12))!
}

final class RecordingNotifier: Notifier {
    var sent: [(id: String, title: String, body: String)] = []
    func notify(id: String, title: String, body: String) { sent.append((id, title, body)) }
}

@Suite("BudgetMonitor")
@MainActor
struct BudgetMonitorTests {
    let fixture = Fixture()
    let notifier = RecordingNotifier()
    let defaults = UserDefaults(suiteName: "budget-tests-\(UUID().uuidString)")!

    func setUp() -> (BudgetMonitor, EntryCategory, LedgerService) {
        let category = fixture.makeCategory("Market")
        category.monthlyLimit = Money(minor: 1_000_00)
        let monitor = BudgetMonitor(context: fixture.context, defaults: defaults, notifier: notifier)
        return (monitor, category, LedgerService(context: fixture.context))
    }

    @Test("%80 eşiği bir kez bildirilir")
    func warnsOnce() throws {
        let (monitor, category, service) = setUp()
        try service.addEntry(amount: Money(minor: 850_00), kind: .expense, date: d(2026, 10, 5), category: category, account: nil)
        #expect(monitor.check(category: category, date: d(2026, 10, 5), asOf: d(2026, 10, 18)) == [0.8])
        #expect(monitor.check(category: category, date: d(2026, 10, 5), asOf: d(2026, 10, 18)).isEmpty)
        #expect(notifier.sent.count == 1)
        #expect(notifier.sent[0].title == "Market bütçesinin %85'i doldu")
    }

    @Test("Limit aşılınca ayrıca bildirilir")
    func exceeded() throws {
        let (monitor, category, service) = setUp()
        try service.addEntry(amount: Money(minor: 850_00), kind: .expense, date: d(2026, 10, 5), category: category, account: nil)
        _ = monitor.check(category: category, date: d(2026, 10, 5), asOf: d(2026, 10, 18))
        try service.addEntry(amount: Money(minor: 200_00), kind: .expense, date: d(2026, 10, 6), category: category, account: nil)
        #expect(monitor.check(category: category, date: d(2026, 10, 6), asOf: d(2026, 10, 18)) == [1.0])
        #expect(notifier.sent.last?.title == "Market bütçesi aşıldı")
    }

    @Test("Bütçe ayı 23'ünde başlıyorsa harcama o dönemden sayılır")
    func customMonthStart() throws {
        defaults.set(23, forKey: MonthSettings.key)
        let (monitor, category, service) = setUp()
        // 20 Ekim önceki döneme (23 Eyl–22 Eki) ait; 25 Ekim yeni dönemin (23 Eki–22 Kas) ilk günlerinden.
        try service.addEntry(amount: Money(minor: 700_00), kind: .expense, date: d(2026, 10, 20), category: category, account: nil)
        try service.addEntry(amount: Money(minor: 300_00), kind: .expense, date: d(2026, 10, 25), category: category, account: nil)
        #expect(monitor.check(category: category, date: d(2026, 10, 25), asOf: d(2026, 10, 26)).isEmpty)
        try service.addEntry(amount: Money(minor: 550_00), kind: .expense, date: d(2026, 11, 20), category: category, account: nil)
        #expect(monitor.check(category: category, date: d(2026, 11, 20), asOf: d(2026, 11, 20)) == [0.8])
        #expect(monitor.check(category: category, date: d(2026, 10, 20), asOf: d(2026, 11, 20)).isEmpty,
                "Önceki dönemin harcaması bildirim üretmez")
    }

    @Test("Geçmiş aya eklenen işlem bildirim üretmez")
    func pastMonth() throws {
        let (monitor, category, service) = setUp()
        try service.addEntry(amount: Money(minor: 2_000_00), kind: .expense, date: d(2026, 9, 5), category: category, account: nil)
        #expect(monitor.check(category: category, date: d(2026, 9, 5), asOf: d(2026, 10, 18)).isEmpty)
    }

    @Test("Bütçe uyarıları kapalıysa bildirim yok")
    func disabled() throws {
        let (monitor, category, service) = setUp()
        defaults.set(false, forKey: NotificationPreferences.budgetKey)
        try service.addEntry(amount: Money(minor: 2_000_00), kind: .expense, date: d(2026, 10, 5), category: category, account: nil)
        #expect(monitor.check(category: category, date: d(2026, 10, 5), asOf: d(2026, 10, 18)).isEmpty)
    }
}
