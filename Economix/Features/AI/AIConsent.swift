import SwiftUI

/// Gemini'ye veri gönderilmeden önce bir kez alınan açık izin. Ayarlar > Yapay zekâ'dan geri alınabilir.
enum AIConsent {
    static let key = "aiConsentGiven"

    static let title = "Verilerin Google'a gönderilsin mi?"

    static let message = """
    Gemini ile analiz ve kategorileme için şu bilgiler, senin API anahtarınla Google'ın Gemini hizmetine gönderilir:

    • Analizde: son 6 ayın aylık gelir-gider toplamları, kategori toplamları, bütçeler, abonelik adları ve taksit yükü. Ayarlardan izin verirsen en çok harcadığın işyerlerinin ve bitmek üzere olan taksit planlarının adları.
    • Kategorilemede: ekstredeki işyeri adları ve kategori adların.

    İşlem notları, hesap adları ve kimlik bilgilerin gönderilmez. Ücretsiz Gemini katmanında Google bu içeriği ürünlerini geliştirmek için kullanabilir.
    """
}

extension View {
    /// İzin yoksa önce onay penceresi gösterir; kabul edilirse izni kaydedip işlemi başlatır.
    func aiConsentAlert(isPresented: Binding<Bool>, onAccept: @escaping () -> Void) -> some View {
        alert(AIConsent.title, isPresented: isPresented) {
            Button("İzin ver ve devam et") {
                UserDefaults.standard.set(true, forKey: AIConsent.key)
                onAccept()
            }
            Button("Vazgeç", role: .cancel) {}
        } message: {
            Text(AIConsent.message)
        }
    }
}
