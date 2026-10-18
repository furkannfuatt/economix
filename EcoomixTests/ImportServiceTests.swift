import Foundation
import SwiftData
import Testing
import EcoomixCore
@testable import Ecoomix

private func d(_ y: Int, _ m: Int, _ day: Int) -> Date {
    FinanceCalendar.calendar.date(from: DateComponents(year: y, month: m, day: day))!
}

private func tl(_ lira: Int) -> Money { Money(minor: lira * 100) }

@Suite("ImportService")
@MainActor
struct ImportServiceTests {
    let f = Fixture()

    func parse(_ rows: [[String]]) throws -> StatementParseResult {
        try StatementParser.parse(rows: [["Tarih", "Açıklama", "Tutar"]] + rows, profile: .generic)
    }

    func seededMarket() -> EntryCategory {
        let market = EntryCategory(name: "Market", icon: "cart", colorHex: "#000", kind: .expense, seedKey: "market")
        f.context.insert(market)
        return market
    }

    @Test("Yeni satırlar dahil edilir, bilinen işyeri kategorisi önerilir")
    func newRows() throws {
        let card = f.makeCard(), market = seededMarket()
        let result = try parse([["01.10.2026", "MIGROS KADIKOY", "250,00"]])
        let candidates = try ImportService(context: f.context).prepare(result, account: card)
        #expect(candidates.count == 1)
        #expect(candidates[0].status == .new)
        #expect(candidates[0].include)
        #expect(candidates[0].category === market)
    }

    @Test("Öğrenilmiş kural yerleşik sözlükten önce gelir")
    func learnedRuleWins() throws {
        let card = f.makeCard(), _ = seededMarket(), food = f.makeCategory("Yemek")
        try LedgerService(context: f.context).learnCategory(merchant: "MIGROS KADIKOY", category: food)
        let result = try parse([["01.10.2026", "MIGROS KADIKOY", "250,00"]])
        #expect(try ImportService(context: f.context).prepare(result, account: card)[0].category === food)
    }

    @Test("Aynı dosya ikinci kez aktarılırsa satırlar 'zaten var' olur")
    func exactDuplicate() throws {
        let card = f.makeCard()
        let service = ImportService(context: f.context)
        let result = try parse([["01.10.2026", "MIGROS", "250,00"], ["02.10.2026", "A101", "80,00"]])
        let summary = try service.commit(try service.prepare(result, account: card), account: card)
        #expect(summary.added == 2)
        let again = try service.prepare(result, account: card)
        #expect(again.allSatisfy { $0.status == .duplicate && !$0.include })
    }

    @Test("Elle girilmiş benzer işlem muhtemel tekrar olarak işaretlenir")
    func fuzzyDuplicate() throws {
        let card = f.makeCard()
        try LedgerService(context: f.context).addEntry(amount: tl(250), kind: .expense, date: d(2026, 9, 30),
                                                       category: nil, account: card, merchant: "Migros")
        let result = try parse([["01.10.2026", "MIGROS SANAL MARKET", "250,00"]])
        let candidate = try ImportService(context: f.context).prepare(result, account: card)[0]
        #expect(candidate.status == .possibleDuplicate)
        #expect(!candidate.include)
    }

    @Test("Taksit satırı mevcut plana eşlenir")
    func knownInstallment() throws {
        let card = f.makeCard()
        try LedgerService(context: f.context).addInstallmentPurchase(total: tl(12_000), count: 6, purchaseDate: d(2026, 8, 3),
                                                                     category: nil, account: card, merchant: "TEKNOSA")
        let result = try parse([["03.10.2026", "TEKNOSA TAKSIT 3/6", "2.000,00"]])
        let candidate = try ImportService(context: f.context).prepare(result, account: card)[0]
        #expect(candidate.status == .installmentKnown)
        #expect(!candidate.include)
    }

    @Test("Bilinmeyen taksit için alım tarihi geriye hesaplanan plan oluşturulur")
    func createsPlan() throws {
        let card = f.makeCard()
        let service = ImportService(context: f.context)
        let result = try parse([["03.10.2026", "VATAN BILGISAYAR TAKSIT 3/6", "2.000,00"]])
        let candidates = try service.prepare(result, account: card)
        #expect(candidates[0].status == .newInstallmentPlan)
        let summary = try service.commit(candidates, account: card)
        #expect(summary.plansCreated == 1)

        let plan = try #require(try f.context.fetch(FetchDescriptor<InstallmentPlan>()).first)
        #expect(plan.total == tl(12_000))
        #expect(plan.count == 6)
        #expect(plan.purchaseDate == d(2026, 8, 3))
        #expect(plan.account === card)
        let third = plan.sortedEntries[2]
        #expect(third.date == d(2026, 10, 3))
        #expect(third.importHash == result.rows[0].importHash)
        // Sonraki ayın ekstresi aynı planı tanır
        let next = try parse([["03.11.2026", "VATAN BILGISAYAR TAKSIT 4/6", "2.000,00"]])
        #expect(try service.prepare(next, account: card)[0].status == .installmentKnown)
    }

    @Test("Karta ödeme varsayılan olarak dışarıda, iade gelir olarak dahil")
    func paymentsAndRefunds() throws {
        let card = f.makeCard()
        let result = try parse([["01.10.2026", "MIGROS", "300,00"],
                                ["05.10.2026", "ODEMENIZ ICIN TESEKKURLER", "-5.000,00"],
                                ["07.10.2026", "ZARA IADE", "-299,90"]])
        let service = ImportService(context: f.context)
        let candidates = try service.prepare(result, account: card)
        #expect(candidates[1].status == .payment && !candidates[1].include)
        #expect(candidates[2].include)
        try service.commit(candidates, account: card)
        let refund = try #require(try f.context.fetch(FetchDescriptor<LedgerEntry>()).first { $0.amountMinor == 299_90 })
        #expect(refund.kind == .income)
        #expect(refund.source == .imported)
    }

    @Test("Ödül, bonus ve chip-para alacakları karta ödeme gibi varsayılan olarak dışarıda")
    func rewardsExcluded() throws {
        let card = f.makeCard()
        let result = try parse([["01.10.2026", "MIGROS", "300,00"],
                                ["02.10.2026", "ILK HARCAMANIZA 100 TL ODUL", "-100,00"],
                                ["03.10.2026", "MIGROS -Kullanilan chip-para", "-25,00"]])
        let service = ImportService(context: f.context)
        var candidates = try service.prepare(result, account: card)
        #expect(candidates[1].status == .reward && !candidates[1].include)
        #expect(candidates[2].status == .reward && !candidates[2].include)
        candidates[1].include = true
        try service.commit(candidates, account: card)
        let reward = try #require(try f.context.fetch(FetchDescriptor<LedgerEntry>()).first { $0.amountMinor == 100_00 })
        #expect(reward.kind == .income, "Açılırsa gelir olarak eklenir")
        #expect(try f.context.fetch(FetchDescriptor<LedgerEntry>()).count == 2)
    }

    @Test("Yalnızca kullanıcının ya da Gemini'nin seçtiği kategori öğrenilir; sözlük önerisi öğrenilmez")
    func learnsOnlyChosenCategories() throws {
        let card = f.makeCard(), market = seededMarket(), other = f.makeCategory("Diğer")
        let result = try parse([["01.10.2026", "MIGROS KADIKOY", "250,00"],
                                ["02.10.2026", "AYSE TEYZE EV YEMEKLERI", "120,00"]])
        let service = ImportService(context: f.context)
        var candidates = try service.prepare(result, account: card)
        #expect(candidates[0].category === market)
        ImportCandidate.applyCategory(other, at: 1, in: &candidates)
        try service.commit(candidates, account: card)
        let rules = try f.context.fetch(FetchDescriptor<MerchantRule>())
        #expect(rules.map(\.pattern) == ["AYSE TEYZE EV YEMEKLERI"])
    }
}

