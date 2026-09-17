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
            return DayPreview(
                key: DateKey.string(date, calendar: calendar),
                date: date,
                kind: kind,
                rings: rings,
                fireDate: rings ? fire : nil
            )
        }
    }

    // MARK: - Private

    private func makeFire(alarm: AlarmModel, fire: Date, kind: DayKind) -> PlannedFire {
        PlannedFire(
            id: StableID.fireSeed(alarmID: alarm.id, fireDate: fire, calendar: calendar),
            uuid: StableID.fireID(alarmID: alarm.id, fireDate: fire, calendar: calendar),
            fireDate: fire,
            dayKind: kind,
            alarmID: alarm.id,
            label: alarm.label
        )
    }

    private func fireTime(on day: Date, hour: Int, minute: Int) -> Date? {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)
    }
}
