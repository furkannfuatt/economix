import Foundation
import Testing
@testable import EconomixCore

@Suite("Taksit takvimi")
struct InstallmentSchedulerTests {
    @Test("İlk taksit alım tarihinde, sonrakiler aylık; ay sonu kaymaz")
    func datesFromPurchase() {
        let lines = InstallmentScheduler.schedule(total: tl(12_000), count: 6, purchaseDate: d(2027, 1, 31))
        #expect(lines.map(\.date) == [d(2027, 1, 31), d(2027, 2, 28), d(2027, 3, 31),
                                      d(2027, 4, 30), d(2027, 5, 31), d(2027, 6, 30)])
        #expect(lines.map(\.index) == [1, 2, 3, 4, 5, 6])
        #expect(lines.allSatisfy { $0.amount == tl(2_000) })
    }

    @Test("Kuruş artığı ilk taksite eklenir")
    func remainder() {
        let lines = InstallmentScheduler.schedule(total: tl(1_000), count: 3, purchaseDate: d(2026, 10, 1))
        #expect(lines.map(\.amount.minor) == [33_334, 33_333, 33_333])
    }

    @Test("Tek çekim tek satır üretir")
    func single() {
        let lines = InstallmentScheduler.schedule(total: tl(500), count: 1, purchaseDate: d(2026, 10, 1))
        #expect(lines.count == 1)
        #expect(lines[0].amount == tl(500))
    }

    @Test("İlerleme: ödenen, kalan ve bitiş ayı")
    func progress() {
        let lines = InstallmentScheduler.schedule(total: tl(6_000), count: 6, purchaseDate: d(2026, 8, 10))
        let p = InstallmentScheduler.progress(of: lines, asOf: d(2026, 10, 12))
        #expect(p.paidCount == 3)
        #expect(p.remainingCount == 3)
        #expect(p.remainingAmount == tl(3_000))
        #expect(p.lastMonth == YearMonth(year: 2027, month: 1))
        #expect(p.nextLine?.date == d(2026, 11, 10))
        #expect(!p.isFinished)
    }

    @Test("Erken kapatma kalanları tek satırda toplar")
    func closeEarly() {
        let lines = InstallmentScheduler.schedule(total: tl(6_000), count: 6, purchaseDate: d(2026, 8, 10))
        let closed = InstallmentScheduler.closeEarly(lines, on: d(2026, 10, 20))
        #expect(closed.count == 4)
        #expect(closed.last?.amount == tl(3_000))
        #expect(closed.last?.date == d(2026, 10, 20))
        #expect(closed.map(\.amount).sum() == tl(6_000))
    }

    @Test("Görünüm: aylık taksit yükü ve biten taksitlerin rahatlaması")
    func outlook() {
        let phone = PlanSchedule(id: "phone", title: "Telefon",
                                 lines: InstallmentScheduler.schedule(total: tl(12_000), count: 4, purchaseDate: d(2026, 9, 5)))
        let tv = PlanSchedule(id: "tv", title: "TV",
                              lines: InstallmentScheduler.schedule(total: tl(6_000), count: 6, purchaseDate: d(2026, 10, 1)))
        let o = InstallmentScheduler.outlook(plans: [phone, tv], from: YearMonth(year: 2026, month: 10), monthCount: 6)

        #expect(o.months.map(\.month.month) == [10, 11, 12, 1, 2, 3])
        #expect(o.months.map(\.amount) == [tl(4_000), tl(4_000), tl(4_000), tl(1_000), tl(1_000), tl(1_000)])
        #expect(o.reliefs.count == 1)
        #expect(o.reliefs[0].month == YearMonth(year: 2027, month: 1))
        #expect(o.reliefs[0].amount == tl(3_000))
        #expect(o.reliefs[0].titles == ["Telefon"])
    }
}
