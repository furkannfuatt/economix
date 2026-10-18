import SwiftUI
import SwiftData
import UserNotifications

@main
struct EcoomixApp: App {
    let container: ModelContainer
    @State private var budgetMonitor: BudgetMonitor

    init() {
        let container = ModelContainerFactory.make(StoreMode.current)
        self.container = container
        _budgetMonitor = State(initialValue: BudgetMonitor(context: container.mainContext))
        UNUserNotificationCenter.current().delegate = NotificationPresenter.shared
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(budgetMonitor)
        }
        .modelContainer(container)
    }
}
