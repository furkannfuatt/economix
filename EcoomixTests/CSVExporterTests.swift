import Foundation
import Testing
import EcoomixCore
@testable import Ecoomix

@Suite("CSVExporter")
@MainActor
struct CSVExporterTests {
    @Test("Excel uyumlu: BOM, noktalı virgül, Türkçe tutar; içe aktarıcıyla geri okunur")
    func roundTrip() throws {
        let f = Fixture()
        let card = f.makeCard()
        let category = f.makeCategory("Market")
        let date = FinanceCalendar.calendar.date(from: DateComponents(year: 2026, month: 10, day: 2))!
        try LedgerService(context: f.context).addEntry(amount: Money(minor: 1_234_56), kind: .expense, date: date,
                                                       category: category, account: card, merchant: "Migros; Kadıköy",
                                                       note: "haftalık \"büyük\" alışveriş")
        let csv = CSVExporter.csv(for: try f.context.fetch(.init()))
        #expect(csv.hasPrefix("\u{FEFF}Tarih;Tür;Tutar;Kategori;Hesap;Hedef hesap;İşyeri;Not;Taksit;Kaynak"))

        let rows = CSVReader.rows(from: csv)
        #expect(rows.count == 2)
        #expect(rows[1] == ["02.10.2026", "Gider", "-1234,56", "Market", "Bonus", "", "Migros; Kadıköy",
                            "haftalık \"büyük\" alışveriş", "", "Elle"])
        let parsed = try StatementParser.parse(rows: rows, profile: .generic,
                                               columns: (headerIndex: 0, map: ColumnMap(date: 0, description: 6, amount: 2)))
        #expect(parsed.rows.first?.amount == Money(minor: 1_234_56))
    }
}
