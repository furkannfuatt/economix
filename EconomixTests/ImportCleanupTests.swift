import Foundation
import SwiftData
import Testing
import EconomixCore
@testable import Economix

private func d(_ y: Int, _ m: Int, _ day: Int) -> Date {
    FinanceCalendar.calendar.date(from: DateComponents(year: y, month: m, day: day))!
}

private func tl(_ lira: Int) -> Money { Money(minor: lira * 100) }

@Suite("İçe aktarımı geri alma")
@MainActor
struct ImportCleanupTests {
    let f = Fixture()

    func parse(_ rows: [[String]]) throws -> StatementParseResult {
        try StatementParser.parse(rows: [["Tarih", "Açıklama", "Tutar"]] + rows, profile: .generic)
    }

    var statement: [[String]] {
        [["01.10.2026", "MIGROS KADIKOY", "250,00"],
         ["03.10.2026", "ZARA", "100,00"],
         ["04.10.2026", "ZARA IADE", "-50,00"],
         ["06.10.2026", "VATAN BILGISAYAR TAKSIT 2/6", "500,00"],
         ["10.10.2026", "ODEMENIZ ICIN TESEKKURLER", "-1.000,00"]]
    }

    @Test("Kartın içe aktarılanları silinir; elle girilenler kalır, ekstre yeniden aynı biçimde aktarılabilir")
    func removesImportedRecords() throws {
        let card = f.makeCard(), other = f.makeCard()
        let clothes = f.makeCategory("Giyim")
        let service = LedgerService(context: f.context)
        let manual = try service.addEntry(amount: tl(250), kind: .expense, date: d(2026, 10, 1), category: nil,
                                          account: card, merchant: "Migros")
        let manualPlan = try service.addInstallmentPurchase(total: tl(900), count: 3, purchaseDate: d(2026, 8, 1),
                                                            category: nil, account: card, merchant: "Teknosa")
        let elsewhere = try service.addEntry(amount: tl(70), kind: .expense, date: d(2026, 10, 2), category: nil,
                                             account: other, merchant: "BIM", source: .imported, importHash: "baska")

        let importer = ImportService(context: f.context)
        var candidates = try importer.prepare(try parse(statement), account: card)
        ImportCandidate.applyCategory(clothes, at: 1, in: &candidates)
        candidates[4].include = true  // ödeme de aktarılmış olsun
        try importer.commit(candidates, account: card)
        #expect(manual.importHash != nil, "Elle girilen kayıt ekstreyle eşleşti")

        let found = try importer.importedRecords(for: card)
        #expect(found.entries == 3)  // ZARA, ZARA IADE, ödeme
        #expect(found.plans == 1)
        #expect(found.linked == 1)
        #expect(found.rules == 1)

        try importer.removeImported(for: card, forgetLearned: true)

        let entries = try f.context.fetch(FetchDescriptor<LedgerEntry>())
        #expect(entries.contains { $0 === manual } && manual.importHash == nil)
        #expect(entries.contains { $0 === elsewhere }, "Başka karta dokunulmaz")
        #expect(manualPlan.sortedEntries.count == 3, "Elle girilen taksit planı kalır")
        #expect(try f.context.fetch(FetchDescriptor<InstallmentPlan>()).count == 1)
        #expect(!entries.contains { $0.source == .imported && $0.account === card })
        #expect(!entries.contains { $0.kind == .transfer })
        #expect(try f.context.fetch(FetchDescriptor<MerchantRule>()).isEmpty)
        #expect(try importer.importedRecords(for: card).isEmpty)

        let again = try importer.prepare(try parse(statement), account: card)
        #expect(again.map(\.status) == [.possibleDuplicate, .new, .new, .newInstallmentPlan, .payment])
    }

    @Test("Öğrenilenler istenirse korunur")
    func keepsLearned() throws {
        let card = f.makeCard(), clothes = f.makeCategory("Giyim")
        let importer = ImportService(context: f.context)
        var candidates = try importer.prepare(try parse(statement), account: card)
        ImportCandidate.applyCategory(clothes, at: 1, in: &candidates)
        try importer.commit(candidates, account: card)
        try importer.removeImported(for: card, forgetLearned: false)
        #expect(try f.context.fetch(FetchDescriptor<MerchantRule>()).count == 1)
    }

    @Test("Önceki sürümde ekstreden oluşturulmuş taksit planı da tanınır")
    func legacyImportedPlan() throws {
        let card = f.makeCard()
        let service = LedgerService(context: f.context)
        // Eski içe aktarım: plan işaretsiz, yalnızca ekstredeki taksitte satırın parmak izi var.
        let plan = try service.addInstallmentPurchase(total: tl(3_000), count: 6, purchaseDate: d(2026, 9, 6),
                                                      category: nil, account: card, merchant: "VATAN BILGISAYAR")
        let line = try #require(plan.sortedEntries.first { $0.installmentIndex == 2 })
        line.importHash = StatementParser.importHash(date: line.date, amount: line.amount, description: "VATAN BILGISAYAR")
        // Elle girilip ekstreyle eşleşmiş plan: parmak izi ekstre açıklamasından, plan adı kullanıcınınki.
        let manual = try service.addInstallmentPurchase(total: tl(900), count: 3, purchaseDate: d(2026, 8, 1),
                                                        category: nil, account: card, merchant: "Teknosa")
        manual.sortedEntries[1].importHash = StatementParser.importHash(date: d(2026, 9, 2), amount: tl(300),
                                                                        description: "TEKNOSA ISTANBUL")

        #expect(try ImportService(context: f.context).importedRecords(for: card).plans == 1)
        try ImportService(context: f.context).removeImported(for: card, forgetLearned: false)
        let plans = try f.context.fetch(FetchDescriptor<InstallmentPlan>())
        #expect(plans.count == 1 && plans[0] === manual)
        #expect(manual.sortedEntries.allSatisfy { $0.importHash == nil })
    }
}
