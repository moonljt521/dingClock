import BackgroundTasks
import Foundation

/// 后台刷新调度。
///
/// 排期窗口是滚动式的：算好未来 N 天后，必须有人定期把它往前推。
/// App 每次回到前台会推一次，但如果用户好几天不打开 App，就得靠后台唤醒。
///
/// SwiftUI 的 `.backgroundTask(.appRefresh(id))` 只负责**注册处理器**，
/// 具体何时运行完全由系统决定。主动 `submit` 一次能明显提高被调度的概率。
enum BackgroundRefresh {

    static let taskID = "com.moonding.dingclock.refresh"

    /// 请求系统在两三天后唤醒一次，用来把排期窗口向前滚。
    /// 失败不致命 —— 下次进前台还会再滚一次。
    @discardableResult
    static func requestReschedule(after interval: TimeInterval = 2 * 24 * 60 * 60) -> Bool {
        let request = BGAppRefreshTaskRequest(identifier: taskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: interval)
        do {
            try BGTaskScheduler.shared.submit(request)
            return true
        } catch {
            // 模拟器、低电量模式、任务过多等情况下会失败，属于正常现象
            return false
        }
    }
}
