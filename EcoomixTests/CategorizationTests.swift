import Foundation
import SwiftData
import Testing
import EcoomixCore
@testable import Ecoomix

private func d(_ y: Int, _ m: Int, _ day: Int) -> Date {
    FinanceCalendar.calendar.date(from: DateComponents(year: y, month: m, day: day))!
}

@Suite("Kategori belirleme")
@MainActor
struct CategorizationTests {
    let f = Fixture()

    func parse(_ rows: [[String]]) throws -> StatementParseResult {
        try StatementParser.parse(rows: [["Tarih", "Açıklama", "Tutar"]] + rows, profile: .generic)
    }

    @Test("Öğrenilen kategori aynı markanın başka şubesine de uygulanır")
    func learnedByBrand() throws {
        let market = f.makeCategory("Market")
        let service = LedgerService(context: f.context)
        try service.learnCategory(merchant: "MIGROS KADIKOY", category: market)
        #expect(service.learnedCategory(for: "MIGROS SANAL MARKET ISTANBUL TR") === market)
        #expect(service.learnedCategory(for: "IYZICO/MIGROS") === market)
        #expect(service.learnedCategory(for: "A101") == nil)
    }

    @Test("Önizlemede seçilen kategori aynı markanın kategorisiz satırlarına da uygulanır")
    func applyToSameBrand() throws {
        let card = f.makeCard()
        let food = f.makeCategory("Yemek"), other = f.makeCategory("Diğer")
        let result = try parse([["01.10.2026", "AYSE TEYZE EV YEMEKLERI KADIKOY", "120,00"],
                                ["05.10.2026", "AYSE TEYZE EV YEMEKLERI MODA", "140,00"],
                                ["06.10.2026", "BASKA BIR YER", "50,00"],
                                ["07.10.2026", "AYSE TEYZE EV YEMEKLERI", "90,00"]])
        var candidates = try ImportService(context: f.context).prepare(result, account: card)
        candidates[3].category = other
        let updated = ImportCandidate.applyCategory(food, at: 0, in: &candidates)
        #expect(updated == 1)
        #expect(candidates[0].category === food)
        #expect(candidates[1].category === food)
        #expect(candidates[2].category == nil)
        #expect(candidates[3].category === other, "Elle seçilmiş başka kategori ezilmez")
    }

    @Test("Gemini isteği yalnızca benzersiz işyeri adlarını ve kategori adlarını içerir")
    func categorizerRequest() throws {
        let request = try GeminiCategorizer(apiKey: "AIza-test")
            .makeRequest(merchants: ["MIGROS", "MIGROS", "AYSE TEYZE EV YEMEKLERI"], categoryNames: ["Market", "Yemek & Kafe"])
        #expect(request.value(forHTTPHeaderField: "x-goog-api-key") == "AIza-test")
        let body = try #require(JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any])
        let text = try #require(((body["contents"] as? [[String: Any]])?.first?["parts"] as? [[String: Any]])?.first?["text"] as? String)
        #expect(text.components(separatedBy: "MIGROS").count - 1 == 1)
        #expect(text.contains("Yemek & Kafe"))
        #expect(!text.contains("120"), "Tutar gönderilmez")
        let config = try #require(body["generationConfig"] as? [String: Any])
        let schema = try #require(config["responseJsonSchema"] as? [String: Any])
        let items = try #require((schema["properties"] as? [String: Any])?["items"] as? [String: Any])
        let item = try #require(items["items"] as? [String: Any])
        let category = try #require((item["properties"] as? [String: Any])?["category"] as? [String: Any])
        #expect(category["enum"] as? [String] == ["Market", "Yemek & Kafe", ""])
    }

    @Test("Gemini yanıtı kategori nesnelerine çevrilir; bilinmeyen ve boş atlanır")
    func categorizerParse() throws {
        let market = f.makeCategory("Market"), food = f.makeCategory("Yemek & Kafe")
        let json = #"{"items":[{"merchant":"MIGROS","category":"Market"},{"merchant":"AYSE TEYZE","category":"Yemek & Kafe"},{"merchant":"XYZ","category":""},{"merchant":"QQQ","category":"Uydurma"}]}"#
        let data = try JSONSerialization.data(withJSONObject: [
            "candidates": [["content": ["parts": [["text": json]]], "finishReason": "STOP"]],
        ])
        let mapping = try GeminiCategorizer.mapping(from: data, statusCode: 200, categories: [market, food])
        #expect(mapping.count == 2)
        #expect(mapping["MIGROS"] === market)
        #expect(mapping["AYSE TEYZE"] === food)
    }
}
