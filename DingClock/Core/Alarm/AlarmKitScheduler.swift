import Foundation
import os.log

#if canImport(AlarmKit)
import AlarmKit
import ActivityKit
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

    /// 铃声排期日志：格式探测是否命中全靠它回溯
    private static let log = Logger(subsystem: "com.moonding.dingclock", category: "AlarmKitScheduler")

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
    /// 超了报 `AlarmManager.AlarmError.maximumLimitReached`。
    ///
    /// - Important: 这里**必须精确匹配 domain**。早先用
    ///   `domain.contains("AlarmKit") && code == 0` 兜底，结果把
    ///   「ID 重复」（`AlarmServiceError.invalidInput`）也认成了上限 ——
    ///   于是对账在第一条就 `break`，后面一条都不下发。
    ///   现象就是「新加的闹钟永远不响，旧闹钟一切正常」。
    private func isLimitError(_ error: Error) -> Bool {
        if let e = error as? AlarmManager.AlarmError, e == .maximumLimitReached { return true }
        let ns = error as NSError
        return ns.domain == "com.apple.AlarmKit.Alarm" && ns.code == 0
    }

    func reconcile(plans: [PlannedFire]) async throws {
        limitHit = false
        let desired = Dictionary(plans.map { ($0.uuid, $0) }, uniquingKeysWith: { first, _ in first })

        let existing = (try? manager.alarms) ?? []
        let existingIDs = Set(existing.map(\.id))

        // 1) 取消不再需要的：系统里有、但我们这次不想要的。
        //    保留 ID（倒计时）必须跳过 —— 它不归排期管，掐掉它等于把用户
        //    正在跑的倒计时清了。
        let stale = existing.filter { desired[$0.id] == nil && !StableID.isReserved($0.id) }
        Self.log.notice("[对账] 目标 \(desired.count) 条，系统现有 \(existing.count) 条，待取消 \(stale.count) 条")
        for alarm in stale {
            try? await manager.cancel(id: alarm.id)
        }

        // 2) 只下发系统里**还没有**的 ID。
        //
        //    这一步是必须的，不是优化：AlarmKit 对已存在的 ID 调 `schedule` 会直接抛
        //    `Not scheduling an alarm with a duplicate ID`，而不是覆盖。
        //    早先这里无差别重发全部计划，于是每次刷新都从第一条开始失败。
        //
        //    那"改了铃声怎么生效"？靠 ID 本身：`StableID.appearanceFingerprint`
        //    把标签/铃声/稍后提醒编进了 ID，配置一变 ID 就变 ——
        //    旧 ID 在这一步之前已被取消，新 ID 在这里被当成"缺失的"下发。
        //
        //    按时间升序下发（`desired` 是字典，遍历顺序随机）：撞到数量上限时
        //    先停手，留下的是**最早**的那些，近期响铃一定有保障。
        let pending = desired
            .filter { !existingIDs.contains($0.key) }
            .values
            .sorted { $0.fireDate < $1.fireDate }

        var succeeded = 0
        var failures: [String] = []

        outer: for plan in pending {
            let id = plan.uuid
            // 铃声名格式探测链：带扩展名 → 裸资源名 → 系统默认。
            // AlertSound.named 是否要求带扩展名官方文档没写死，逐级试最稳；
            // 闹钟响不响永远优先于铃声好不好听。
            var lastError: Error?
            for sound in soundCandidates(ringtoneID: plan.ringtoneID) {
                do {
                    let configuration = makeConfiguration(plan: plan, soundName: sound)
                    _ = try await manager.schedule(id: id, configuration: configuration)
                    succeeded += 1
                    continue outer
                } catch {
                    if isLimitError(error) {
                        limitHit = true
                        Self.log.error("[对账] 撞到系统上限，已成功下发 \(succeeded) 条后停手")
                        break outer
                    }
                    lastError = error
                    Self.log.error("[对账] \(id.uuidString, privacy: .public)（\(plan.label, privacy: .public)）用 \(sound ?? "系统默认", privacy: .public) 排期失败：\(String(describing: error), privacy: .public)")
                }
            }
            // 单条失败不再中断整轮 —— 一个闹钟排不上，不该拖垮其余所有闹钟。
            let reason = lastError?.localizedDescription ?? "未知原因"
            failures.append("\(plan.label)（\(plan.fireDate.chineseTimeLabel)）：\(reason)")
        }

        // 全部失败才算真失败，如实抛给上层；部分失败只记日志，界面照常可用。
        if succeeded == 0, !pending.isEmpty {
            throw NSError(
                domain: "DingClock.AlarmKitScheduler", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "\(pending.count) 个响铃一个都没排上：\(failures.first ?? "")"]
            )
        }

        let finalCount = ((try? manager.alarms) ?? []).count
        Self.log.notice("[对账] 完成：本轮下发 \(succeeded)/\(pending.count) 条，失败 \(failures.count) 条，系统内共 \(finalCount) 条")
    }

    func cancelAll() async throws {
        let existing = (try? manager.alarms) ?? []
        for alarm in existing {
            try? await manager.cancel(id: alarm.id)
        }
    }

    func scheduledCount() async throws -> Int {
        ((try? manager.alarms) ?? []).filter { !StableID.isReserved($0.id) }.count
    }

    func scheduledSystemDates() async -> [Date] {
        let alarms = (try? manager.alarms) ?? []
        let dates = alarms
            .filter { !StableID.isReserved($0.id) }
            .compactMap { alarm -> Date? in
                guard case .fixed(let date) = alarm.schedule else { return nil }
                return date
            }
        return dates.sorted()
    }

    // MARK: - 配置

    /// 铃声名的候选序列：
    /// 系统默认 → [nil]；自定义 → ["xxx.caf", "xxx", nil]。
    /// AlertSound.named 的名字格式官方文档只说"sound file"，这里两种都试。
    private func soundCandidates(ringtoneID: String?) -> [String?] {
        guard let name = RingtoneCatalog.soundName(forID: ringtoneID) else { return [nil] }
        return [name + ".caf", name, nil]
    }

    private func makeConfiguration(
        plan: PlannedFire,
        soundName: String?
    ) -> AlarmManager.AlarmConfiguration<DingClockAlarmMetadata> {

        // 标题与「稍后提醒」都取自**这一条**排期，而不是全局参数 ——
        // 多闹钟下每个闹钟的设置必须各归各的。
        let title = LocalizedStringResource(stringLiteral: plan.label)

        // AlarmButton 没有静态便捷成员（.stopButton 之类是不存在的），
        // 必须用 init(text:textColor:systemImageName:) 自己构造。
        let stop = AlarmButton(text: "停止", textColor: .white, systemImageName: "stop.circle")
        let snooze = AlarmButton(text: "稍后提醒", textColor: .white, systemImageName: "zzz")
        let pause = AlarmButton(text: "暂停", textColor: .white, systemImageName: "pause.fill")
        let resume = AlarmButton(text: "继续", textColor: .white, systemImageName: "play.fill")

        let presentation: AlarmPresentation
        let countdownDuration: Alarm.CountdownDuration?

        if plan.snoozeEnabled {
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
            countdownDuration = Alarm.CountdownDuration(preAlert: nil, postAlert: plan.snoozeDuration)
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

        // 铃声：AlarmKit 只给 .default 和 .named(资源名)，没有"无声/仅震动"。
        // 名字由 soundCandidates 探测链给出，这里只负责包装。
        let sound: ActivityKit.AlertConfiguration.AlertSound =
            soundName.map { ActivityKit.AlertConfiguration.AlertSound.named($0) } ?? .default

        return AlarmManager.AlarmConfiguration(
            countdownDuration: countdownDuration,
            schedule: .fixed(plan.fireDate),
            attributes: attributes,
            // 关键：闹钟被关掉时系统会拉起 App 执行这个 Intent，
            // 趁槽位刚空出来把最远端的新闹钟补上 —— 窗口因此能持续前滚
            stopIntent: AlarmStoppedIntent(),
            secondaryIntent: nil,
            sound: sound
        )
    }
}
#endif
