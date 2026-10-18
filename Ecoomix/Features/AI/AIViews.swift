import SwiftUI
import SwiftData
import EcoomixCore

/// Öneriler ekranındaki AI bölümü: son analiz + yeni analiz düğmesi.
struct AIAnalysisSection: View {
    let data: FinanceSnapshot

    @Environment(\.modelContext) private var context
    @Query(sort: \AIAnalysis.createdAt, order: .reverse) private var analyses: [AIAnalysis]
    @AppStorage("aiIncludeMerchants") private var includeMerchants = false
    @AppStorage(GeminiModel.storageKey) private var model = GeminiModel.flash.rawValue
    @State private var running = false
    @State private var error: String?
    @State private var hasKey = GeminiKeyProvider.current != nil

    var body: some View {
        Group {
            if !hasKey {
                NavigationLink {
                    AISettingsView()
                } label: {
                    Label("Gemini API anahtarını ekle", systemImage: "key.fill")
                }
                Text("Analiz isteğe bağlıdır. Yalnızca toplulaştırılmış rakamlar gönderilir.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Button {
                    Task { await run() }
                } label: {
                    HStack {
                        Label(running ? "Analiz ediliyor…" : "Son 6 ayı analiz et", systemImage: "sparkles")
                        Spacer()
                        if running { ProgressView() }
                    }
                }
                .disabled(running)

                if running {
                    Text("Gemini düşünerek yanıt veriyor; 1–2 dakika sürebilir.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let error {
                    Text(error).font(.footnote).foregroundStyle(.red)
                }

                if let latest = analyses.first, let advice = latest.advice {
                    NavigationLink {
                        AIAdviceView(analysis: latest, advice: advice)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Son analiz · \(TR.shortDate(latest.createdAt))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(advice.summary)
                                .font(.subheadline)
                                .lineLimit(3)
                        }
                    }
                }
                if analyses.count > 1 {
                    NavigationLink("Geçmiş analizler (\(analyses.count))") {
                        AIHistoryView()
                    }
                }
            }
        }
        .onAppear { hasKey = GeminiKeyProvider.current != nil }
    }

    private func run() async {
        guard let key = GeminiKeyProvider.current else { return }
        running = true
        error = nil
        defer { running = false }

        let now = Date.now
        let input = AnalysisInput(transactions: data.transactions, asOf: now, budgets: data.budgets,
                                  categoryNames: data.categoryNames, subscriptions: data.subscriptions,
                                  installmentPlans: data.planSchedules)
        let payload = AIPayloadBuilder.build(from: input, insights: data.insights(asOf: now),
                                             includeMerchants: includeMerchants)
        do {
            let advice = try await GeminiAdvisor(apiKey: key, model: model).analyze(payload: payload)
            let json = String(decoding: try JSONEncoder().encode(advice), as: UTF8.self)
            let current = YearMonth.current()
            context.insert(AIAnalysis(periodStart: current.adding(months: -(AIPayloadBuilder.monthCount - 1)).start,
                                      periodEnd: now, model: model, resultJSON: json))
            try context.save()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

extension AIAnalysis {
    var advice: AIAdvice? { try? JSONDecoder().decode(AIAdvice.self, from: Data(resultJSON.utf8)) }
}

struct AIAdviceView: View {
    let analysis: AIAnalysis
    let advice: AIAdvice

    var body: some View {
        List {
            Section {
                Text(advice.summary)
                    .padding(.vertical, 4)
            } footer: {
                Text("\(TR.shortDate(analysis.createdAt)) · \(analysis.model)")
            }

            Section("Öneriler") {
                ForEach(advice.insights, id: \.self) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(item.title).font(.headline)
                            Spacer()
                            Text(priorityLabel(item.priority))
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(priorityColor(item.priority).opacity(0.15), in: .capsule)
                                .foregroundStyle(priorityColor(item.priority))
                        }
                        Text(item.detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if item.estimatedMonthlySaving > 0 {
                            Text("Olası tasarruf: ayda \(Money(minor: Int(item.estimatedMonthlySaving * 100)).formatted(decimals: false))")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(ChartPalette.single)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Section("Gelecek ay planı") {
                ForEach(Array(advice.nextMonthPlan.enumerated()), id: \.offset) { index, step in
                    Label(step, systemImage: "\(index + 1).circle.fill")
                }
            }
        }
        .navigationTitle("Yapay zekâ analizi")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func priorityLabel(_ value: String) -> String {
        switch value {
        case "high": "Yüksek"
        case "medium": "Orta"
        default: "Düşük"
        }
    }

    private func priorityColor(_ value: String) -> Color {
        switch value {
        case "high": .expense
        case "medium": .orange
        default: .secondary
        }
    }
}

struct AIHistoryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \AIAnalysis.createdAt, order: .reverse) private var analyses: [AIAnalysis]

    var body: some View {
        List {
            ForEach(analyses) { analysis in
                if let advice = analysis.advice {
                    NavigationLink {
                        AIAdviceView(analysis: analysis, advice: advice)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(TR.shortDate(analysis.createdAt)).font(.subheadline.weight(.semibold))
                            Text(advice.summary).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
                    }
                }
            }
            .onDelete { offsets in
                offsets.map { analyses[$0] }.forEach(context.delete)
                try? context.save()
            }
        }
        .navigationTitle("Geçmiş analizler")
    }
}

struct AISettingsView: View {
    @AppStorage("aiIncludeMerchants") private var includeMerchants = false
    @AppStorage(GeminiModel.storageKey) private var model = GeminiModel.flash.rawValue
    @State private var key = ""
    @State private var saved = KeychainStore.read(KeychainStore.geminiKey) != nil
    private let hasBundledKey = GeminiKeyProvider.bundledKey != nil

    var body: some View {
        Form {
            Section {
                if saved {
                    Label("Uygulamada girilen anahtar kayıtlı", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(ChartPalette.single)
                    Button("Anahtarı sil", role: .destructive) {
                        KeychainStore.delete(KeychainStore.geminiKey)
                        saved = false
                    }
                } else {
                    if hasBundledKey {
                        Label("Derlemeye gömülü anahtar kullanılıyor", systemImage: "doc.badge.gearshape")
                            .foregroundStyle(ChartPalette.single)
                    }
                    SecureField(hasBundledKey ? "Başka bir anahtar gir (isteğe bağlı)" : "AIza…", text: $key)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Kaydet") {
                        saved = KeychainStore.save(key.trimmingCharacters(in: .whitespacesAndNewlines),
                                                   for: KeychainStore.geminiKey)
                        key = ""
                    }
                    .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } header: {
                Text("Gemini API anahtarı")
            } footer: {
                Text("aistudio.google.com adresinden alınır. Uygulamada girilen anahtar yalnızca bu cihazın Keychain'inde saklanır ve projedeki Config/Secrets.xcconfig dosyasındaki anahtardan önce gelir.")
            }

            Section("Model") {
                Picker("Model", selection: $model) {
                    ForEach(GeminiModel.allCases) { Text($0.title).tag($0.rawValue) }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }

            Section {
                Toggle("İşyeri adlarını gönder", isOn: $includeMerchants)
            } header: {
                Text("Gizlilik")
            } footer: {
                Text("Kapalıyken yalnızca aylık toplamlar, kategori toplamları, bütçeler, abonelik adları ve taksit yükü gönderilir. İşlem notları hiçbir zaman gönderilmez. Açarsan en çok harcama yaptığın 15 işyerinin adı ve toplamı da eklenir.")
            }

            Section {
                LabeledContent("Sağlayıcı", value: "Google Gemini")
                LabeledContent("Ne zaman çalışır", value: "Yalnızca sen istediğinde")
            } footer: {
                Text("Kullanım Google AI Studio hesabının kotasından düşer; ücretsiz katmanda Google verileri ürün geliştirmede kullanabilir.")
            }
        }
        .navigationTitle("Yapay zekâ")
    }
}
