import SwiftUI
import LocalAuthentication

/// İsteğe bağlı Face ID kilidi. Uygulama arka plana geçince kilitlenir; uygulama değiştiricide içerik görünmez.
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

/// Kilit ekranını kendi penceresinde gösterir. Ana görünümün üstündeki bir katman, sonradan açılan sayfaların
/// (sheet) ve klavyenin altında kalır; bu pencere hepsinin üstündedir ve erişilebilirlikte de arkayı kapatır.
final class LockWindowPresenter {
    private var window: UIWindow?
    private var keyboardObserver: NSObjectProtocol?

    func show(onUnlock: @escaping () -> Void) {
        // Klavye kendi penceresinde, kilidin üstünde durur: açık olanı kapat, kilitliyken açılmasına izin verme
        // (ör. kilitten sonra açılıp tutar alanına odaklanan bir sayfa).
        hideKeyboard()
        guard window == nil,
              let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first
        else { return }
        let host = UIHostingController(rootView: LockScreen(onUnlock: onUnlock))
        host.view.accessibilityViewIsModal = true
        let window = UIWindow(windowScene: scene)
        window.windowLevel = .alert + 1
        window.rootViewController = host
        window.isHidden = false
        self.window = window
        keyboardObserver = NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillShowNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { hideKeyboard() }
        }
    }

    func hide() {
        window?.isHidden = true
        window = nil
        if let keyboardObserver { NotificationCenter.default.removeObserver(keyboardObserver) }
        keyboardObserver = nil
    }
}

struct LockScreen: View {
    let onUnlock: () -> Void

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.tint)
                Text("Ecoomix kilitli").font(.title3.weight(.semibold))
                Button("Kilidi aç", systemImage: "faceid", action: onUnlock)
                    .buttonStyle(.glassProminent)
            }
        }
        // Arkadaki sayfanın klavyesi açılıp kapanırken kilit ekranı yerinden oynamasın.
        .ignoresSafeArea(.keyboard)
    }
}
