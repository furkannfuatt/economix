import Foundation
import Testing
@testable import EconomixCore

@Suite("XLSX okuma")
struct XLSXReaderTests {
    func fixture() throws -> Data {
        let url = try #require(Bundle.module.url(forResource: "axess-ekstre", withExtension: "xlsx", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    @Test("Boş satır ve atlanan hücreler kolon hizası korunarak okunur")
    func readsRows() throws {
        let rows = try XLSXReader.rows(from: fixture())
        #expect(rows[0] == ["Akbank Axess Kart Ekstresi"])
        #expect(rows[1] == [])
        #expect(rows[2] == ["Tarih", "Açıklama", "Tutar"])
        #expect(rows[3] == ["46296", "MIGROS KADIKOY", "1234.56"])
        #expect(rows[4] == ["02.10.2026", "", "99.9"])
    }

    @Test("Okunan satırlar ekstre çözümleyiciden geçer")
    func parses() throws {
        let rows = try XLSXReader.rows(from: fixture())
        #expect(BankProfile.detect(fileName: "ekstre.xlsx", rows: rows).id == "akbank")
        let result = try StatementParser.parse(rows: rows, profile: .akbank)
        #expect(result.rows.map(\.amount) == [Money(minor: 123_456), Money(minor: 9_990), tl(2_000)])
        #expect(result.rows[0].date == d(2026, 10, 1))
        #expect(result.rows[2].installment == InstallmentMarker(current: 2, total: 6))
    }

    @Test("Kolon harfleri: en fazla 3 büyük harf (Excel'in son kolonu XFD)", arguments: [
        ("A", 0), ("C", 2), ("Z", 25), ("AA", 26), ("XFD", 16_383),
    ])
    func columnLetters(letters: String, index: Int) {
        #expect(XLSXReader.columnIndex(letters) == index)
    }

    @Test("Geçersiz ya da aşırı uzun kolon harfi reddedilir", arguments: ["", "a", "A1", "ABCD", "ZZZZZZZZZZZZZZZZ"])
    func rejectsColumnLetters(letters: String) {
        #expect(XLSXReader.columnIndex(letters) == nil)
    }

    @Test("Satır numarası 1 ile sınır arasında olmalı")
    func rowNumbers() {
        #expect(XLSXReader.rowIndex(1) == 0)
        #expect(XLSXReader.rowIndex(UInt(ImportLimits.maxRows)) == ImportLimits.maxRows - 1)
        #expect(XLSXReader.rowIndex(0) == nil)
        #expect(XLSXReader.rowIndex(UInt(ImportLimits.maxRows) + 1) == nil)
        #expect(XLSXReader.rowIndex(.max) == nil)
    }

    @Test("XLSX olmayan veri hata verir")
    func rejectsGarbage() {
        #expect(throws: (any Error).self) { try XLSXReader.rows(from: Data("merhaba".utf8)) }
    }
}
