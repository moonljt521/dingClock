import Foundation

/// 把「按年 JSON」摊平成 `日期 -> 特殊日` 的索引，让判定变成 O(1) 查表。
///
/// 设计要点：这里**不做任何业务判断**，只负责「这天在国务院文件里是什么」。
/// 什么算「要上班」由 `WorkdayCalendar` 决定，两层分开才好测试。
struct HolidayIndex: Sendable, Equatable {

    private var map: [String: HolidayDay] = [:]

    /// 已装载数据的年份，用于在 UI 上提示「数据覆盖到哪一年」
    private(set) var loadedYears: Set<Int> = []

    static let empty = HolidayIndex()

    init() {}

    init(records: [HolidayYearData]) {
        for r in records { merge(r) }
    }

    init(days: [HolidayDay]) {
        for d in days { map[d.date] = d }
        loadedYears = Set(days.compactMap { Int($0.date.prefix(4)) })
    }

    mutating func merge(_ record: HolidayYearData) {
        // 国务院还没发布该年通知时，days 为空。此时**不要**把它算作「已覆盖」，
        // 否则会在设置页谎报数据范围，掩盖「这一年还没数据」这个事实。
        guard !record.days.isEmpty else { return }
        for d in record.days { map[d.date] = d }
        loadedYears.insert(record.year)
    }

    mutating func merge(_ records: [HolidayYearData]) {
        for r in records { merge(r) }
    }

    /// 该日期是否为「法定节假日（放假）」
    func offDay(on key: String) -> HolidayDay? {
        guard let d = map[key], d.isOffDay else { return nil }
        return d
    }

    /// 该日期是否为「调休补班日（周末上班）」
    func makeupWorkday(on key: String) -> HolidayDay? {
        guard let d = map[key], !d.isOffDay else { return nil }
        return d
    }

    /// 该日期是否有特殊标记（不论放假还是补班）
    func special(on key: String) -> HolidayDay? { map[key] }

    /// 这天有没有数据可查（用于区分「确认是普通日」和「数据缺口」）
    func hasCoverage(calendar: Calendar = .current, around date: Date) -> Bool {
        loadedYears.contains(calendar.component(.year, from: date))
    }

    var coverageDescription: String {
        guard !loadedYears.isEmpty else { return "未装载节假日数据" }
        let sorted = loadedYears.sorted()
        guard let first = sorted.first, let last = sorted.last else { return "未装载节假日数据" }
        return first == last ? "\(first) 年" : "\(first)–\(last) 年"
    }
}
