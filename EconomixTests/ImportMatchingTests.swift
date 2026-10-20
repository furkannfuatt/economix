import Foundation
import SwiftData
import Testing
import EconomixCore
@testable import Economix

private func d(_ y: Int, _ m: Int, _ day: Int) -> Date {
    FinanceCalendar.calendar.date(from: DateComponents(year: y, month: m, day: day))!
}

private func kurus(_ value: Int) -> Money { Money(minor: value) }

/// Elle girilen işlemlerle ekstre satırlarının eşleştirilmesi.
@Suite("İçe aktarma eşleştirme")
@MainActor
struct ImportMatchingTests {
    let f = Fixture()

    func parse(_ rows: [[String]]) throws -> StatementParseResult {
        try StatementParser.parse(rows: [["Tarih", "Açıklama", "Tutar"]] + rows, profile: .generic)
    }

    @discardableResult
    func manual(_ minor: Int, _ date: Date, merchant: String, account: Account) throws -> LedgerEntry {
        try LedgerService(context: f.context).addEntry(amount: kurus(minor), kind: .expense, date: date, category: nil,
                                                       account: account, merchant: merchant)
    }

    func makeAccount(_ name: String, _ type: AccountType) -> Account {
        let account = Account(name: name, type: type)
        f.context.insert(account)
        return account
    }

    @Test("Bir elle kayıt yalnızca bir ekstre satırıyla eşleşir")
    func oneToOne() throws {
        let card = f.makeCard()
        let coffee = try manual(150_00, d(2026, 10, 4), merchant: "Starbucks", account: card)
        let result = try parse([["04.10.2026", "STARBUCKS NISANTASI", "150,00"],
                                ["05.10.2026", "STARBUCKS NISANTASI", "150,00"]])
        let candidates = try ImportService(context: f.context).prepare(result, account: card)
        #expect(candidates[0].status == .possibleDuplicate)
        #expect(candidates[0].matchedEntry === coffee)
        #expect(!candidates[0].include)
        #expect(candidates[1].status == .new)
        #expect(candidates[1].matchedEntry == nil)
        #expect(candidates[1].include)
    }

    @Test("Tam tutar eşleşmesi yakın tutardan önce gelir")
    func exactBeatsNear() throws {
        let card = f.makeCard()
        let a = try manual(150_00, d(2026, 10, 4), merchant: "Kahve", account: card)
        let b = try manual(152_00, d(2026, 10, 4), merchant: "Kahve", account: card)
        let result = try parse([["04.10.2026", "KAHVE DUNYASI", "152,00"], ["04.10.2026", "KAHVE DUNYASI", "150,00"]])
        let candidates = try ImportService(context: f.context).prepare(result, account: card)
        #expect(candidates[0].matchedEntry === b)
        #expect(candidates[1].matchedEntry === a)
        #expect(candidates.allSatisfy { $0.status == .possibleDuplicate })
    }

    @Test("Kuruşsuz girilen tutar ve tutan işyeri: aynı alışveriş sayılır, tutar ekstreye göre düzeltilir")
    func nearAmountSameMerchant() throws {
        let card = f.makeCard()
        let entry = try manual(245_00, d(2026, 10, 2), merchant: "Migros", account: card)
        let service = ImportService(context: f.context)
        let result = try parse([["02.10.2026", "MIGROS SANAL MARKET", "245,28"]])
        let candidates = try service.prepare(result, account: card)
        #expect(candidates[0].status == .similarAmount)
        #expect(candidates[0].matchedEntry === entry)
        #expect(candidates[0].amountDifference == kurus(28))
        #expect(!candidates[0].include)

        let summary = try service.commit(candidates, account: card)
        #expect(summary.linked == 1)
        #expect(summary.amountsCorrected == 1)
        #expect(entry.amount == kurus(245_28))
        #expect(entry.importHash == result.rows[0].importHash)
        #expect(try service.prepare(result, account: card)[0].status == .duplicate)
    }

    @Test("Yakın tutar ama farklı işyeri: 'benzer olabilir' notuyla dahil gelir")
    func nearAmountOtherMerchant() throws {
        let card = f.makeCard()
        let entry = try manual(1_000_00, d(2026, 10, 2), merchant: "Market", account: card)
        let result = try parse([["02.10.2026", "A101", "1.015,00"]])
        let candidate = try ImportService(context: f.context).prepare(result, account: card)[0]
        #expect(candidate.status == .similarAmount)
        #expect(candidate.matchedEntry === entry)
        #expect(candidate.include)
    }

    @Test("Tolerans dışındaki tutar ya da ±2 günden uzak tarih eşleşmez")
    func outsideTolerance() throws {
        let card = f.makeCard()
        try manual(245_00, d(2026, 10, 2), merchant: "Migros", account: card)
        try manual(500_00, d(2026, 10, 2), merchant: "Migros", account: card)
        let result = try parse([["02.10.2026", "MIGROS", "260,00"], ["06.10.2026", "MIGROS", "500,00"]])
        let candidates = try ImportService(context: f.context).prepare(result, account: card)
        #expect(candidates.allSatisfy { $0.status == .new && $0.matchedEntry == nil })
    }

    @Test("Eşleşen elle kayıt işaretlenir; aynı ekstre tekrar yüklenince 'zaten eklenmiş' olur")
    func exactMatchIsLinked() throws {
        let card = f.makeCard()
        let entry = try manual(250_00, d(2026, 10, 1), merchant: "Migros", account: card)
        let service = ImportService(context: f.context)
        let result = try parse([["01.10.2026", "MIGROS", "250,00"], ["03.10.2026", "A101", "80,00"]])
        let summary = try service.commit(try service.prepare(result, account: card), account: card)
        #expect(summary.added == 1)
        #expect(summary.linked == 1)
        #expect(summary.amountsCorrected == 0)
        #expect(entry.importHash == result.rows[0].importHash)
        #expect(try service.prepare(result, account: card).allSatisfy { $0.status == .duplicate })
        #expect(try f.context.fetchCount(FetchDescriptor<LedgerEntry>()) == 2)
    }

    @Test("Banka kartı harcaması, banka hesabı dökümü yüklenirken de eşleşir")
    func debitCardMatchesBankStatement() throws {
        let debit = makeAccount("Garanti BBVA Banka Kartı", .debitCard)
        let bank = makeAccount("Garanti Vadesiz", .bank)
        let entry = try manual(320_00, d(2026, 10, 7), merchant: "BIM", account: debit)
        let rows = [["Tarih", "Açıklama", "Tutar"], ["07.10.2026", "BIM MAGAZALARI", "-320,00"],
                    ["08.10.2026", "HAVALE GELEN", "1.000,00"]]
        let result = try StatementParser.parse(rows: rows, profile: .generic,
                                               expenseSign: ImportService.expenseSign(for: bank))
        let candidates = try ImportService(context: f.context).prepare(result, account: bank)
        #expect(candidates[0].status == .possibleDuplicate)
        #expect(candidates[0].matchedEntry === entry)
    }

    @Test("Hedef hesap türü işaret ipucunu belirler")
    func expenseSignHint() {
        #expect(ImportService.expenseSign(for: Account(name: "Vadesiz", type: .bank)) == .negative)
        #expect(ImportService.expenseSign(for: Account(name: "Banka kartı", type: .debitCard)) == .negative)
        #expect(ImportService.expenseSign(for: Account(name: "Bonus", type: .creditCard)) == .auto)
    }

    @Test("Kredi kartı ekstresi başka hesaptaki kayıtla eşleşmez")
    func creditCardIsolated() throws {
        let card = f.makeCard()
        let debit = makeAccount("Banka Kartı", .debitCard)
        try manual(320_00, d(2026, 10, 7), merchant: "BIM", account: debit)
        let result = try parse([["07.10.2026", "BIM MAGAZALARI", "320,00"]])
        #expect(try ImportService(context: f.context).prepare(result, account: card)[0].status == .new)
    }

    @Test("Banka kartında taksit seçilemez, kart ekstresi yoktur")
    func debitCardType() {
        let debit = Account(name: "Banka Kartı", type: .debitCard)
        #expect(!debit.isCreditCard)
        #expect(AccountType.debitCard.title == "Banka kartı")
        #expect(CardPreset.all.filter { $0.type == .debitCard }.count == 3)
        #expect(CardPreset.all.filter { $0.type == .creditCard }.count == 3)
    }
}
