import Foundation
import Testing
@testable import Ecoomix

@Suite("Uygulama kilidi")
@MainActor
struct AppLockTests {
    @Test("Kilit ayarı başlatma argümanıyla (-appLockEnabled NO) kapatılamaz; yalnızca kayıtlı değer okunur")
    func ignoresLaunchArguments() throws {
        let suite = "AppLockTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        // Başlatma argümanları süreç genelindeki argüman alanında durur; test sonunda eski hâline döner.
        let arguments = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        defer { defaults.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain) }
        defaults.set(true, forKey: "kilit")
        defaults.setVolatileDomain(arguments.merging(["kilit": false]) { _, new in new }, forName: UserDefaults.argumentDomain)

        #expect(defaults.bool(forKey: "kilit") == false)
        #expect(AppLock.storedFlag("kilit", in: defaults, domain: suite) == true)
        #expect(AppLock.storedFlag("baska", in: defaults, domain: suite) == false)
    }
}
