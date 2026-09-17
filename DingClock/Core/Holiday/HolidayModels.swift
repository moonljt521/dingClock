import Foundation

/// 单个特殊日期：来自国务院办公厅《关于部分节假日安排的通知》。
/// 数据源（holiday-cn）已把「法定节假日休息」与「调休补班上班」两类都标出来了。
struct HolidayDay: Codable, Hashable, Sendable {
    /// 节日名称，如「春节」「国庆节」
    let name: String
    /// ISO 8601 日期字符串，如 "2026-02-15"
    let date: String
    /// true = 放假休息（法定节假日）；false = 调休上班（周末补班）
    let isOffDay: Bool
}

/// 某一年的完整节假日安排
struct HolidayYearData: Codable, Sendable {
    let year: Int
    /// 所依据的国务院文件网址
    let papers: [String]?
    let days: [HolidayDay]
}

/// 日期键工具：统一用 "yyyy-MM-dd" 作为索引键。
///
/// 注意必须锁定 POSIX 语言环境，否则在部分区域设置下会输出非公历字符串。
enum DateKey {
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func string(_ date: Date, calendar: Calendar = .current) -> String {
        var f = formatter
        f.timeZone = calendar.timeZone
        return f.string(from: date)
    }

    /// 精确到分钟的时间戳键，如 "2026-10-10-07-30"。
    /// 系统闹钟 ID 必须用它而不是日期键 —— 否则同一天改时间会派生出同一个 ID。
    static func timestamp(_ date: Date, calendar: Calendar = .current) -> String {
        var f = timestampFormatter
        f.timeZone = calendar.timeZone
        return f.string(from: date)
    }

    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd-HH-mm"
        return f
    }()

    static func date(_ key: String, calendar: Calendar = .current) -> Date? {
        var f = formatter
        f.timeZone = calendar.timeZone
        return f.date(from: key)
    }
}
