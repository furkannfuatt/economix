import SwiftUI
import LocalAuthentication

/// İsteğe bağlı Face ID kilidi. Uygulama arka plana geçince kilitlenir; uygulama değiştiricide içerik bulanık görünür.
@Observable
final class AppLock {
    static let enabledKey = "appLockEnabled"

    var isLocked: Bool

    init() {
        isLocked = UserDefaults.standard.bool(forKey: Self.enabledKey)
    }

    var isEnabled: Bool { UserDefaults.standard.bool(forKey: Self.enabledKey) }

    func lockIfNeeded() {
        if isEnabled { isLocked = true }
    }

    func unlock() async {
        guard isLocked else { return }
        if await Self.authenticate(reason: "Ecoomix'i açmak için kimliğini doğrula") { isLocked = false }
    }

    /// Face ID / Touch ID, olmazsa cihaz parolası.
    static func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { return true }
        return (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) ?? false
    }
}

struct LockScreen: View {
    let onUnlock: () -> Void

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.tint)
                Text("Ecoomix kilitli").font(.title3.weight(.semibold))
                Button("Kilidi aç", systemImage: "faceid", action: onUnlock)
                    .buttonStyle(.glassProminent)
            }
        }
    }
}
