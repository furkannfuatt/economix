import SwiftUI
import SwiftData
import UserNotifications

struct NotificationSettingsView: View {
    @Environment(\.modelContext) private var context
    @AppStorage(NotificationPreferences.budgetKey) private var budget = true
    @AppStorage(NotificationPreferences.cardKey) private var cardDue = true
    @AppStorage(NotificationPreferences.subscriptionKey) private var subscription = true
    @AppStorage(NotificationPreferences.monthlyKey) private var monthly = true
    @State private var status: UNAuthorizationStatus = .notDetermined

    var body: some View {
        Form {
            Section {
                switch status {
                case .authorized, .provisional, .ephemeral:
                    Label("Bildirimlere izin verildi", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(ChartPalette.single)
                case .denied:
                    Button("Bildirim izni kapalı — Ayarlar'ı aç", systemImage: "bell.slash.fill") {
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                default:
                    Button("Bildirimlere izin ver", systemImage: "bell.badge.fill") {
                        Task {
                            _ = await NotificationScheduler.requestAuthorization()
                            await refresh()
                        }
                    }
                }
            }

            Section {
                Toggle("Bütçe %80 ve %100 uyarıları", isOn: $budget)
                Toggle("Kart son ödeme (2 gün önce)", isOn: $cardDue)
                Toggle("Abonelik yenileme (1 gün önce)", isOn: $subscription)
                Toggle("Aylık özet (ayın 1'i)", isOn: $monthly)
            } footer: {
                Text("Bildirimler cihazında planlanır; hiçbir sunucuya veri gitmez.")
            }
        }
        .navigationTitle("Bildirimler")
        .task { await refresh() }
        .onChange(of: [cardDue, subscription, monthly]) {
            Task { await AppMaintenance.rescheduleReminders(context: context) }
        }
    }

    private func refresh() async {
        status = await NotificationScheduler.authorizationStatus()
    }
}
