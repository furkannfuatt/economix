import Foundation

public enum TxKind: String, CaseIterable, Sendable, Codable {
    /// Yatırım: gider sayılmaz (bütçe, net ve tasarruf oranına girmez), ayrı toplanır; harcandığı kartın borcuna eklenir.
    case expense, income, investment, transfer

    public var title: String {
        switch self {
        case .expense: "Gider"
        case .income: "Gelir"
        case .investment: "Yatırım"
        case .transfer: "Transfer"
        }
    }
}

/// Bir işlemin taksit planına bağlantısı.
public struct InstallmentRef: Hashable, Sendable {
    public let planID: String
    public let purchaseDate: Date
    public let planTotal: Money

    public init(planID: String, purchaseDate: Date, planTotal: Money) {
        self.planID = planID
        self.purchaseDate = purchaseDate
        self.planTotal = planTotal
    }
}

/// Hesaplamalar için SwiftData'dan bağımsız işlem görüntüsü.
public struct TxSnapshot: Hashable, Sendable {
    public var id: String
    /// Her zaman pozitif; yönü `kind` belirler.
    public var amount: Money
    public var kind: TxKind
    public var date: Date
    public var categoryID: String?
    public var accountID: String?
    /// Transferlerde hedef hesap (ör. kart borcu ödemesinde kart).
    public var toAccountID: String?
    public var merchant: String
    public var installment: InstallmentRef?
    public var isSubscription: Bool

    public init(id: String, amount: Money, kind: TxKind, date: Date, categoryID: String?, accountID: String?,
                toAccountID: String? = nil, merchant: String, installment: InstallmentRef? = nil,
                isSubscription: Bool = false) {
        self.id = id
        self.amount = amount
        self.kind = kind
        self.date = date
        self.categoryID = categoryID
        self.accountID = accountID
        self.toAccountID = toAccountID
        self.merchant = merchant
        self.installment = installment
        self.isSubscription = isSubscription
    }
}

public enum MerchantNormalizer {
    /// Ödeme aracısı önekleri ("IYZICO/TRENDYOL", "PAYPAL *STEAM").
    static let paymentProcessors: Set<String> = ["IYZICO", "IYZ", "PAYTR", "PAYPAL", "PARAM", "SIPAY", "CRAFTGATE", "PAPARA"]
    /// Marka sayılmayan ekler: şirket türü, şube/mağaza, şehir, alan adı.
    static let noiseWords: Set<String> = [
        "TR", "TUR", "TURKEY", "TURKIYE", "ISTANBUL", "ANKARA", "IZMIR", "BURSA", "ANTALYA", "KOCAELI", "ADANA",
        "KADIKOY", "BESIKTAS", "SISLI", "USKUDAR", "ATASEHIR", "MALTEPE", "BAKIRKOY",
        "A", "S", "AS", "LTD", "STI", "SIRKETI", "SAN", "TIC", "VE", "COM", "WWW", "NET", "ONLINE", "INTERNET",
        "SANAL", "POS", "SUBE", "SUBESI", "MAGAZA", "MAGAZASI", "MAGAZALARI", "MAGAZACILIK", "MARKETLER",
    ]

    /// İşyerinin marka anahtarı: "MIGROS SANAL MARKET ISTANBUL TR" → "MIGROS", "PAYTR*ABC TEKSTIL LTD STI" → "ABC TEKSTIL".
    /// Kısa (≤3 harf) ilk kelimeye bir sonraki kelime eklenir.
    public static func brandKey(_ text: String) -> String {
        var words = normalize(text).split(separator: " ").map(String.init)
        while let first = words.first, paymentProcessors.contains(first) { words.removeFirst() }
        words.removeAll { noiseWords.contains($0) }
        guard let first = words.first else { return "" }
        if first.count <= 3, words.count > 1 { return first + " " + words[1] }
        return first
    }

    /// "Migros  Kadıköy 34" → "MIGROS KADIKOY". Türkçe karakterler katlanır, yalnızca rakamdan oluşan parçalar atılır.
    public static func normalize(_ text: String) -> String {
        let folded = text
            .folding(options: .diacriticInsensitive, locale: nil)
            .uppercased(with: Locale(identifier: "en_US_POSIX"))
        let cleaned = String(folded.map { $0.isLetter || $0.isNumber ? $0 : " " })
        return cleaned
            .split(separator: " ")
            .filter { !$0.allSatisfy(\.isNumber) }
            .joined(separator: " ")
    }
}
