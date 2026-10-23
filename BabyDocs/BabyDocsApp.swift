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
                        if RevenueCatProbe.wantsPurchase {
                            Task {
                                await StoreService.shared.refresh()
                                guard let plan = StoreService.shared.plans.first else { return }
                                try? await StoreService.shared.purchase(plan)
                            }
                        }
                    }
                    #endif
                }
                #if DEBUG
                .task { await openScreenshotRoute() }
                #endif
                .onOpenURL { url in
                    AppNavigator.shared.open(url)
                }
        }
    }

    #if DEBUG
    /// Screenshot routes, so an unattended capture can show each main screen
    /// without a UI test: `-duo-screen <plan|children|documents|plus|settings>`
    /// or `-duo-screen task/<catalog key>`. Applied a few seconds after launch
    /// rather than at it, so a native recording shows the move, and through
    /// launch arguments rather than links, which the simulator puts behind an
    /// "Open in Baby Docs?" alert.
    @MainActor
    private func openScreenshotRoute() async {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-duo-screen"), index + 1 < arguments.count else { return }
        let parts = arguments[index + 1].split(separator: "/").map(String.init)
        try? await Task.sleep(for: .seconds(7))
        let navigator = AppNavigator.shared
        withAnimation {
            switch parts.first {
            case "children": navigator.selectedTab = .children
            case "documents": navigator.selectedTab = .documents
            case "plus": navigator.selectedTab = .plus
            case "settings": navigator.selectedTab = .settings
            case "task":
                navigator.selectedTab = .plan
                let match = ((try? container.mainContext.fetch(FetchDescriptor<RequirementTask>())) ?? [])
                    .first { $0.catalogKey == parts.last && $0.deletedAt == nil }
                navigator.pendingTaskID = match?.id
            default: navigator.selectedTab = .plan
            }
        }
    }
    #endif
}
