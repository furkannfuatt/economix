import Foundation
import EcoomixCore

/// Modelden dönen yapılandırılmış tasarruf analizi.
nonisolated struct AIAdvice: Codable, Equatable {
    struct Item: Codable, Equatable, Hashable {
        let title: String
        let detail: String
        let category: String
        let estimatedMonthlySaving: Double
        let priority: String
    }

    let summary: String
    let insights: [Item]
    let nextMonthPlan: [String]
}

nonisolated enum AIAdvisorError: LocalizedError, Equatable {
    case invalidKey, rateLimited, overloaded, blocked, truncated
    case badResponse(String)
    case network(String)

    var errorDescription: String? {
        switch self {
        case .invalidKey: "Gemini API anahtarı geçersiz ya da yetkisiz. Ayarlar > Yapay zekâ bölümünden kontrol et."
        case .rateLimited: "Gemini kotası doldu ya da çok sık istek gönderildi. Biraz sonra tekrar dene."
        case .overloaded: "Gemini şu an yoğun. Birkaç dakika sonra tekrar dene."
        case .blocked: "Gemini bu isteği güvenlik filtresi nedeniyle yanıtlamadı."
        case .truncated: "Yanıt yarıda kesildi. Tekrar dene."
        case .badResponse(let detail): "Beklenmeyen yanıt: \(detail)"
        case .network(let detail): "Bağlantı hatası: \(detail)"
        }
    }
}

enum GeminiModel: String, CaseIterable, Identifiable {
    case flash = "gemini-3.8-flash"
    case argon = "gemini-4-argon"

    static let storageKey = "geminiModel"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .flash: "Gemini 3.8 Flash (hızlı, ekonomik)"
        case .argon: "Gemini 4 Argon (en güçlü)"
        }
    }
}

/// Anahtarın kaynağı: önce uygulamada girilen (Keychain), yoksa Config/Secrets.xcconfig'ten gömülen.
enum GeminiKeyProvider {
    static let infoKey = "GeminiAPIKey"
    private static let placeholders: Set<String> = ["BURAYA_ANAHTARINI_YAZ"]

    static func resolve(keychain: String?, bundled: String?) -> String? {
        func clean(_ value: String?) -> String? {
            guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty,
                  !value.hasPrefix("$("), !placeholders.contains(value) else { return nil }
            return value
        }
        return clean(keychain) ?? clean(bundled)
    }

    static var bundledKey: String? {
        resolve(keychain: nil, bundled: Bundle.main.object(forInfoDictionaryKey: infoKey) as? String)
    }

    static var current: String? {
        resolve(keychain: KeychainStore.read(KeychainStore.geminiKey), bundled: bundledKey)
    }
}

/// Google Gemini API (generateContent) istemcisi; doğrudan HTTP. JSON şemalı yanıt üretir.
struct GeminiClient {
    static let baseURL = "https://generativelanguage.googleapis.com/v1beta/models/"
    static let bundleIdentifier = "com.furkanfuat.ecoomix"

    let apiKey: String
    var model: String = GeminiModel.flash.rawValue
    var session: URLSession = .shared

    func makeRequest(system: String, user: String, schema: [String: Any], maxOutputTokens: Int) throws -> URLRequest {
        let body: [String: Any] = [
            "systemInstruction": ["parts": [["text": system]]],
            "contents": [["role": "user", "parts": [["text": user]]]],
            // responseFormat.text.mimeType biçimi canlı API'de 400 veriyor; bu biçim doğrulandı.
            "generationConfig": [
                "maxOutputTokens": maxOutputTokens,
                "responseMimeType": "application/json",
                "responseJsonSchema": schema,
            ],
        ]
        guard let url = URL(string: Self.baseURL + model + ":generateContent") else {
            throw AIAdvisorError.badResponse("geçersiz model adı")
        }
        var request = URLRequest(url: url, timeoutInterval: 180)
        request.httpMethod = "POST"
        // Anahtar URL yerine başlıkta taşınır (loglara düşmez).
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        // Google Cloud'da anahtarı yalnızca bu iOS uygulamasıyla sınırlamak için.
        request.setValue(Self.bundleIdentifier, forHTTPHeaderField: "X-Ios-Bundle-Identifier")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    func send(_ request: URLRequest) async throws -> (Data, Int) {
        do {
            let (data, response) = try await session.data(for: request)
            return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
        } catch {
            throw AIAdvisorError.network(error.localizedDescription)
        }
    }

    private struct Response: Decodable {
        struct Candidate: Decodable {
            struct Content: Decodable {
                struct Part: Decodable {
                    let text: String?
                    let thought: Bool?
                }
                let parts: [Part]?
            }
            let content: Content?
            let finishReason: String?
        }
        struct PromptFeedback: Decodable { let blockReason: String? }

        let candidates: [Candidate]?
        let promptFeedback: PromptFeedback?
    }

    private struct ErrorResponse: Decodable {
        struct Detail: Decodable {
            let message: String?
            let status: String?
        }
        let error: Detail
    }

    private static let blockingReasons: Set<String> = ["SAFETY", "RECITATION", "BLOCKLIST", "PROHIBITED_CONTENT",
                                                       "SPII", "LANGUAGE", "IMAGE_SAFETY"]

    /// HTTP durumunu, engelleme/kesilme nedenlerini kontrol edip metin parçasındaki JSON'u çözer.
    static func decode<T: Decodable>(_ type: T.Type, data: Data, statusCode: Int) throws -> T {
        guard statusCode == 200 else {
            let message = (try? JSONDecoder().decode(ErrorResponse.self, from: data))?.error.message
            let raw = String(decoding: data, as: UTF8.self)
            switch statusCode {
            case 400 where raw.contains("API_KEY_INVALID") || raw.localizedCaseInsensitiveContains("API key not valid"):
                throw AIAdvisorError.invalidKey
            case 401, 403: throw AIAdvisorError.invalidKey
            case 429: throw AIAdvisorError.rateLimited
            case 500...599: throw AIAdvisorError.overloaded
            default: throw AIAdvisorError.badResponse(message ?? "HTTP \(statusCode)")
            }
        }

        let response: Response
        do {
            response = try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw AIAdvisorError.badResponse("yanıt çözülemedi")
        }
        if response.promptFeedback?.blockReason != nil { throw AIAdvisorError.blocked }
        guard let candidate = response.candidates?.first else { throw AIAdvisorError.badResponse("yanıt boş") }

        // İçeriği okumadan önce durma sebebi kontrol edilir.
        if let reason = candidate.finishReason {
            if reason == "MAX_TOKENS" { throw AIAdvisorError.truncated }
            if blockingReasons.contains(reason) { throw AIAdvisorError.blocked }
        }

        let text = (candidate.content?.parts ?? [])
            .filter { $0.thought != true }
            .compactMap(\.text)
            .joined()
        do {
            return try JSONDecoder().decode(T.self, from: Data(stripCodeFence(text).utf8))
        } catch {
            throw AIAdvisorError.badResponse("yanıt biçimi hatalı")
        }
    }

    /// Model JSON'u ```json … ``` içine sararsa ayıklar.
    private static func stripCodeFence(_ text: String) -> String {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("```") else { return trimmed }
        if let newline = trimmed.firstIndex(of: "\n") { trimmed = String(trimmed[trimmed.index(after: newline)...]) }
        if trimmed.hasSuffix("```") { trimmed = String(trimmed.dropLast(3)) }
        return trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Son 6 ayın özetinden kişisel tasarruf önerileri.
struct GeminiAdvisor {
    let apiKey: String
    var model: String = GeminiModel.flash.rawValue
    var session: URLSession = .shared

    private var client: GeminiClient { GeminiClient(apiKey: apiKey, model: model, session: session) }

    static let systemPrompt = """
    Sen Türkiye'de yaşayan bir kullanıcının kişisel finans danışmanısın. Para birimi TL. \
    Sana kullanıcının son 6 ayının özetini JSON olarak veriyorum: aylık gelir/gider, kategori bazında aylık harcamalar \
    ve bütçeler, abonelikler, önümüzdeki aylardaki kredi kartı taksit yükü ve uygulamanın kural tabanlı bulguları. \
    Aylar her ayın monthStartDay gününde başlar (1 ise takvim ayı; ör. 23 ise "2026-11" 23 Ekim–22 Kasım dönemidir). Son ay kısmidir; currentMonthDay dönemin kaçıncı gününde olduğumuzu gösterir. investment yatırıma ayrılan paradır; gider değildir ve tasarruf oranına dahil edilmez.

    Bu verilere dayanarak somut ve uygulanabilir tasarruf önerileri üret. Her öneri verideki bir rakama dayansın; \
    veride olmayan rakam uydurma. Tahmini aylık tasarrufu TL olarak gerçekçi ver. Kural tabanlı bulguları tekrar etme; \
    onların ötesine geç (örüntüler, mevsimsellik, taksit planlaması, abonelik önceliklendirme gibi). \
    3 ile 6 arası öneri yaz, önem sırasına göre diz. nextMonthPlan, gelecek ay için 3–5 kısa adım olsun. \
    Tüm metinler Türkçe, samimi ve kısa olsun. Yalnızca istenen JSON'u döndür.
    """

    static let responseSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "summary": ["type": "string", "description": "2-3 cümlelik genel değerlendirme"],
            "insights": [
                "type": "array",
                "items": [
                    "type": "object",
                    "properties": [
                        "title": ["type": "string"],
                        "detail": ["type": "string"],
                        "category": ["type": "string", "description": "İlgili kategori adı ya da boş"],
                        "estimatedMonthlySaving": ["type": "number"],
                        "priority": ["type": "string", "enum": ["high", "medium", "low"]],
                    ],
                    "required": ["title", "detail", "category", "estimatedMonthlySaving", "priority"],
                    "additionalProperties": false,
                ],
            ],
            "nextMonthPlan": ["type": "array", "items": ["type": "string"]],
        ],
        "required": ["summary", "insights", "nextMonthPlan"],
        "additionalProperties": false,
    ]

    func makeRequest(payload: AIPayload) throws -> URLRequest {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let payloadJSON = String(decoding: try encoder.encode(payload), as: UTF8.self)
        return try client.makeRequest(system: Self.systemPrompt, user: payloadJSON, schema: Self.responseSchema,
                                      maxOutputTokens: 16_384)
    }

    static func parse(data: Data, statusCode: Int) throws -> AIAdvice {
        try GeminiClient.decode(AIAdvice.self, data: data, statusCode: statusCode)
    }

    func analyze(payload: AIPayload) async throws -> AIAdvice {
        let (data, status) = try await client.send(try makeRequest(payload: payload))
        return try Self.parse(data: data, statusCode: status)
    }
}

/// Ekstredeki işyeri adlarını kullanıcının kategorilerinden birine atar. Yalnızca işyeri ve kategori adları gönderilir.
struct GeminiCategorizer {
    let apiKey: String
    var model: String = GeminiModel.flash.rawValue
    var session: URLSession = .shared

    private var client: GeminiClient { GeminiClient(apiKey: apiKey, model: model, session: session) }

    static let systemPrompt = """
    Türkiye'deki bir banka ya da kredi kartı ekstresinden gelen işyeri açıklamalarını kullanıcının kategorilerinden \
    birine ata. Açıklamalar büyük harfli, kısaltılmış olabilir; şube, şehir ya da ödeme aracısı (IYZICO, PAYTR gibi) \
    içerebilir. Yalnızca verilen kategori adlarından birini kullan. Emin değilsen category alanını boş bırak. \
    Her işyeri için, verilen yazımıyla bir öğe döndür.
    """

    private struct Input: Encodable {
        let categories: [String]
        let merchants: [String]
    }

    private struct Output: Decodable {
        struct Item: Decodable {
            let merchant: String
            let category: String
        }
        let items: [Item]
    }

    func makeRequest(merchants: [String], categoryNames: [String]) throws -> URLRequest {
        var seen = Set<String>()
        let unique = merchants.filter { seen.insert($0).inserted }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        let user = String(decoding: try encoder.encode(Input(categories: categoryNames, merchants: unique)), as: UTF8.self)
        let schema: [String: Any] = [
            "type": "object",
            "properties": [
                "items": [
                    "type": "array",
                    "items": [
                        "type": "object",
                        "properties": [
                            "merchant": ["type": "string"],
                            "category": ["type": "string", "enum": categoryNames + [""]],
                        ],
                        "required": ["merchant", "category"],
                        "additionalProperties": false,
                    ],
                ],
            ],
            "required": ["items"],
            "additionalProperties": false,
        ]
        return try client.makeRequest(system: Self.systemPrompt, user: user, schema: schema, maxOutputTokens: 8_192)
    }

    /// İşyeri açıklaması → kategori. Boş ya da bilinmeyen kategori adları atlanır.
    static func mapping(from data: Data, statusCode: Int, categories: [EntryCategory]) throws -> [String: EntryCategory] {
        let output = try GeminiClient.decode(Output.self, data: data, statusCode: statusCode)
        var result: [String: EntryCategory] = [:]
        for item in output.items {
            if let category = categories.first(where: { $0.name == item.category }) { result[item.merchant] = category }
        }
        return result
    }

    func categorize(merchants: [String], categories: [EntryCategory]) async throws -> [String: EntryCategory] {
        let request = try makeRequest(merchants: merchants, categoryNames: categories.map(\.name))
        let (data, status) = try await client.send(request)
        return try Self.mapping(from: data, statusCode: status, categories: categories)
    }
}
