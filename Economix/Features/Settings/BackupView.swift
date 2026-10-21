import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Ayarlar > Yedekle ve geri yükle.
struct BackupView: View {
    @Environment(\.modelContext) private var context
    @Query private var entries: [LedgerEntry]
    @State private var file: URL?
    @State private var error: String?

    var body: some View {
        List {
            Section {
                LabeledContent("İşlem sayısı", value: "\(entries.count)")
                if let file {
                    ShareLink(item: file) {
                        Label("Yedek dosyasını kaydet / paylaş", systemImage: "square.and.arrow.up")
                    }
                } else if let error {
                    Text(error).foregroundStyle(.red)
                } else {
                    ProgressView()
                }
            } header: {
                Text("Yedek al")
            } footer: {
                Text("Hesaplar, kategoriler, bütçeler, işlemler, taksitler, düzenli ödemeler ve ayarların tek bir dosyaya yazılır. Dosya şifrelenmez; Dosyalar uygulamasında sana ait bir klasörde sakla. Gemini anahtarı, Gemini izni ve Face ID kilidi yedeğe girmez.")
            }

            Section {
                BackupRestoreButton()
            } header: {
                Text("Yedekten geri yükle")
            } footer: {
                Text("Mevcut tüm verilerin silinir, yerine yedektekiler gelir; iCloud'daki kopya da buna göre güncellenir.")
            }
        }
        .navigationTitle("Yedekle ve geri yükle")
        .task {
            do {
                file = try BackupService.writeTemporaryFile(from: context)
            } catch {
                self.error = "Yedek oluşturulamadı: \(error.localizedDescription)"
            }
        }
        // Tüm verilerin düz metin kopyası geçici klasörde kalmasın.
        .onDisappear {
            BackupService.removeTemporaryFiles()
            file = nil
        }
    }
}

/// Yedek dosyası seçtirir, onay alıp geri yükler. Ayarlar'da ve ilk kurulum ekranında kullanılır.
struct BackupRestoreButton: View {
    var title = "Yedek dosyası seç"

    @Environment(\.modelContext) private var context
    @State private var picking = false
    @State private var pending: Data?
    @State private var confirming = false
    @State private var message: String?
    @State private var error: String?

    var body: some View {
        Button(title, systemImage: "arrow.down.doc") { picking = true }
            .fileImporter(isPresented: $picking, allowedContentTypes: [.json]) { result in
                switch result {
                case .success(let url): load(url)
                case .failure(let failure): error = failure.localizedDescription
                }
            }
            .confirmationDialog("Mevcut veriler silinip yedektekilerle değiştirilsin mi?", isPresented: $confirming,
                                titleVisibility: .visible) {
                Button("Geri yükle", role: .destructive) {
                    if let pending { restore(pending) }
                    pending = nil
                }
                Button("Vazgeç", role: .cancel) { pending = nil }
            }
        if let message {
            Label(message, systemImage: "checkmark.circle")
                .font(.subheadline)
                .foregroundStyle(ChartPalette.single)
        }
        if let error {
            Text(error).font(.subheadline).foregroundStyle(.red)
        }
    }

    private func load(_ url: URL) {
        message = nil
        error = nil
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > BackupService.maxFileBytes {
            error = BackupService.BackupError.tooLarge.localizedDescription
            return
        }
        do {
            pending = try Data(contentsOf: url)
            confirming = true
        } catch {
            self.error = "Dosya okunamadı: \(error.localizedDescription)"
        }
    }

    private func restore(_ data: Data) {
        do {
            let summary = try BackupService.restore(data, into: context)
            AppMaintenance.runOnForeground(context: context)
            message = "Geri yüklendi: \(summary.entries) işlem, \(summary.accounts) hesap, \(summary.categories) kategori."
        } catch {
            self.error = error.localizedDescription
        }
    }
}
