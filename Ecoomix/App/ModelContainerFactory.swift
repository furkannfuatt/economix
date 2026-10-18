import Foundation
import SwiftData

enum StoreMode {
    /// Gerçek veri, iCloud ile senkron.
    case cloud
    /// DEBUG demo verisi: ayrı dosya, asla iCloud'a gitmez.
    case demo
    /// Testler ve önizlemeler.
    case inMemory

    static var current: StoreMode {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return .inMemory }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-demoData") { return .demo }
        #endif
        return .cloud
    }
}

enum ModelContainerFactory {
    static let cloudContainerID = "iCloud.com.furkanfuat.ecoomix"

    static func make(_ mode: StoreMode) -> ModelContainer {
        let schema = Schema(EcoomixSchema.models)
        do {
            switch mode {
            case .cloud:
                let config = ModelConfiguration("Ecoomix", schema: schema,
                                                cloudKitDatabase: .private(cloudContainerID))
                return try ModelContainer(for: schema, configurations: config)
            case .demo:
                let url = URL.applicationSupportDirectory.appending(path: "demo.store")
                let config = ModelConfiguration("Demo", schema: schema, url: url, cloudKitDatabase: .none)
                return try ModelContainer(for: schema, configurations: config)
            case .inMemory:
                let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
                return try ModelContainer(for: schema, configurations: config)
            }
        } catch {
            // iCloud yapılandırması yüklenemezse veriler kaybolmasın: aynı dosyayı yerel açar.
            let config = ModelConfiguration("Ecoomix", schema: schema, cloudKitDatabase: .none)
            do {
                return try ModelContainer(for: schema, configurations: config)
            } catch {
                fatalError("Veritabanı açılamadı: \(error)")
            }
        }
    }
}
