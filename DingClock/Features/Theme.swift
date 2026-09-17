import SwiftUI

/// 统一的视觉语言：**响铃 = 实色；静音 = 灰**。
/// 「调休补班」单独用橙色 —— 它是旧版闹钟最容易漏掉、也是最容易让人睡过头的一天。
enum Palette {
    static let workday = Color.blue
    static let makeup = Color.orange
    static let manual = Color.teal
    static let rest = Color.gray
    static let holiday = Color.purple

    static func tint(for kind: DayKind) -> Color {
        switch kind {
        case .regularWorkday: return workday
        case .makeupWorkday: return makeup
        case .manualWorkday: return manual
        case .statutoryHoliday: return holiday
        case .weekend, .manualRest: return rest
        }
    }

    static func symbol(for kind: DayKind) -> String {
        switch kind {
        case .regularWorkday: return "briefcase.fill"
        case .makeupWorkday: return "exclamationmark.triangle.fill"
        case .weekend: return "moon.zzz.fill"
        case .statutoryHoliday: return "party.popper.fill"
        case .manualWorkday: return "hand.raised.fill"
        case .manualRest: return "hand.raised.slash.fill"
        }
    }
}

extension DayKind {
    var tint: Color { Palette.tint(for: self) }
    var symbolName: String { Palette.symbol(for: self) }
}

extension Date {
    /// 「9月17日 周四」
    func chineseDayLabel(withWeekday: Bool = true) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = withWeekday ? "M月d日 EEEE" : "M月d日"
        return f.string(from: self)
    }

    /// 「周四」
    var chineseWeekday: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "EEEE"
        return f.string(from: self)
    }

    var chineseMonthTitle: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy年M月"
        return f.string(from: self)
    }

    /// 相对时间，如「还有 8 小时」「明天 07:00」
    func relativeDescription(from now: Date = Date(), calendar: Calendar = .current) -> String {
        let dayDiff = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: now),
            to: calendar.startOfDay(for: self)
        ).day ?? 0

        let time = {
            let f = DateFormatter()
            f.locale = Locale(identifier: "zh_CN")
            f.dateFormat = "HH:mm"
            return f.string(from: self)
        }()

        switch dayDiff {
        case 0: return "今天 \(time)"
        case 1: return "明天 \(time)"
        case 2: return "后天 \(time)"
        default: return "\(chineseDayLabel()) \(time)"
        }
    }
}

/// 一周的日序首字，索引 = `Calendar` 的 weekday - 1
enum WeekdaySymbols {
    static let chinese = ["日", "一", "二", "三", "四", "五", "六"]
    static func chinese(forWeekday weekday: Int) -> String {
        chinese[max(0, min(6, weekday - 1))]
    }
}
