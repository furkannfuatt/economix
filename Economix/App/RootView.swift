import SwiftUI
import SwiftData
import EconomixCore

enum AppTab: String, Hashable {
    case summary, transactions, reports, payments, settings
}

/// Uygulama genelinde gezinme ve hızlı ekleme durumu.
@Observable
final class AppRouter {
    var tab: AppTab = .summary
    var editor: EditorRequest?

    init() {
        #if DEBUG
        // Ekran görüntüsü kontrolü için: -tab reports, -editor new
        let defaults = UserDefaults.standard
        if let raw = defaults.string(forKey: "tab"), let tab = AppTab(rawValue: raw) { self.tab = tab }
        if defaults.string(forKey: "editor") == "new" { editor = EditorRequest() }
        #endif
    }
}

struct EditorRequest: Identifiable {
    let id = UUID()
    var entry: LedgerEntry?
    var kind: TxKind = .expense
    var presetAmount: Money?
    var presetToAccountID: UUID?
}

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Query private var categories: [EntryCategory]
    @State private var router = AppRouter()
    @State private var lock = AppLock()
    @State private var lockWindow = LockWindowPresenter()
    @State private var bootstrapped = false

    private var showsLock: Bool { lock.isLocked || (scenePhase != .active && lock.isEnabled) }

    var body: some View {
        Group {
            if categories.isEmpty && bootstrapped {
                OnboardingView()
            } else {
                tabs
            }
        }
        .accessibilityHidden(showsLock)
        // Yedek: kilit penceresi açılamazsa ana görünüm yine örtülür.
        .overlay {
            if showsLock {
                LockScreen { Task { await lock.unlock() } }
            }
        }
        .onChange(of: showsLock, initial: true) { _, shown in
            if shown {
                lockWindow.show { Task { await lock.unlock() } }
            } else {
                lockWindow.hide()
            }
        }
        .environment(router)
        .environment(\.locale, TR.locale)
        .sheet(item: $router.editor) { request in
            EntryEditorView(request: request)
        }
        .task {
            await AppMaintenance.runOnLaunch(context: context)
            bootstrapped = true
            await lock.unlock()
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                AppMaintenance.runOnForeground(context: context)
                Task { await lock.unlock() }
            case .background:
                lock.lockIfNeeded()
            default:
                break
            }
        }
    }

    private var tabs: some View {
        TabView(selection: $router.tab) {
            Tab("Özet", systemImage: "chart.pie.fill", value: AppTab.summary) {
                DashboardView()
            }
            Tab("İşlemler", systemImage: "list.bullet.rectangle.portrait.fill", value: AppTab.transactions) {
                TransactionsView()
            }
            Tab("Raporlar", systemImage: "chart.bar.xaxis", value: AppTab.reports) {
                ReportsView()
            }
            Tab("Ödemeler", systemImage: "creditcard.fill", value: AppTab.payments) {
                PaymentsView()
            }
            Tab("Ayarlar", systemImage: "gearshape.fill", value: AppTab.settings) {
                SettingsView()
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tabViewBottomAccessory {
            Button {
                router.editor = EditorRequest()
            } label: {
                Label("İşlem ekle", systemImage: "plus.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

enum AppMaintenance {
    /// Açılışta: iCloud kopyalarını birleştir, yeni varsayılanları ekle, eski hataların izlerini onar,
    /// kaçırılan düzenli işlemleri üret.
    static func runOnLaunch(context: ModelContext) async {
        // Dışa aktarma/yedek ekranındayken kapanan uygulamanın geçici dosyaları kalmasın.
        CSVExporter.removeTemporaryFiles()
        BackupService.removeTemporaryFiles()
        try? SeedService.deduplicate(in: context)
        try? SeedService.migrateInvestmentCategory(in: context)
        try? SeedService.addNewDefaults(in: context)
        try? DataRepairs.run(in: context)
        #if DEBUG
        if StoreMode.current == .demo { try? DemoData.loadIfNeeded(into: context) }
        #endif
        runOnForeground(context: context)
        let hasData = ((try? context.fetchCount(FetchDescriptor<EntryCategory>())) ?? 0) > 0
        // Demo modunda (yalnızca simülatör/ekran görüntüsü) izin penceresi açılmaz.
        if hasData, StoreMode.current != .demo, await NotificationScheduler.authorizationStatus() == .notDetermined {
            _ = await NotificationScheduler.requestAuthorization()
            await rescheduleReminders(context: context)
        }
    }

    static func runOnForeground(context: ModelContext) {
        try? RecurringGenerator(context: context).run()
        Task { await rescheduleReminders(context: context) }
    }

    static func rescheduleReminders(context: ModelContext) async {
        let accounts = (try? context.fetch(FetchDescriptor<Account>())) ?? []
        let recurring = (try? context.fetch(FetchDescriptor<RecurringItem>())) ?? []
        let entries = (try? context.fetch(FetchDescriptor<LedgerEntry>())) ?? []
        await NotificationScheduler.reschedule(cards: accounts, recurring: recurring,
                                               transactions: entries.map(\.snapshot))
    }
}
