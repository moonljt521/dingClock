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
    /// 铃声标识。nil / 未知值 = 系统默认（AlarmKit 没有"无声"选项，见 RingtoneCatalog）
    var ringtoneID: String?
    /// 提前排期的天数窗口。窗口越大越稳，但会占用更多系统闹钟槽位
    var windowDays: Int
    var createdAt: Date

    /// 「仅这次关闭」：精确到分钟地跳过**一次**响铃，闹钟本身保持开启。
    ///
    /// 和 `isEnabled = false` 的区别是语义：前者是"今天多睡一天，明天照常"，
    /// 后者是"以后都别响了"。两者在列表里都表现为开关是关的（见 `isOn`），
    /// 但只有前者会自动恢复。
    ///
    /// 到点之后由 `AlarmStore` 自动清空，所以不需要用户再去手动打开。
    var skippedFireDate: Date?

    init(
        id: UUID = UUID(),
        hour: Int = 7,
        minute: Int = 0,
        label: String = "起床",
        isEnabled: Bool = true,
        repeatMode: RepeatMode = .fiveDay,
        respectsStateHolidays: Bool = true,
        snoozeEnabled: Bool = true,
        ringtoneID: String? = nil,
        windowDays: Int = 21,
        createdAt: Date = Date(),
        skippedFireDate: Date? = nil
    ) {
        self.id = id
        self.hour = hour
        self.minute = minute
        self.label = label
        self.isEnabled = isEnabled
        self.repeatMode = repeatMode
        self.respectsStateHolidays = respectsStateHolidays
        self.snoozeEnabled = snoozeEnabled
        self.ringtoneID = ringtoneID
        self.windowDays = windowDays
        self.createdAt = createdAt
        self.skippedFireDate = skippedFireDate
    }

    /// 用户视角的「这个闹钟现在开着吗」。
    ///
    /// 「仅这次关闭」之后 `isEnabled` 仍是 true，但对用户来说它就是关的 ——
    /// 列表上的开关读这个属性，而不是直接读 `isEnabled`。
    var isOn: Bool { isEnabled && skippedFireDate == nil }

    /// 这次响铃是否被「仅这次关闭」跳过了（精确到分钟）
    func skips(_ fireDate: Date, calendar: Calendar = .current) -> Bool {
        guard let skipped = skippedFireDate else { return false }
        return calendar.isDate(fireDate, equalTo: skipped, toGranularity: .minute)
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
