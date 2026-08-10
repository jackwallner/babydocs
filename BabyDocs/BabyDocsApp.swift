import SwiftData
import SwiftUI

@main
struct BabyDocsApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    private let container: ModelContainer

    init() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-uitest-wipe-store") {
            BabyModelStore.wipeStoreFilesForTesting()
        }
        #endif
        container = BabyModelStore.sharedModelContainer

        // Synchronous and network-free, so the first frame already knows
        // whether there is a session. Anything async here would put a spinner
        // in front of a plan that is sitting on disk.
        AuthService.shared.bootstrap()
        FamilyService.shared.loadFromCache()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .modelContainer(container)
                .task {
                    StoreService.shared.start()
                    NotificationService.shared.start()
                    await AuthService.shared.refreshInBackground()
                    await FamilyService.shared.refresh()
                    await SyncCoordinator.shared.syncNow()
                }
                .onOpenURL { url in
                    if let code = InviteLink.code(from: url) {
                        AppNavigator.shared.pendingInviteCode = code
                    }
                }
        }
    }
}
