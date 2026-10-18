import SwiftUI
import SwiftData
import EcoomixCore

/// Tüm tasarruf önerileri: kural tabanlı analiz (+ AI analizi).
struct InsightsView: View {
    @Query private var entries: [LedgerEntry]
    @Query(sort: \EntryCategory.sortOrder) private var categories: [EntryCategory]
    @Query private var plans: [InstallmentPlan]
    @Query private var recurring: [RecurringItem]

    var body: some View {
        let data = FinanceSnapshot(entries: entries, categories: categories, plans: plans, recurring: recurring)
        let insights = data.insights()
        // Tasarruf oranı açığı diğer önerileri kapsar; toplamda çift saymamak için dışarıda bırakılır.
        let potential = insights.filter { $0.kind != .savingsRate }
            .compactMap(\.estimatedMonthlySaving).filter { $0.minor > 0 }.sum()

        List {
            if potential.minor > 0 {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Toplam olası tasarruf").font(.subheadline).foregroundStyle(.secondary)
                        Text("ayda \(potential.formatted(decimals: false))")
                            .font(.title2.weight(.bold))
                            .monospacedDigit()
                        Text("yılda yaklaşık \((potential * 12).formatted(decimals: false))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                } footer: {
                    Text("Kategori ve abonelik önerilerinin toplamıdır; bazı öneriler kısmen örtüşebilir.")
                }
            }

            Section {
                AIAnalysisSection(data: data)
            } header: {
                Text("Yapay zekâ analizi")
            }

            Section("Kural tabanlı öneriler") {
                if insights.isEmpty {
                    Text("Şimdilik öneri yok. Birkaç haftalık veri girdikçe burada öneriler belirir.")
                        .foregroundStyle(.secondary)
                }
                ForEach(insights) { insight in
                    InsightRow(insight: insight)
                        .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("Öneriler")
    }
}
