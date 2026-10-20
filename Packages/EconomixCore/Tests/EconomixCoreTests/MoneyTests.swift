import Foundation
import Testing
@testable import EconomixCore

@Suite("Money")
struct MoneyTests {
    @Test("Türk formatında binlik ayraç ve kuruş gösterir")
    func formatsTurkish() {
        #expect(Money(minor: 123_456).formatted() == "1.234,56 ₺")
        #expect(Money(minor: 5).formatted() == "0,05 ₺")
        #expect(Money(minor: 100_000_000).formatted() == "1.000.000,00 ₺")
        #expect(Money(minor: -4_590).formatted() == "-45,90 ₺")
    }

    @Test("Kuruşsuz kısa format yuvarlar")
    func formatsWithoutDecimals() {
        #expect(Money(minor: 123_456).formatted(decimals: false) == "1.235 ₺")
        #expect(Money(minor: 99).formatted(decimals: false) == "1 ₺")
    }

    @Test("Banka metinlerindeki tutarları çözer", arguments: [
        ("1.234,56", 123_456),
        ("1234,56", 123_456),
        ("1,234.56", 123_456),
        ("45,9", 4_590),
        ("-45,90", -4_590),
        ("45,90-", -4_590),
        ("1.234", 123_400),
        ("12.50", 1_250),
        ("1.250,00 TL", 125_000),
        ("₺ 99", 9_900),
        ("+300,00", 30_000),
        ("(150,00)", -15_000),
    ])
    func parses(text: String, expected: Int) {
        #expect(Money.parse(text) == Money(minor: expected))
    }

    @Test("Geçersiz metin nil döner", arguments: ["", "abc", "--", "1,2,3,4"])
    func parseRejectsGarbage(text: String) {
        #expect(Money.parse(text) == nil)
    }

    @Test("10 milyar TL'yi aşan ya da çok uzun tutarlar reddedilir", arguments: [
        "99999999999999999", "999999999999999999999", "10.000.000.000,01", "-10000000001",
    ])
    func parseRejectsHugeAmounts(text: String) {
        #expect(Money.parse(text) == nil)
    }

    @Test("Üst sınırdaki tutar kabul edilir")
    func parseAcceptsLimit() {
        #expect(Money.parse("10.000.000.000,00") == Money.maxMagnitude)
        #expect(Money.parse("-10.000.000.000") == -Money.maxMagnitude)
    }

    @Test("Aritmetik taşmada çökmez, en büyük değere doyar")
    func saturatingArithmetic() {
        let max = Money(minor: .max)
        #expect(max + Money(minor: 1) == max)
        #expect(-max - Money(minor: 10) == -max)
        #expect(max * 3 == max)
        #expect(max * -3 == -max)
        var total = max
        total += max
        #expect(total == max)
        total -= -max
        #expect(total == max)
        #expect([max, max, max].sum() == max)
        #expect(-Money(minor: .min) == max)
        #expect(max.scaled(numerator: 10, denominator: 1) == max)
    }

    @Test("En küçük değer biçimlenirken çökmez")
    func formatsExtremes() {
        #expect(Money(minor: .min).formatted().hasPrefix("-"))
        #expect(Money(minor: .min).magnitude.minor == Int.max)
    }

    @Test("Bölme artığı ilk parçaya eklenir")
    func splitPutsRemainderFirst() {
        let parts = Money(minor: 100_000).split(into: 3)
        #expect(parts == [Money(minor: 33_334), Money(minor: 33_333), Money(minor: 33_333)])
        #expect(parts.reduce(.zero, +) == Money(minor: 100_000))
    }

    @Test("Toplama, çıkarma ve karşılaştırma")
    func arithmetic() {
        let a = Money(minor: 1_000), b = Money(minor: 250)
        #expect(a + b == Money(minor: 1_250))
        #expect(a - b == Money(minor: 750))
        #expect(b < a)
        #expect([a, b].sum() == Money(minor: 1_250))
    }
}

@Suite("YearMonth")
struct YearMonthTests {
    let cal = FinanceCalendar.calendar

    @Test("Ay ekleme yıl sınırını aşar")
    func addingMonths() {
        let ym = YearMonth(year: 2026, month: 11)
        #expect(ym.adding(months: 3) == YearMonth(year: 2027, month: 2))
        #expect(ym.adding(months: -11) == YearMonth(year: 2025, month: 12))
    }

    @Test("Ay gün sayısı ve sınırlar")
    func boundaries() {
        let feb = YearMonth(year: 2028, month: 2)
        #expect(feb.dayCount == 29)
        #expect(YearMonth(date: feb.start) == feb)
        #expect(YearMonth(date: feb.end) == YearMonth(year: 2028, month: 3))
        #expect(feb.date(day: 31) == cal.date(from: DateComponents(year: 2028, month: 2, day: 29)))
    }

    @Test("Türkçe ay adı")
    func title() {
        #expect(YearMonth(year: 2026, month: 10).title == "Ekim 2026")
        #expect(YearMonth(year: 2026, month: 2).shortTitle == "Şub")
    }

    @Test("Aralık listesi")
    func range() {
        let months = YearMonth.range(from: YearMonth(year: 2026, month: 11), to: YearMonth(year: 2027, month: 1))
        #expect(months.map(\.month) == [11, 12, 1])
    }
}
