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

        #if DEBUG
        // Screenshot and manual-inspection runs. Seeds the sample family so the
        // plan renders from a real reconciliation pass rather than from a
        // hand-built fixture, which is the only version of a screenshot worth
        // trusting: if a rule is wrong, the picture is wrong too.
        if ProcessInfo.processInfo.arguments.contains("-uitest-seed") {
            MainActor.assumeIsolated {
                let context = container.mainContext
                if (try? context.fetchCount(FetchDescriptor<Child>())) == 0 {
                    SampleData.seed(into: context)
                }
            }
        }
        #endif

    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .modelContainer(container)
                .task {
                    StoreService.shared.start()
                    NotificationService.shared.start()
                    ReviewPromptTracker.recordAppLaunch()
                }
                .onOpenURL { url in
                    AppNavigator.shared.open(url)
                }
        }
    }
}
