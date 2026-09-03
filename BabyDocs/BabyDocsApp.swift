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

        // Plus, without a purchase. Debug only, and never a path a shipping
        // build can take: the Plus tab is a different screen once it is bought
        // (the timeline, the reminder switches, the pages that leave the
        // phone), and none of that is inspectable on a simulator otherwise,
        // because RevenueCat is deliberately never configured there.
        if ProcessInfo.processInfo.arguments.contains("-uitest-pro") {
            MainActor.assumeIsolated {
                StoreService.shared.setLocalOverride(isPro: true)
            }
        }

        // Opens straight onto one task's detail, by catalog key.
        //
        // For the layout tests, which are about what a screen looks like at a
        // given text size and not about whether a list can be scrolled. Finding
        // the row by swiping was most of what those tests actually exercised:
        // at accessibility XXXL the plan is many screens long, so the hunt
        // burned five minutes, failed on its own scroll budget, and reported it
        // as a layout failure. Same door, unlocked from the outside.
        if let index = ProcessInfo.processInfo.arguments.firstIndex(of: "-uitest-open-task"),
           index + 1 < ProcessInfo.processInfo.arguments.count {
            let key = ProcessInfo.processInfo.arguments[index + 1]
            MainActor.assumeIsolated {
                let context = container.mainContext
                let match = ((try? context.fetch(FetchDescriptor<RequirementTask>())) ?? [])
                    .first { $0.catalogKey == key && $0.deletedAt == nil }
                AppNavigator.shared.pendingTaskID = match?.id
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
                    ConversionDiagnostics.recordAppOpen()
                    #if DEBUG
                    if RevenueCatProbe.isEnabled {
                        // Same entry point the paywall calls, so what this
                        // proves is the actual path and not a parallel one.
                        StoreService.shared.trackPaywallImpression(id: RevenueCatProbe.impressionID)
                    }
                    #endif
                }
                .onOpenURL { url in
                    AppNavigator.shared.open(url)
                }
        }
    }
}
