import Foundation
import os.log

#if canImport(AlarmKit)
import AlarmKit
import ActivityKit
import SwiftUI

/// 倒计时的真·后端：AlarmKit 的 `timer` 配置。
///
/// 用它的理由和闹钟一样 —— 这是唯一能突破静音模式与专注模式、并且会
/// 自己接管锁屏与灵动岛倒计时的路径。倒计时通常是"我在等一个东西"，
/// 人未必盯着屏幕，静音下听不见就等于没提醒。
///
/// - Note: `AlarmManager.AlarmConfiguration.timer` 和 `AlarmConfiguration.alarm`
///   是两条不同的构造路径：前者不需要 `schedule` 字段（时长即全部），
///   后者才需要 `.fixed(日期)`。倒计时走前者。
@available(iOS 26.0, *)
final class AlarmKitCountdownScheduler: CountdownScheduling, @unchecked Sendable {

    private var manager: AlarmManager { .shared }

    private static let log = Logger(subsystem: "com.moonding.dingclock", category: "Countdown")

    var isSupported: Bool { true }
    var backendNote: String {
        "由系统接管：锁屏与灵动岛显示原生倒计时，到点突破静音模式响铃。"
    }

    func start(duration: TimeInterval) async throws {
        // 上一个没清干净的话，schedule 同一个 ID 的行为不保证是覆盖 —— 先清一次最稳
        try? manager.cancel(id: StableID.countdownTimerID)

        // AlarmButton 没有静态便捷成员，必须自己构造（同 AlarmKitScheduler）
        let stop = AlarmButton(text: "停止", textColor: .white, systemImageName: "stop.circle")
        let pause = AlarmButton(text: "暂停", textColor: .white, systemImageName: "pause.fill")
        let resume = AlarmButton(text: "继续", textColor: .white, systemImageName: "play.fill")

        let presentation = AlarmPresentation(
            alert: AlarmPresentation.Alert(title: "倒计时结束", stopButton: stop),
            countdown: AlarmPresentation.Countdown(title: "倒计时", pauseButton: pause),
            paused: AlarmPresentation.Paused(title: "已暂停", resumeButton: resume)
        )

        let attributes = AlarmAttributes(
            presentation: presentation,
            metadata: DingClockAlarmMetadata(
                alarmLabel: "倒计时",
                dayReason: "倒计时结束提醒",
                fireDate: Date().addingTimeInterval(duration)
            ),
            tintColor: .orange
        )

        let configuration = AlarmManager.AlarmConfiguration<DingClockAlarmMetadata>.timer(
            duration: duration,
            attributes: attributes,
            stopIntent: CountdownStoppedIntent(),
            secondaryIntent: nil,
            sound: .default
        )

        _ = try await manager.schedule(id: StableID.countdownTimerID, configuration: configuration)
        Self.log.notice("倒计时已起：\(Int(duration), privacy: .public) 秒")
    }

    func pause() async throws {
        try manager.pause(id: StableID.countdownTimerID)
    }

    func resume() async throws {
        try manager.resume(id: StableID.countdownTimerID)
    }

    func cancel() async throws {
        // 没挂着的倒计时再取消会抛错，但那是正常情况，不该往上冒
        try? manager.cancel(id: StableID.countdownTimerID)
    }

    func stop() async throws {
        try? manager.stop(id: StableID.countdownTimerID)
        try? manager.cancel(id: StableID.countdownTimerID)
    }

    func isActive() async -> Bool {
        ((try? manager.alarms) ?? []).contains { $0.id == StableID.countdownTimerID }
    }
}
#endif
