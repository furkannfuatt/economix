import Foundation

/// İçe aktarılan dosyalar için üst sınırlar. Banka ekstreleri birkaç yüz satır ve birkaç MB'tır; sınırlar bozuk
/// ya da kötü niyetli bir dosyanın belleği doldurup uygulamayı kilitlemesini önler.
public enum ImportLimits {
    public static let maxFileBytes = 20 * 1024 * 1024
    public static let maxRows = 20_000
    public static let maxColumns = 100
}
