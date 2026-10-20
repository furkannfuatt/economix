import SwiftUI
import LocalAuthentication

/// İsteğe bağlı Face ID kilidi. Uygulama arka plana geçince kilitlenir; uygulama değiştiricide içerik görünmez.
@Observable
final class AppLock {
    static let enabledKey = "appLockEnabled"

    var isLocked: Bool

    init() {
        isLocked = Self.storedFlag(Self.enabledKey)
    }

    var isEnabled: Bool { Self.storedFlag(Self.enabledKey) }

    /// Ayar yalnızca uygulamanın kendi kaydından okunur. `UserDefaults.bool` başlatma argümanlarını da okur;
    /// böylece cihaza bağlı bir bilgisayardan `-appLockEnabled NO` ile açılan uygulama kilidi atlardı.
    static func storedFlag(_ key: String, in defaults: UserDefaults = .standard,
                           domain: String = Bundle.main.bundleIdentifier ?? "") -> Bool {
        defaults.persistentDomain(forName: domain)?[key] as? Bool ?? false
    }

    /// Cihazda parola yoksa kimlik doğrulanamaz; kilit de koruma sağlamaz (Ayarlar bunu gösterir).
    static var isAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    func lockIfNeeded() {
        if isEnabled { isLocked = true }
    }

    func unlock() async {
        guard isLocked else { return }
        // Kilit açıkken cihaz parolası kaldırıldıysa doğrulama imkânsızdır; kullanıcı kendi verisine
        // erişemez hâle gelmesin diye açılır. Ayarlar'da kilidin çalışmadığı uyarısı görünür.
        guard Self.isAvailable else {
            isLocked = false
            return
        }
        if await Self.authenticate(reason: "Ecoomix'i açmak için kimliğini doğrula") { isLocked = false }
    }

    /// Face ID / Touch ID, olmazsa cihaz parolası. Doğrulama yapılamıyorsa (cihaz parolası yok) false.
    static func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { return false }
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
