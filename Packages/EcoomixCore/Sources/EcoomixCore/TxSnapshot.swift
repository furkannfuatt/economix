import Foundation

public enum TxKind: String, CaseIterable, Sendable, Codable {
    case expense, income, transfer

    public var title: String {
        switch self {
        case .expense: "Gider"
        case .income: "Gelir"
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
