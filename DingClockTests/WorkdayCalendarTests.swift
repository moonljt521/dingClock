import XCTest
@testable import DingClock

/// 工作日判定引擎的测试。
///
/// 这组测试要证明的就是一句话：**该响的日子一定响，不该响的日子一定不响。**
final class WorkdayCalendarTests: XCTestCase {

    private let cal = TestCalendar.calendar

    private func makeCalendar(
        pattern: WeekPattern = .fiveDay,
        respectsStateHolidays: Bool = true,
        overrides: [String: ManualOverride] = [:]
    ) -> WorkdayCalendar {
        WorkdayCalendar(
            weekPattern: pattern,
            holidays: TestFixtures.holidayIndex2026(),
            overrides: overrides,
            respectsStateHolidays: respectsStateHolidays,
            calendar: cal
        )
    }

    private func date(_ key: String) -> Date {
        DateKey.date(key, calendar: cal)!
    }

    // MARK: - 基础判定

    func testRegularWeekdayIsWorkday() {
        // 2026-09-17 周四
        XCTAssertEqual(makeCalendar().kind(for: TestCalendar.date(2026, 9, 17)), .regularWorkday)
    }

    func testRegularWeekendIsRest() {
        // 2026-09-19 周六，未被调休
        XCTAssertEqual(makeCalendar().kind(for: TestCalendar.date(2026, 9, 19)), .weekend)
    }

    /// 法定节假日落在周中——旧版闹钟最容易照响的一天
    func testStatutoryHolidayOnWeekdayIsSilent() {
        let kind = makeCalendar().kind(for: TestCalendar.date(2026, 10, 1)) // 周四，国庆
        XCTAssertEqual(kind, .statutoryHoliday(name: "国庆节"))
        XCTAssertFalse(kind.isWorkday)
    }

    // MARK: - 核心诉求：调休补班日必须响

    func testMakeupSaturdayRings() {
        // 2026-10-10 周六，国庆调休补班
        let kind = makeCalendar().kind(for: TestCalendar.date(2026, 10, 10))
        XCTAssertEqual(kind, .makeupWorkday(name: "国庆节"))
        XCTAssertTrue(kind.isWorkday, "调休补班的周六必须响铃，否则就会睡过头——这正是本次开发的核心诉求")
    }

    func testAll2026MakeupDaysRing() {
        let calendar = makeCalendar()
        for key in TestFixtures.makeupDays2026 {
            let day = date(key)
            XCTAssertTrue(calendar.isWorkday(day), "\(key) 是国务院发布的调休补班日，必须响")
        }
    }

    func testAll2026StatutoryHolidaysAreSilent() {
        let calendar = makeCalendar()
        for key in TestFixtures.offDays2026 {
            let day = date(key)
            XCTAssertFalse(calendar.isWorkday(day), "\(key) 是法定放假日，不该响")
        }
    }

    /// 调休补班日必然落在周末；法定假日必然包含周中。若数据本身不满足，
    /// 说明这条测试链路没意义（而不是撞上了巧合）。
    func testMakeupDaysReallyFallOnWeekends() {
        for key in TestFixtures.makeupDays2026 {
            let weekday = cal.component(.weekday, from: date(key))
            XCTAssertTrue(weekday == 1 || weekday == 7, "\(key) 应该落在周末，否则它不叫调休补班")
        }
    }

    // MARK: - 「跟随国务院」开关

    func testIgnoringStateHolidaysFallsBackToWeekPattern() {
        let calendar = makeCalendar(respectsStateHolidays: false)
        // 补班的周六不再响，退回旧行为
        XCTAssertEqual(calendar.kind(for: TestCalendar.date(2026, 10, 10)), .weekend)
        // 国庆当天的周四反而会照响
        XCTAssertEqual(calendar.kind(for: TestCalendar.date(2026, 10, 1)), .regularWorkday)
    }

    // MARK: - 手动标记的优先级

    func testManualWorkOverrideBeatsStatutoryHoliday() {
        let overrides = ["2026-10-01": ManualOverride(kind: .work, note: "值班")]
        let calendar = makeCalendar(overrides: overrides)
        XCTAssertEqual(calendar.kind(for: TestCalendar.date(2026, 10, 1)), .manualWorkday(note: "值班"))
        XCTAssertTrue(calendar.isWorkday(TestCalendar.date(2026, 10, 1)))
    }

    /// 很多公司（尤其是大小周的公司）并不跟着国家调休走
    func testManualRestOverrideBeatsMakeupWorkday() {
        let overrides = ["2026-10-10": ManualOverride(kind: .rest, note: "公司自行放假")]
        let calendar = makeCalendar(overrides: overrides)
        XCTAssertEqual(calendar.kind(for: TestCalendar.date(2026, 10, 10)), .manualRest(note: "公司自行放假"))
        XCTAssertFalse(calendar.isWorkday(TestCalendar.date(2026, 10, 10)))
    }

    func testManualOverrideWorksEvenWhenIgnoringStateHolidays() {
        let overrides = ["2026-09-19": ManualOverride(kind: .work)]
        let calendar = makeCalendar(respectsStateHolidays: false, overrides: overrides)
        XCTAssertTrue(calendar.isWorkday(TestCalendar.date(2026, 9, 19)))
    }

    // MARK: - 大小周

    func testAlternatingBigSmallWeek() {
        // 以 2026-09-05（周六）为小周锚点
        let anchor = TestCalendar.date(2026, 9, 5)
        let pattern = WeekPattern.alternatingBigSmall(anchor: anchor, anchorIsSmallWeek: true)
        let calendar = makeCalendar(pattern: pattern, respectsStateHolidays: false)

        XCTAssertTrue(calendar.isWorkday(TestCalendar.date(2026, 9, 5)), "小周周六要上班")
        XCTAssertFalse(calendar.isWorkday(TestCalendar.date(2026, 9, 12)), "大周周六休息")
        XCTAssertTrue(calendar.isWorkday(TestCalendar.date(2026, 9, 19)), "又轮到小周，周六上班")
        XCTAssertFalse(calendar.isWorkday(TestCalendar.date(2026, 9, 6)), "周日永远休息")
        XCTAssertTrue(calendar.isWorkday(TestCalendar.date(2026, 9, 7)), "周一照常上班")
    }

    func testAlternatingBigSmallWeekWhenSmallWeekIsSecond() {
        // anchorIsSmallWeek = false 时奇偶应当反转
        let anchor = TestCalendar.date(2026, 9, 5)
        let pattern = WeekPattern.alternatingBigSmall(anchor: anchor, anchorIsSmallWeek: false)
        let calendar = makeCalendar(pattern: pattern, respectsStateHolidays: false)

        XCTAssertFalse(calendar.isWorkday(TestCalendar.date(2026, 9, 5)), "锚点是大周，周六休息")
        XCTAssertTrue(calendar.isWorkday(TestCalendar.date(2026, 9, 12)), "两周后是小周，周六上班")
    }

    // MARK: - 自定义周几

    func testCustomWeekdays() {
        let calendar = makeCalendar(pattern: .custom([2, 4, 6]), respectsStateHolidays: false)
        XCTAssertTrue(calendar.isWorkday(TestCalendar.date(2026, 9, 14)), "周一")
        XCTAssertFalse(calendar.isWorkday(TestCalendar.date(2026, 9, 15)), "周二没选")
        XCTAssertTrue(calendar.isWorkday(TestCalendar.date(2026, 9, 16)), "周三")
        XCTAssertFalse(calendar.isWorkday(TestCalendar.date(2026, 9, 20)), "周日没选")
    }

    // MARK: - 边界

    /// 数据没有覆盖到的年份应当**优雅降级到周模式**，既不崩、也不乱响
    func testUnknownYearFallsBackToWeekPattern() {
        let calendar = makeCalendar()
        XCTAssertFalse(calendar.holidays.hasCoverage(calendar: cal, around: TestCalendar.date(2028, 1, 3)))
        XCTAssertEqual(calendar.kind(for: TestCalendar.date(2028, 1, 3)), .regularWorkday) // 周一
        XCTAssertEqual(calendar.kind(for: TestCalendar.date(2028, 1, 1)), .weekend)        // 周六
    }

    /// 跨年边界：2026-12-31 之后没有 2027 数据时也应正常判定
    func testYearBoundaryDoesNotCrash() {
        let calendar = makeCalendar()
        _ = calendar.kind(for: TestCalendar.date(2026, 12, 31))
        _ = calendar.kind(for: TestCalendar.date(2027, 1, 1))
        XCTAssertFalse(calendar.holidays.loadedYears.isEmpty)
    }

    func testCoverageDescriptionReflectsLoadedYears() {
        XCTAssertEqual(TestFixtures.holidayIndex2026().coverageDescription, "2026 年")
        XCTAssertEqual(HolidayIndex.empty.coverageDescription, "未装载节假日数据")
    }
}
