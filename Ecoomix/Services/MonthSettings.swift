import Foundation
import EcoomixCore

/// Bütçe ayının başlangıç günü (Ayarlar > Bütçe ayı). Varsayılan 1: takvim ayı.
/// Özet, raporlar, bütçeler, tasarruf önerileri ve Gemini analizi ayları buna göre keser.
enum MonthSettings {
    static let key = "monthStartDay"

    static func rule(_ defaults: UserDefaults = .standard) -> MonthRule {
        MonthRule(startDay: defaults.object(forKey: key) as? Int ?? 1)
    }
}
