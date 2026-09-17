import Foundation

#if canImport(AlarmKit)
import AlarmKit
import SwiftUI

// DingClockAlarmMetadata 定义在 Shared/ 下，主 App 与 Widget 共用。

/// 真实响铃后端：基于 iOS 26 的 AlarmKit。
///
/// AlarmKit 是苹果第一次把**系统级闹钟**开放给第三方——它能突破静音模式与专注模式、
/// 抢占锁屏与灵动岛，权限规格和系统时钟 App 同级。这是唯一能真正满足
/// 「把用户叫醒」的技术路径。
///
/// ## 为什么必须逐个日期排
/// AlarmKit 的重复规则只有两种：`.weekly([周几])` 或 `.never`，**没有任何「日期属性」概念**。
/// 所以「跳过法定节假日」无法靠一条重复规则表达，只能由 `SchedulePlanner`
/// 把工作日展开成具体日期，再 `schedule(.fixed(日期))` 一个一个排进去。
///
/// ## 为什么对账要幂等
/// 窗口会随 App 每次进入前台而滚动刷新。ID 用 `StableID.fireID` 由
/// 「闹钟 ID + 日期」确定性派生，因此重复下发天然幂等，不会堆出重复闹钟。
///
/// - Important: 本文件只在 `canImport(AlarmKit)` 时参与编译。
///   在 Xcode 26 下 API 细节（尤其是按钮与 intent 参数）需要真机跑一遍确认。
@available(iOS 26.0, *)
final class AlarmKitScheduler: AlarmScheduling, @unchecked Sendable {

    private var manager: AlarmManager { AlarmManager.shared }

    var isSupported: Bool { true }
    var backendName: String { "AlarmKit（系统级闹钟）" }
    var backendNote: String {
        "已接入系统闹钟：可突破静音模式与专注模式，锁屏与灵动岛同步显示。"
    }

    // MARK: - 授权

    func authorizationState() async -> AlarmAuthState {
        switch manager.authorizationState {
        case .authorized: return .authorized
        case .denied: return .denied
        case .notDetermined: return .notDetermined
        @unknown default: return .notDetermined
        }
    }

    @discardableResult
    func requestAuthorization() async throws -> Bool {
        let state = try await manager.requestAuthorization()
        return state == .authorized
    }

    // MARK: - 对账

    /// 上次对账是否撞到了系统的同时闹钟数上限
    private(set) var limitHit = false

    /// 官方 FAQ：AlarmKit 没有固定的闹钟数上限，设备会按状态动态限制，
    /// 超了报 maximumLimitReached（对应 NSError domain=com.apple.AlarmKit.Alarm, code=0）
    private func isLimitError(_ error: Error) -> Bool {
        if let e = error as? AlarmManager.AlarmError, e == .maximumLimitReached { return true }
        let ns = error as NSError
        return ns.domain.contains("AlarmKit") && ns.code == 0
    }

    func reconcile(plans: [PlannedFire], spec: AlarmPresentationSpec) async throws {
        limitHit = false
        let desired = Dictionary(plans.map { ($0.uuid, $0) }, uniquingKeysWith: { first, _ in first })

        // 1) 取消不再需要的：系统里有、但我们这次不想要的
        let existing = (try? manager.alarms) ?? []
        for alarm in existing where desired[alarm.id] == nil {
            try? await manager.cancel(id: alarm.id)
        }

        // 2) 下发缺失的。撞到数量上限就停手 —— plans 已按时间升序，
        //    所以留下的是最早的那些，近期响铃一定有保障。
        for (id, plan) in desired {
            do {
                let configuration = makeConfiguration(plan: plan, spec: spec)
                _ = try await manager.schedule(id: id, configuration: configuration)
            } catch {
                if isLimitError(error) {
                    limitHit = true
                    break
                }
                throw error
            }
        }
    }

    func cancelAll() async throws {
        let existing = (try? manager.alarms) ?? []
        for alarm in existing {
            try? await manager.cancel(id: alarm.id)
        }
    }

    func scheduledCount() async throws -> Int {
        ((try? manager.alarms) ?? []).count
    }

    func scheduledSystemDates() async -> [Date] {
        let alarms = (try? manager.alarms) ?? []
        let dates = alarms.compactMap { alarm -> Date? in
            guard case .fixed(let date) = alarm.schedule else { return nil }
            return date
        }
        return dates.sorted()
    }

    // MARK: - 配置

    private func makeConfiguration(
        plan: PlannedFire,
        spec: AlarmPresentationSpec
    ) -> AlarmManager.AlarmConfiguration<DingClockAlarmMetadata> {

        let title = LocalizedStringResource(stringLiteral: plan.label)

        // AlarmButton 没有静态便捷成员（.stopButton 之类是不存在的），
        // 必须用 init(text:textColor:systemImageName:) 自己构造。
        let stop = AlarmButton(text: "停止", textColor: .white, systemImageName: "stop.circle")
        let snooze = AlarmButton(text: "稍后提醒", textColor: .white, systemImageName: "zzz")
        let pause = AlarmButton(text: "暂停", textColor: .white, systemImageName: "pause.fill")
        let resume = AlarmButton(text: "继续", textColor: .white, systemImageName: "play.fill")

        let presentation: AlarmPresentation
        let countdownDuration: Alarm.CountdownDuration?

        if spec.snoozeEnabled {
            // 不用 init(title:secondaryButton:secondaryButtonBehavior:) —— 那个要 iOS 26.1+，
            // 用带 stopButton 的版本可以贴着 iOS 26.0
            let alert = AlarmPresentation.Alert(
                title: title,
                stopButton: stop,
                secondaryButton: snooze,
                secondaryButtonBehavior: .countdown
            )
            presentation = AlarmPresentation(
                alert: alert,
                countdown: AlarmPresentation.Countdown(title: title, pauseButton: pause),
                paused: AlarmPresentation.Paused(title: "已暂停", resumeButton: resume)
            )
            countdownDuration = Alarm.CountdownDuration(preAlert: nil, postAlert: spec.snoozeDuration)
        } else {
            presentation = AlarmPresentation(
                alert: AlarmPresentation.Alert(title: title, stopButton: stop)
            )
            countdownDuration = nil
        }

        let attributes = AlarmAttributes(
            presentation: presentation,
            metadata: DingClockAlarmMetadata(
                alarmLabel: plan.label,
                dayReason: plan.dayKind.reason,
                fireDate: plan.fireDate
            ),
            tintColor: .orange
        )

        return AlarmManager.AlarmConfiguration(
            countdownDuration: countdownDuration,
            schedule: .fixed(plan.fireDate),
            attributes: attributes,
            // 关键：闹钟被关掉时系统会拉起 App 执行这个 Intent，
            // 趁槽位刚空出来把最远端的新闹钟补上 —— 窗口因此能持续前滚
            stopIntent: AlarmStoppedIntent(),
            secondaryIntent: nil,
            sound: .default
        )
    }
}
#endif
