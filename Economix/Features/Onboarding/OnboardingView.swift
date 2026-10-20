import SwiftUI
import SwiftData

struct OnboardingView: View {
    @Environment(\.modelContext) private var context
    @State private var error: String?

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            Image(systemName: "chart.pie.fill")
                .font(.system(size: 72))
                .foregroundStyle(.tint)
                .symbolEffect(.bounce, options: .nonRepeating)

            VStack(spacing: 10) {
                Text("Economix'e hoş geldin")
                    .font(.largeTitle.bold())
                Text("Gelir, gider, taksit ve aboneliklerini tek yerde takip et. Verilerin yalnızca senin iCloud hesabında durur.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 14) {
                feature("list.bullet.rectangle.portrait.fill", "Harcamalarını kategorilere ayır")
                feature("creditcard.fill", "Kart kesim ve taksitlerini izle")
                feature("bell.badge.fill", "Bütçe aşımında bildirim al")
                feature("lightbulb.fill", "Nereden tasarruf edebileceğini gör")
            }
            .padding(.vertical, 8)

            Spacer()

            if let error {
                Text(error).font(.footnote).foregroundStyle(.red)
            }

            Button {
                do {
                    try SeedService.seedDefaults(in: context)
                } catch {
                    self.error = "Başlatılamadı: \(error.localizedDescription)"
                }
            } label: {
                Text("Başla")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)

            Text("Yeniden kurulumda iCloud'daki verilerin birkaç saniye içinde gelir.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
    }

    private func feature(_ icon: String, _ text: String) -> some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: icon).foregroundStyle(.tint)
        }
        .font(.callout)
    }
}
