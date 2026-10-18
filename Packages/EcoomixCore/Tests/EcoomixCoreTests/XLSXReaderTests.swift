import Foundation
import Testing
@testable import EcoomixCore

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

    @Test("XLSX olmayan veri hata verir")
    func rejectsGarbage() {
        #expect(throws: (any Error).self) { try XLSXReader.rows(from: Data("merhaba".utf8)) }
    }
}
