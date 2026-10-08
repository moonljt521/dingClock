import Foundation

/// 一次已排定的响铃
struct PlannedFire: Identifiable, Equatable, Sendable {
    /// 稳定标识（用于去重与对账）
    var id: String
    /// 交给系统的系统级闹钟 ID
    var uuid: UUID
    var fireDate: Date
    var dayKind: DayKind
    var alarmID: UUID
    var label: String
    /// 该次响铃用的铃声资源名；nil = 系统默认
    var ringtoneID: String?
    /// 该次响铃所属闹钟是否启用「稍后提醒」。
    ///
    /// 刻意随每次响铃一起下发，而不是在排期时传一个全局参数 ——
    /// 多个闹钟各自的开关心智是独立的，用全局参数会让「A 关了稍后提醒」
    /// 被「B 开着」覆盖掉。
    var snoozeEnabled: Bool
    /// 稍后提醒时长（秒）
    var snoozeDuration: TimeInterval

    var dayKey: String { id }
}

/// 「响铃日历」的一格：某天到底响不响，为什么
struct DayPreview: Identifiable, Equatable, Sendable {
    var id: String { key }
    var key: String
    var date: Date
    var kind: DayKind
    /// 综合闹钟开关后的最终结论
    var rings: Bool
    /// 若响，几点响
    var fireDate: Date?
}

/// 排期引擎：把「日期属性判定」翻译成「未来若干天的具体响铃时刻」。
///
/// 这是整个方案里最关键的一步。因为 AlarmKit 的重复规则只支持
/// 「每周固定周几」或「不重复」，无法表达「跳过法定节假日」，
/// 所以我们必须把工作日**逐个展开成具体日期**，一个一个排进去。
struct SchedulePlanner: Sendable {

    /// 「稍后提醒」时长。AlarmKit 的稍后提醒是固定时长，不做每闹钟可调 ——
    /// 多一个旋钮，用户也不会去调，默认 9 分钟是手机闹钟的通用值。
    static let defaultSnoozeDuration: TimeInterval = 9 * 60

    var calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    /// 计算一个闹钟在未来窗口内所有真正会响的时刻
    /// - Parameters:
    ///   - now: 当前时间，早于它的时刻会被跳过
    ///   - maxCount: 只取前 N 个（列表页展示「下次响铃」时用）
    func fires(
        for alarm: AlarmModel,
        workday: WorkdayCalendar,
        from now: Date = Date(),
        maxCount: Int? = nil
    ) -> [PlannedFire] {
        guard alarm.isEnabled else { return [] }

        // 「只响一次」：用户显式指定了日期，就照响不误（UI 会另行提示当天是否撞上节假日）
        if case .once(let day) = alarm.repeatMode {
            guard let fire = fireTime(on: day, hour: alarm.hour, minute: alarm.minute), fire > now else { return [] }
            guard !alarm.skips(fire, calendar: calendar) else { return [] }
            return [makeFire(alarm: alarm, fire: fire, kind: workday.kind(for: fire))]
        }

        let startDay = calendar.startOfDay(for: now)
        let window = max(1, alarm.windowDays)
        var result: [PlannedFire] = []

        // 多算一天，保证「今天已经过了响铃时间」时窗口仍然填满
        for offset in 0...(window + 1) {
            guard let day = calendar.date(byAdding: .day, value: offset, to: startDay) else { continue }
            let kind = workday.kind(for: day)
            guard kind.isWorkday else { continue }
            guard let fire = fireTime(on: day, hour: alarm.hour, minute: alarm.minute), fire > now else { continue }
            // 「仅这次关闭」：这一天不排，但窗口继续往后铺
            guard !alarm.skips(fire, calendar: calendar) else { continue }
            result.append(makeFire(alarm: alarm, fire: fire, kind: kind))
            if let maxCount, result.count >= maxCount { break }
        }
        return result
    }

    /// 只要下一次响铃（列表页用）
    func nextFire(for alarm: AlarmModel, workday: WorkdayCalendar, from now: Date = Date()) -> PlannedFire? {
        fires(for: alarm, workday: workday, from: now, maxCount: 1).first
    }

    /// 逐日预告：含**不响**的日子，用于「未来 30 天响铃日历」
    func preview(
        for alarm: AlarmModel,
        workday: WorkdayCalendar,
        from day: Date = Date(),
        days: Int = 30
    ) -> [DayPreview] {
        let startDay = calendar.startOfDay(for: day)
        return (0..<days).compactMap { offset -> DayPreview? in
            guard let date = calendar.date(byAdding: .day, value: offset, to: startDay) else { return nil }
            let kind = workday.kind(for: date)

            var shouldRing: Bool
            switch alarm.repeatMode {
            case .once(let onceDay):
                shouldRing = calendar.isDate(onceDay, inSameDayAs: date)
            default:
                shouldRing = kind.isWorkday
            }

            let rings = shouldRing && alarm.isEnabled
            let fire = fireTime(on: date, hour: alarm.hour, minute: alarm.minute)
            // 「仅这次关闭」的那一天，日历上如实显示成不响
            let skipped = fire.map { alarm.skips($0, calendar: calendar) } ?? false
            return DayPreview(
                key: DateKey.string(date, calendar: calendar),
                date: date,
                kind: kind,
                rings: rings && !skipped,
                fireDate: (rings && !skipped) ? fire : nil
            )
        }
    }

    // MARK: - Private

    private func makeFire(alarm: AlarmModel, fire: Date, kind: DayKind) -> PlannedFire {
        let appearance = StableID.appearanceFingerprint(
            label: alarm.label,
            ringtoneID: alarm.ringtoneID,
            snoozeEnabled: alarm.snoozeEnabled
        )
        return PlannedFire(
            id: StableID.fireSeed(alarmID: alarm.id, fireDate: fire, appearance: appearance, calendar: calendar),
            uuid: StableID.fireID(alarmID: alarm.id, fireDate: fire, appearance: appearance, calendar: calendar),
            fireDate: fire,
            dayKind: kind,
            alarmID: alarm.id,
            label: alarm.label,
            ringtoneID: alarm.ringtoneID,
            snoozeEnabled: alarm.snoozeEnabled,
            snoozeDuration: SchedulePlanner.defaultSnoozeDuration
        )
    }

    private func fireTime(on day: Date, hour: Int, minute: Int) -> Date? {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)
    }
}
