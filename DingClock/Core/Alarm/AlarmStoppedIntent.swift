import Foundation

#if canImport(AlarmKit)
import AppIntents

/// 闹钟被用户关掉时，系统会调用这个 Intent（通过 AlarmConfiguration.stopIntent）。
///
/// 这是滑动窗口方案里**最可靠**的前滚触发器，没有之一：
///
/// · 每响一次，就有一个闹钟槽位刚空出来 —— 正好在这一刻把最远端的新闹钟补上，
///   让同时存在的闹钟数始终顶在上限、覆盖范围持续向前滚。
/// · 相比之下 `BGAppRefreshTask` 是机会式的（可能几天不跑，用户强退后永远不跑），
///   只能当加分项。
///
/// 放在主 App target：系统会在后台拉起 App 进程执行，**不需要用户打开 App**。
///
/// 依据 Apple DTS 官方 FAQ：闹钟被关掉（滑动或按电源键）时，
/// AlarmConfiguration 里设置的 stopIntent 会被调用，其 perform 方法得以执行。
struct AlarmStoppedIntent: LiveActivityIntent {

    static var title: LocalizedStringResource = "闹钟已关闭"

    func perform() async throws -> some IntentResult {
        await AlarmStore.rollWindowAfterAlarmStopped()
        return .result()
    }
}
#endif
