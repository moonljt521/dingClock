import Foundation

/// 用户对某一天的手动标记。存在时**覆盖一切**——
/// 包括国务院的调休安排，因为很多公司并不跟着国家调休走。
struct ManualOverride: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable, CaseIterable {
        case rest   // 这天放假，别响
        case work   // 这天上班，要响

        var label: String {
            switch self {
            case .rest: return "放假"
            case .work: return "上班"
            }
        }
    }

    var kind: Kind
    var note: String = ""

    init(kind: Kind, note: String = "") {
        self.kind = kind
        self.note = note
    }
}

/// 工作日判定引擎。
///
/// 判定优先级（自上而下，先命中先返回）：
///
/// 1. **用户手动标记** —— 最高优先级，可以推翻国家调休
/// 2. **国务院文件**（仅在 `respectsStateHolidays` 为真时生效）
///    - 法定节假日 → 休息
///    - 调休补班日 → 上班
/// 3. **周模式** —— 五天制 / 大小周 / 自定义周几
///
/// 这一条链路就是「先判定日期属性、再决定响不响」的全部实现。
struct WorkdayCalendar: Sendable, Equatable {

    var weekPattern: WeekPattern
    var holidays: HolidayIndex
    /// key 为 `DateKey.string(...)`
    var overrides: [String: ManualOverride]
    /// 是否把国务院放假/调休安排纳入判定
    var respectsStateHolidays: Bool
    var calendar: Calendar

    init(
        weekPattern: WeekPattern = .fiveDay,
        holidays: HolidayIndex = .empty,
        overrides: [String: ManualOverride] = [:],
        respectsStateHolidays: Bool = true,
        calendar: Calendar = .current
    ) {
        self.weekPattern = weekPattern
        self.holidays = holidays
        self.overrides = overrides
        self.respectsStateHolidays = respectsStateHolidays
        self.calendar = calendar
    }

    /// 核心方法：判定某一天的性质
    func kind(for date: Date) -> DayKind {
        let key = DateKey.string(date, calendar: calendar)

        // 1. 手动标记最高优先级
        if let override = overrides[key] {
            switch override.kind {
            case .rest: return .manualRest(note: override.note)
            case .work: return .manualWorkday(note: override.note)
            }
        }

        // 2. 国务院节假日安排
        if respectsStateHolidays {
            if let off = holidays.offDay(on: key) {
                return .statutoryHoliday(name: off.name)
            }
            if let makeup = holidays.makeupWorkday(on: key) {
                return .makeupWorkday(name: makeup.name)
            }
        }

        // 3. 周模式兜底
        return weekPattern.worksByWeekRule(date, calendar: calendar) ? .regularWorkday : .weekend
    }

    /// 简化查询：这天闹钟该不该响
    func isWorkday(_ date: Date) -> Bool { kind(for: date).isWorkday }

    /// 这天有没有任何「特殊安排」（放假、补班或手动标记）
    var hasSpecialArrangements: Bool {
        !overrides.isEmpty || !holidays.loadedYears.isEmpty
    }
}
