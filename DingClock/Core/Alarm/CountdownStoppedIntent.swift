import Foundation

#if canImport(AlarmKit)
import AppIntents

/// 倒计时被停止时系统会拉起 App 执行这个 Intent。
///
/// 和闹钟的 `AlarmStoppedIntent` **刻意分开**：那边停止后要做的是滚动排期窗口，
/// 这边只需要把界面状态复位。混成一个 Intent 会让后台回调里多跑一堆无用功 ——
/// 而系统给后台回调的时间本来就短。
struct CountdownStoppedIntent: LiveActivityIntent {

    static var title: LocalizedStringResource = "倒计时已停止"

    func perform() async throws -> some IntentResult {
        CountdownController.markStoppedInBackground()
        return .result()
    }
}
#endif
