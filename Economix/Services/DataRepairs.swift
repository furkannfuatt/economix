import Foundation
import SwiftData
import EconomixCore

/// Önceki sürümlerdeki hataların veride bıraktığı izleri bir kez düzeltir.
enum DataRepairs {
    static func run(in context: ModelContext, defaults: UserDefaults = .standard) throws {
        let key = "repair.installmentTaxi.v1"
        guard !defaults.bool(forKey: key) else { return }
        try repairInstallmentTaxi(in: context)
        defaults.set(true, forKey: key)
    }

    /// "TAKSI" kökü "TAKSIT" yazısını da yakalıyordu: taksitli alımlar Ulaşım'a düşüp bu kategori işyeri kuralı olarak öğreniliyordu.
    /// Bu kurallar silinir; taksit planları ve işlemler sözlüğün yeni önerisine (yoksa kategorisize) alınır.
    static func repairInstallmentTaxi(in context: ModelContext) throws {
        func affected(_ text: String) -> Bool {
            MerchantNormalizer.normalize(text).split(separator: " ").contains { $0.hasPrefix("TAKSIT") }
                && MerchantCategorizer.suggestedSeedKey(for: text) != "ulasim"
        }
        let categories = try context.fetch(FetchDescriptor<EntryCategory>())
        func replacement(for text: String) -> EntryCategory? {
            MerchantCategorizer.suggestedSeedKey(for: text).flatMap { key in
                categories.first { $0.seedKey == key && $0.kind == .expense }
            }
        }
        for rule in try context.fetch(FetchDescriptor<MerchantRule>())
        where rule.category?.seedKey == "ulasim" && affected(rule.pattern) {
            context.delete(rule)
        }
        for plan in try context.fetch(FetchDescriptor<InstallmentPlan>())
        where plan.category?.seedKey == "ulasim" && affected(plan.merchant) {
            plan.category = replacement(for: plan.merchant)
            for entry in plan.entries ?? [] where entry.category?.seedKey == "ulasim" { entry.category = plan.category }
        }
        for entry in try context.fetch(FetchDescriptor<LedgerEntry>())
        where entry.category?.seedKey == "ulasim" && affected(entry.merchant) {
            entry.category = replacement(for: entry.merchant)
        }
        if context.hasChanges { try context.save() }
    }
}
