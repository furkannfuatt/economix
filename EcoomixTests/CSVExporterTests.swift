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

    @Test("Formül gibi başlayan metin alanları Excel'de çalışmasın diye etkisizleştirilir; tutar olduğu gibi kalır")
    func neutralizesFormulas() throws {
        let f = Fixture()
        let card = f.makeCard()
        let category = f.makeCategory("@Kategori")
        try LedgerService(context: f.context).addEntry(amount: Money(minor: 50_00), kind: .expense, date: .now,
                                                       category: category, account: card,
                                                       merchant: "=HYPERLINK(\"http://ornek.test\";\"tıkla\")",
                                                       note: "+90 cmd")
        let rows = CSVReader.rows(from: CSVExporter.csv(for: try f.context.fetch(.init())))
        #expect(rows[1][2] == "-50,00")
        #expect(rows[1][3] == "'@Kategori")
        #expect(rows[1][6] == "'=HYPERLINK(\"http://ornek.test\";\"tıkla\")")
        #expect(rows[1][7] == "'+90 cmd")
    }

    @Test("Paylaşım için yazılan geçici dosya temizlenir")
    func removesTemporaryFile() throws {
        let f = Fixture()
        let url = try CSVExporter.writeTemporaryFile(for: try f.context.fetch(.init()))
        #expect(FileManager.default.fileExists(atPath: url.path))
        CSVExporter.removeTemporaryFiles()
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }
}
