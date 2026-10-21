import SwiftUI
import SwiftData
import EconomixCore

struct SettingsView: View {
    @AppStorage(AppLock.enabledKey) private var appLockEnabled = false
    @AppStorage(MonthSettings.key) private var monthStartDay = 1
    @State private var lockAvailable = AppLock.isAvailable

    private var monthFooter: String {
        let rule = MonthRule(startDay: monthStartDay)
        let current = rule.current()
        var text = "Özet, raporlar, bütçeler, tasarruf önerileri ve Gemini analizi ayları buna göre keser. "
        if !rule.isCalendarMonth {
            text += "Şu anki dönem: \(rule.rangeTitle(of: current)) (\(current.monthName)). "
                + "Dönem, günlerinin çoğunun düştüğü ayın adını alır. "
        }
        return text + "Kart hesap kesimi, taksit ve abonelik tarihleri değişmez."
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Veriler") {
                    NavigationLink {
                        AccountsView()
                    } label: {
                        Label("Hesaplar ve kartlar", systemImage: "creditcard.fill")
                    }
                    NavigationLink {
                        CategoriesView()
                    } label: {
                        Label("Kategoriler ve bütçeler", systemImage: "square.grid.2x2.fill")
                    }
                    NavigationLink {
                        ImportView()
                    } label: {
                        Label("Ekstre içe aktar", systemImage: "square.and.arrow.down.fill")
                    }
                }

                Section {
                    Picker(selection: $monthStartDay) {
                        ForEach(1...31, id: \.self) { day in
                            Text(day == 1 ? "Her ayın 1'i (takvim ayı)" : "Her ayın \(MonthRule(startDay: day).startDayTitle)")
                                .tag(day)
                        }
                    } label: {
                        Label("Ay başlangıcı", systemImage: "calendar.badge.clock")
                    }
                } header: {
                    Text("Bütçe ayı")
                } footer: {
                    Text(monthFooter)
                }

                Section("Analiz ve uyarılar") {
                    NavigationLink {
                        AISettingsView()
                    } label: {
                        Label("Yapay zekâ", systemImage: "sparkles")
                    }
                    NavigationLink {
                        NotificationSettingsView()
                    } label: {
                        Label("Bildirimler", systemImage: "bell.badge.fill")
                    }
                }

                Section {
                    Toggle(isOn: Binding(get: { appLockEnabled }, set: { newValue in setAppLock(newValue) })) {
                        Label("Face ID ile kilitle", systemImage: "faceid")
                    }
                    // Cihaz parolası yokken kilit açılamaz; açık kalmışsa çalışmadığı söylenir.
                    .disabled(!lockAvailable && !appLockEnabled)
                    if !lockAvailable {
                        Label(appLockEnabled
                              ? "Kilit şu an çalışmıyor: cihazda parola yok. Ayarlar > Face ID ve Parola'dan parola belirle."
                              : "Kilit için cihazda parola olmalı. Ayarlar > Face ID ve Parola'dan belirleyebilirsin.",
                              systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    NavigationLink {
                        BackupView()
                    } label: {
                        Label("Yedekle ve geri yükle", systemImage: "externaldrive.badge.icloud")
                    }
                    NavigationLink {
                        ExportView()
                    } label: {
                        Label("İşlemleri dışa aktar (CSV)", systemImage: "square.and.arrow.up")
                    }
                } header: {
                    Text("Güvenlik ve yedek")
                } footer: {
                    Text("Veriler iCloud'da otomatik yedeklenir. Yedek dosyası verilerini başka bir kuruluma taşımak için; CSV, Excel'de açabileceğin ek bir kopyadır.")
                }

                Section {
                    LabeledContent("Sürüm", value: Bundle.main.appVersion)
                    LabeledContent("Senkron", value: StoreMode.current == .cloud ? "iCloud" : "Yerel (demo)")
                }
            }
            .navigationTitle("Ayarlar")
            .onAppear { lockAvailable = AppLock.isAvailable }
        }
    }
}

extension SettingsView {
    /// Kilidi açarken önce kimlik doğrulanır; doğrulanamazsa açılmaz.
    private func setAppLock(_ enabled: Bool) {
        guard enabled else {
            appLockEnabled = false
            return
        }
        Task {
            if await AppLock.authenticate(reason: "Face ID kilidini açmak için doğrula") { appLockEnabled = true }
        }
    }
}

struct ExportView: View {
    @Query private var entries: [LedgerEntry]
    @State private var file: URL?
    @State private var error: String?

    var body: some View {
        List {
            Section {
                LabeledContent("İşlem sayısı", value: "\(entries.count)")
                if let file {
                    ShareLink(item: file) {
                        Label("CSV dosyasını paylaş / kaydet", systemImage: "square.and.arrow.up")
                    }
                } else if let error {
                    Text(error).foregroundStyle(.red)
                } else {
                    ProgressView()
                }
            } footer: {
                Text("Dosyalar uygulamasına, iCloud Drive'a ya da e-postaya kaydedebilirsin. Excel'de Türkçe ayarlarla doğrudan açılır.")
            }
        }
        .navigationTitle("Dışa aktar")
        .task {
            do {
                file = try CSVExporter.writeTemporaryFile(for: entries)
            } catch {
                self.error = "Dosya oluşturulamadı: \(error.localizedDescription)"
            }
        }
        // Tüm işlemlerin düz metin kopyası geçici klasörde kalmasın.
        .onDisappear {
            CSVExporter.removeTemporaryFiles()
            file = nil
        }
    }
}

extension Bundle {
    var appVersion: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}
