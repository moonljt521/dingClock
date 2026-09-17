import Foundation

/// 闹钟的重复模式：**只管「一周里哪几天上班」**。
/// 「是否跟着国家放调休」由 `AlarmModel.respectsStateHolidays` 单独控制。
enum RepeatMode: Codable, Equatable, Sendable {
    /// 五天工作制
    case fiveDay
    /// 大小周
    case alternatingBigSmall(anchor: Date, anchorIsSmallWeek: Bool)
    /// 自定义周几（`Calendar` weekday 语义：1=周日 … 7=周六）
    case custom(Set<Int>)
    /// 只响一次，指定具体日期
    case once(Date)

    /// 映射到周模式（「只响一次」没有周模式）
    var weekPattern: WeekPattern? {
        switch self {
        case .fiveDay: return .fiveDay
        case .alternatingBigSmall(let anchor, let isSmall): return .alternatingBigSmall(anchor: anchor, anchorIsSmallWeek: isSmall)
        case .custom(let days): return .custom(days)
        case .once: return nil
        }
    }
}

/// 一个闹钟。
///
/// 注意 `repeatMode` 与 `respectsStateHolidays` 是**正交**的两个维度：
/// - 「工作日（含调休）」= `.fiveDay` + `respectsStateHolidays = true`
/// - 「周一至周五」      = `.fiveDay` + `respectsStateHolidays = false`（旧版 iOS 的行为）
struct AlarmModel: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var hour: Int
    var minute: Int
    var label: String
    var isEnabled: Bool
    var repeatMode: RepeatMode
    /// 是否把国务院法定节假日与调休补班纳入判定
    var respectsStateHolidays: Bool
    var snoozeEnabled: Bool
    /// 提前排期的天数窗口。窗口越大越稳，但会占用更多系统闹钟槽位
    var windowDays: Int
    var createdAt: Date

    init(
        id: UUID = UUID(),
        hour: Int = 7,
        minute: Int = 0,
        label: String = "起床",
        isEnabled: Bool = true,
        repeatMode: RepeatMode = .fiveDay,
        respectsStateHolidays: Bool = true,
        snoozeEnabled: Bool = true,
        windowDays: Int = 21,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.hour = hour
        self.minute = minute
        self.label = label
        self.isEnabled = isEnabled
        self.repeatMode = repeatMode
        self.respectsStateHolidays = respectsStateHolidays
        self.snoozeEnabled = snoozeEnabled
        self.windowDays = windowDays
        self.createdAt = createdAt
    }

    /// 面向用户的一句话描述
    var patternDescription: String {
        switch repeatMode {
        case .fiveDay:
            return respectsStateHolidays ? "工作日（含调休）" : "周一至周五"
        case .alternatingBigSmall:
            return respectsStateHolidays ? "大小周（含调休）" : "大小周"
        case .custom(let days):
            return WeekPattern.customLabel(for: days)
        case .once:
            return "只响一次"
        }
    }

    /// 是否为对标 iOS 27 的「工作日（含调休）」模式
    var isStateScheduleWorkdayMode: Bool {
        if case .fiveDay = repeatMode { return respectsStateHolidays }
        return false
    }

    var timeDescription: String { String(format: "%02d:%02d", hour, minute) }

    /// 该闹钟对应的判定日历（把自身配置翻译成引擎参数）
    func workdayCalendar(holidays: HolidayIndex, overrides: [String: ManualOverride], calendar: Calendar = .current) -> WorkdayCalendar {
        WorkdayCalendar(
            weekPattern: repeatMode.weekPattern ?? .fiveDay,
            holidays: holidays,
            overrides: overrides,
            respectsStateHolidays: respectsStateHolidays,
            calendar: calendar
        )
    }
}
