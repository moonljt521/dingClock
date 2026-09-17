import SwiftUI

@main
struct DingClockApp: App {

    @StateObject private var store = AlarmStore()

    /// 后台刷新任务标识，需与 Info.plist 的 BGTaskSchedulerPermittedIdentifiers 一致
    static let refreshTaskID = BackgroundRefresh.taskID

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
        }
        .backgroundTask(.appRefresh(Self.refreshTaskID)) {
            // 后台把排期窗口向前滚动，保证「未来 N 天」始终已经排好
            await store.refreshOnForeground()
        }
    }
}
