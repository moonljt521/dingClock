import Foundation

/// 周模式：**抛开节假日，一周里哪几天算上班**。
///
/// 与「是否遵循国务院调休」是两个正交维度——所以「工作日(含调休)」=
/// `.fiveDay` + `respectsStateHolidays = true`，而不是一个独立的模式。
enum WeekPattern: Codable, Equatable, Sendable {
    /// 五天工作制：周一至周五
    case fiveDay
    /// 大小周：小周周六上班、大周双休；周日永远休息
    case alternatingBigSmall(anchor: Date, anchorIsSmallWeek: Bool)
    /// 自定义周几上班。取值用 `Calendar` 的 weekday 语义：1=周日 … 7=周六
    case custom(Set<Int>)

    /// 该日期按周规则是否上班（不含节假日判定）
    func worksByWeekRule(_ date: Date, calendar: Calendar = .current) -> Bool {
        let weekday = calendar.component(.weekday, from: date)
        switch self {
        case .fiveDay:
            return (2...6).contains(weekday)

        case .custom(let days):
            return days.contains(weekday)

        case .alternatingBigSmall(let anchor, let anchorIsSmallWeek):
            if weekday == 1 { return false }            // 周日永远休息
            if (2...6).contains(weekday) { return true } // 周一至周五上班
            // weekday == 7，周六取决于大小周轮换
            let weeks = Self.weekOffset(from: anchor, to: date, calendar: calendar)
            let isSmallWeek = (weeks % 2 == 0) ? anchorIsSmallWeek : !anchorIsSmallWeek
            return isSmallWeek                             // 小周周六上班，大周周六休息
        }
    }

    /// 从 anchor 到 date 相差多少个自然周（以周一为一周起点）
    static func weekOffset(from anchor: Date, to date: Date, calendar: Calendar = .current) -> Int {
        let a = startOfWeek(for: anchor, calendar: calendar)
        let b = startOfWeek(for: date, calendar: calendar)
        let days = calendar.dateComponents([.day], from: a, to: b).day ?? 0
        return Int((Double(days) / 7.0).rounded())
    }

    /// 取所在周的周一（用 `Calendar` 计算，自动处理不同地区的周起始日）
    static func startOfWeek(for date: Date, calendar: Calendar = .current) -> Date {
        var cal = calendar
        cal.firstWeekday = 2 // 周一
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return cal.date(from: comps) ?? cal.startOfDay(for: date)
    }

    var label: String {
        switch self {
        case .fiveDay: return "周一至周五"
        case .alternatingBigSmall: return "大小周"
        case .custom(let days): return WeekPattern.customLabel(for: days)
        }
    }

    /// 自定义周几的中文名，按一周顺序排列
    static func customLabel(for days: Set<Int>) -> String {
        let names = [2: "一", 3: "二", 4: "三", 5: "四", 6: "五", 7: "六", 1: "日"]
        let ordered = days.sorted { lhs, rhs in
            let l = lhs == 1 ? 8 : lhs, r = rhs == 1 ? 8 : rhs
            return l < r
        }
        guard !ordered.isEmpty else { return "未选择" }
        if ordered.count == 7 { return "每天" }
        return "周" + ordered.compactMap { names[$0] }.joined(separator: "、")
    }
}
