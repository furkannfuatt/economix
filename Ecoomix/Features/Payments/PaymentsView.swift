import SwiftUI

struct PaymentsView: View {
    enum Section: String, CaseIterable, Identifiable {
        case installments = "Taksitler"
        case subscriptions = "Düzenli"
        case cards = "Kartlar"
        var id: String { rawValue }
    }

    @AppStorage("paymentsSection") private var section: Section = .installments
    @State private var newRecurring = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Picker("Bölüm", selection: $section) {
                        ForEach(Section.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    switch section {
                    case .installments: InstallmentsTab()
                    case .subscriptions: SubscriptionsTab()
                    case .cards: CardsTab()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Ödemeler")
            .navigationDestination(for: InstallmentPlan.self) { PlanDetailView(plan: $0) }
            .toolbar {
                if section == .subscriptions {
                    Button("Düzenli ödeme ekle", systemImage: "plus") { newRecurring = true }
                }
            }
            .sheet(isPresented: $newRecurring) {
                RecurringEditorView(item: nil)
            }
        }
    }
}
