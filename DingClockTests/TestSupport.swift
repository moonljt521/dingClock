import Foundation
@testable import DingClock

/// 测试用的固定日历。
///
/// **必须锁定时区**，否则同一份数据在不同机器上算出来的「哪一天是周几」会不一致，
/// 测试就失去了意义。
enum TestCalendar {
    static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        c.locale = Locale(identifier: "zh_CN")
        c.firstWeekday = 2
        return c
    }()

    static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = hour
        comps.minute = minute
        return calendar.date(from: comps)!
    }
}

/// 2026 年国务院办公厅节假日安排的真实数据。
///
/// 直接内嵌而不是读资源文件，是为了让测试**完全自洽**：不受构建配置、
/// Bundle 路径、资源是否被正确拷贝的影响。资源本身另有测试单独校验。
enum TestFixtures {

    static let days2026: [HolidayDay] = [
        // 元旦
        HolidayDay(name: "元旦", date: "2026-01-01", isOffDay: true),
        HolidayDay(name: "元旦", date: "2026-01-02", isOffDay: true),
        HolidayDay(name: "元旦", date: "2026-01-03", isOffDay: true),
        HolidayDay(name: "元旦", date: "2026-01-04", isOffDay: false),
        // 春节
        HolidayDay(name: "春节", date: "2026-02-14", isOffDay: false),
        HolidayDay(name: "春节", date: "2026-02-15", isOffDay: true),
        HolidayDay(name: "春节", date: "2026-02-16", isOffDay: true),
        HolidayDay(name: "春节", date: "2026-02-17", isOffDay: true),
        HolidayDay(name: "春节", date: "2026-02-18", isOffDay: true),
        HolidayDay(name: "春节", date: "2026-02-19", isOffDay: true),
        HolidayDay(name: "春节", date: "2026-02-20", isOffDay: true),
        HolidayDay(name: "春节", date: "2026-02-21", isOffDay: true),
        HolidayDay(name: "春节", date: "2026-02-22", isOffDay: true),
        HolidayDay(name: "春节", date: "2026-02-23", isOffDay: true),
        HolidayDay(name: "春节", date: "2026-02-28", isOffDay: false),
        // 清明节
        HolidayDay(name: "清明节", date: "2026-04-04", isOffDay: true),
        HolidayDay(name: "清明节", date: "2026-04-05", isOffDay: true),
        HolidayDay(name: "清明节", date: "2026-04-06", isOffDay: true),
        // 劳动节
        HolidayDay(name: "劳动节", date: "2026-05-01", isOffDay: true),
        HolidayDay(name: "劳动节", date: "2026-05-02", isOffDay: true),
        HolidayDay(name: "劳动节", date: "2026-05-03", isOffDay: true),
        HolidayDay(name: "劳动节", date: "2026-05-04", isOffDay: true),
        HolidayDay(name: "劳动节", date: "2026-05-05", isOffDay: true),
        HolidayDay(name: "劳动节", date: "2026-05-09", isOffDay: false),
        // 端午节
        HolidayDay(name: "端午节", date: "2026-06-19", isOffDay: true),
        HolidayDay(name: "端午节", date: "2026-06-20", isOffDay: true),
        HolidayDay(name: "端午节", date: "2026-06-21", isOffDay: true),
        // 中秋 / 国庆
        HolidayDay(name: "国庆节", date: "2026-09-20", isOffDay: false),
        HolidayDay(name: "中秋节", date: "2026-09-25", isOffDay: true),
        HolidayDay(name: "中秋节", date: "2026-09-26", isOffDay: true),
        HolidayDay(name: "中秋节", date: "2026-09-27", isOffDay: true),
        HolidayDay(name: "国庆节", date: "2026-10-01", isOffDay: true),
        HolidayDay(name: "国庆节", date: "2026-10-02", isOffDay: true),
        HolidayDay(name: "国庆节", date: "2026-10-03", isOffDay: true),
        HolidayDay(name: "国庆节", date: "2026-10-04", isOffDay: true),
        HolidayDay(name: "国庆节", date: "2026-10-05", isOffDay: true),
        HolidayDay(name: "国庆节", date: "2026-10-06", isOffDay: true),
        HolidayDay(name: "国庆节", date: "2026-10-07", isOffDay: true),
        HolidayDay(name: "国庆节", date: "2026-10-10", isOffDay: false)
    ]

    static func holidayIndex2026() -> HolidayIndex {
        HolidayIndex(days: days2026)
    }

    /// 2026 年全部的调休补班日（周末上班）——这些是最容易睡过头的一天
    static let makeupDays2026 = [
        "2026-01-04", "2026-02-14", "2026-02-28",
        "2026-05-09", "2026-09-20", "2026-10-10"
    ]

    /// 2026 年全部法定放假日
    static var offDays2026: [String] {
        days2026.filter(\.isOffDay).map(\.date)
    }
}
