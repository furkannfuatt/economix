import Foundation
import Testing
import EcoomixCore
@testable import Ecoomix

@Suite("GeminiAdvisor")
@MainActor
struct GeminiAdvisorTests {
    let payload = AIPayloadBuilder.build(
        from: AnalysisInput(transactions: [], asOf: .now, budgets: [:], categoryNames: [:], subscriptions: [],
                            installmentPlans: []),
        insights: [], includeMerchants: false)

    @Test("İstek: model uç noktası, anahtar başlığı, iOS paket başlığı, JSON şemalı çıktı")
    func request() throws {
        let request = try GeminiAdvisor(apiKey: "AIza-test", model: "gemini-3.8-flash").makeRequest(payload: payload)
        #expect(request.url?.absoluteString
                == "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.8-flash:generateContent")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "x-goog-api-key") == "AIza-test")
        #expect(request.value(forHTTPHeaderField: "X-Ios-Bundle-Identifier") == "com.furkanfuat.ecoomix")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.url?.query == nil, "Anahtar URL'de taşınmamalı")

        let body = try #require(JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any])
        let system = try #require(body["systemInstruction"] as? [String: Any])
        #expect(((system["parts"] as? [[String: Any]])?.first?["text"] as? String)?.isEmpty == false)
        let contents = try #require(body["contents"] as? [[String: Any]])
        #expect(contents.first?["role"] as? String == "user")
        let text = (contents.first?["parts"] as? [[String: Any]])?.first?["text"] as? String
        #expect(text?.contains("\"currency\":\"TRY\"") == true)

        // Canlı API'de doğrulanan biçim: responseFormat.text.mimeType 400 veriyor.
        let config = try #require(body["generationConfig"] as? [String: Any])
        #expect(config["responseFormat"] == nil)
        #expect(config["responseMimeType"] as? String == "application/json")
        let schema = try #require(config["responseJsonSchema"] as? [String: Any])
        #expect(schema["additionalProperties"] as? Bool == false)
    }

    private func response(_ parts: [[String: Any]], finish: String = "STOP") -> Data {
        let json: [String: Any] = [
            "candidates": [["content": ["role": "model", "parts": parts], "finishReason": finish]],
            "modelVersion": "gemini-3.8-flash",
        ]
        return try! JSONSerialization.data(withJSONObject: json)
    }

    private let adviceJSON = """
    {"summary":"Genel durum iyi.","insights":[{"title":"Yemek","detail":"Azalt","category":"Yemek & Kafe",\
    "estimatedMonthlySaving":1500,"priority":"high"}],"nextMonthPlan":["Market listesi yap"]}
    """

    @Test("Yanıt: düşünce parçası atlanır, metindeki JSON çözülür")
    func parses() throws {
        let data = response([["text": "plan yapıyorum", "thought": true], ["text": adviceJSON]])
        let advice = try GeminiAdvisor.parse(data: data, statusCode: 200)
        #expect(advice.summary == "Genel durum iyi.")
        #expect(advice.insights.first?.estimatedMonthlySaving == 1500)
        #expect(advice.nextMonthPlan == ["Market listesi yap"])
    }

    @Test("Kod bloğu içine sarılmış JSON da çözülür")
    func fencedJSON() throws {
        let advice = try GeminiAdvisor.parse(data: response([["text": "```json\n\(adviceJSON)\n```"]]), statusCode: 200)
        #expect(advice.summary == "Genel durum iyi.")
    }

    @Test("Engellenen istem ve güvenlik nedeniyle durma ayrı hata verir")
    func blocked() {
        let blockedPrompt = try! JSONSerialization.data(withJSONObject: ["promptFeedback": ["blockReason": "SAFETY"]])
        #expect(throws: AIAdvisorError.blocked) { try GeminiAdvisor.parse(data: blockedPrompt, statusCode: 200) }
        #expect(throws: AIAdvisorError.blocked) {
            try GeminiAdvisor.parse(data: response([["text": ""]], finish: "SAFETY"), statusCode: 200)
        }
    }

    @Test("Kesilen yanıt ayrı hata verir")
    func truncated() {
        #expect(throws: AIAdvisorError.truncated) {
            try GeminiAdvisor.parse(data: response([["text": "{\"summary\":"]], finish: "MAX_TOKENS"), statusCode: 200)
        }
    }

    @Test("HTTP durumları anlamlı hatalara çevrilir")
    func statusCodes() {
        let invalidKey = Data(#"{"error":{"code":400,"message":"API key not valid.","status":"INVALID_ARGUMENT","details":[{"reason":"API_KEY_INVALID"}]}}"#.utf8)
        #expect(throws: AIAdvisorError.invalidKey) { try GeminiAdvisor.parse(data: invalidKey, statusCode: 400) }
        let generic = Data(#"{"error":{"code":403,"message":"denied","status":"PERMISSION_DENIED"}}"#.utf8)
        #expect(throws: AIAdvisorError.invalidKey) { try GeminiAdvisor.parse(data: generic, statusCode: 403) }
        #expect(throws: AIAdvisorError.rateLimited) { try GeminiAdvisor.parse(data: generic, statusCode: 429) }
        #expect(throws: AIAdvisorError.overloaded) { try GeminiAdvisor.parse(data: generic, statusCode: 503) }
        let badRequest = Data(#"{"error":{"code":400,"message":"Invalid JSON payload","status":"INVALID_ARGUMENT"}}"#.utf8)
        #expect(throws: AIAdvisorError.badResponse("Invalid JSON payload")) {
            try GeminiAdvisor.parse(data: badRequest, statusCode: 400)
        }
    }
}

@Suite("GeminiKeyProvider")
@MainActor
struct GeminiKeyProviderTests {
    @Test("Anahtar uygulama paketine gömülmez; yalnızca Keychain'den okunur")
    func notBundled() {
        #expect(Bundle.main.object(forInfoDictionaryKey: "GeminiAPIKey") == nil)
    }

    @Test("Girilen anahtarın boşlukları temizlenir")
    func trims() {
        #expect(GeminiKeyProvider.normalized("  AIza-keychain \n") == "AIza-keychain")
    }

    @Test("Boş ya da şablon değer yok sayılır", arguments: ["", "  ", "$(GEMINI_API_KEY)", "BURAYA_ANAHTARINI_YAZ"])
    func ignoresPlaceholder(value: String) {
        #expect(GeminiKeyProvider.normalized(value) == nil)
    }
}
