import XCTest
@testable import DingClock

/// 排期引擎的测试。
///
/// `.fiveDay + respectsStateHolidays` 就是「工作日（含调休）」——
/// 也就是 iOS 27 时钟 App 新增的那个模式。这里验证它真的能跳过节假日、
/// 又不会漏掉调休补班。
final class SchedulePlannerTests: XCTestCase {

    private let cal = TestCalendar.calendar

    private func makeCalendar(respectsStateHolidays: Bool = true) -> WorkdayCalendar {
        WorkdayCalendar(
            weekPattern: .fiveDay,
            holidays: TestFixtures.holidayIndex2026(),
            overrides: [:],
            respectsStateHolidays: respectsStateHolidays,
            calendar: cal
        )
    }

    private func planner() -> SchedulePlanner { SchedulePlanner(calendar: cal) }

    private func keys(_ fires: [PlannedFire]) -> [String] {
        fires.map { DateKey.string($0.fireDate, calendar: cal) }
    }

    // MARK: - 基本约束

    func testPlanOnlyContainsWorkdaysAtTheRightTime() {
        let alarm = AlarmModel(hour: 7, minute: 30, windowDays: 30)
        let workday = makeCalendar()
        let from = TestCalendar.date(2026, 9, 17, 6, 0)

        let fires = planner().fires(for: alarm, workday: workday, from: from)

        XCTAssertFalse(fires.isEmpty)
        for fire in fires {
            XCTAssertTrue(workday.isWorkday(fire.fireDate), "\(fire.id) 那天不该响")
            XCTAssertGreaterThan(fire.fireDate, from, "\(fire.id) 已经过去了，不该再排")
            XCTAssertEqual(cal.component(.hour, from: fire.fireDate), 7)
            XCTAssertEqual(cal.component(.minute, from: fire.fireDate), 30)
        }
    }

    func testDisabledAlarmProducesNoFires() {
        var alarm = AlarmModel(hour: 7, minute: 0)
        alarm.isEnabled = false
        XCTAssertTrue(planner().fires(for: alarm, workday: makeCalendar()).isEmpty)
    }

    func testPastTimeTodayIsSkipped() {
        let alarm = AlarmModel(hour: 7, minute: 0, windowDays: 14)
        let now = TestCalendar.date(2026, 9, 17, 7, 1) // 周四 07:01，今天的 07:00 已过
        let fires = planner().fires(for: alarm, workday: makeCalendar(), from: now)
        XCTAssertFalse(
            fires.contains { cal.isDate($0.fireDate, inSameDayAs: now) },
            "今天 07:00 已过，不该再排"
        )
    }

    func testFutureTimeTodayIsKept() {
        let alarm = AlarmModel(hour: 7, minute: 0, windowDays: 14)
        let now = TestCalendar.date(2026, 9, 17, 6, 0) // 还没到 07:00
        let fires = planner().fires(for: alarm, workday: makeCalendar(), from: now)
        XCTAssertTrue(
            fires.contains { cal.isDate($0.fireDate, inSameDayAs: now) },
            "今天 07:00 还没到，应该排进去"
        )
    }

    func testWindowLengthIsRespected() {
        let alarm = AlarmModel(hour: 7, minute: 0, windowDays: 7)
        let from = TestCalendar.date(2026, 9, 17, 0, 1)
        let fires = planner().fires(for: alarm, workday: makeCalendar(), from: from)
        let last = try? XCTUnwrap(fires.last)
        guard let last else { return XCTFail("应该有排期") }
        let span = cal.dateComponents(
            [.day],
            from: cal.startOfDay(for: from),
            to: cal.startOfDay(for: last.fireDate)
        ).day ?? 0
        XCTAssertLessThanOrEqual(span, 9, "7 天窗口不该排到 9 天以后")
    }

    // MARK: - 长假场景

    /// 国庆 7 天假期期间一次都不该响
    func testNationalDayHolidayProducesNoFires() {
        let alarm = AlarmModel(hour: 7, minute: 0, windowDays: 30)
        let fires = planner().fires(for: alarm, workday: makeCalendar(), from: TestCalendar.date(2026, 9, 30, 8, 0))
        for day in 1...7 {
            let date = TestCalendar.date(2026, 10, day)
            XCTAssertFalse(
                fires.contains { cal.isDate($0.fireDate, inSameDayAs: date) },
                "10/\(day) 是国庆假期，不该响"
            )
        }
    }

    /// 10/10 周六是调休补班，必须被排进去
    func testMakeupSaturdayIsScheduled() {
        let alarm = AlarmModel(hour: 7, minute: 0, windowDays: 30)
        let fires = planner().fires(for: alarm, workday: makeCalendar(), from: TestCalendar.date(2026, 9, 30, 8, 0))
        XCTAssertTrue(
            fires.contains { cal.isDate($0.fireDate, inSameDayAs: TestCalendar.date(2026, 10, 10)) },
            "10/10 是国庆调休补班日，必须排进响铃列表"
        )
    }

    /// 端到端：中秋 + 国庆连休的完整窗口，逐日核对
    func testMidAutumnAndNationalDayWindowDayByDay() {
        let alarm = AlarmModel(hour: 7, minute: 0, windowDays: 30)
        let fires = planner().fires(for: alarm, workday: makeCalendar(), from: TestCalendar.date(2026, 9, 18, 6, 0))
        let result = Set(keys(fires))

        // 9/20 周日，国庆调休补班 → 响
        XCTAssertTrue(result.contains("2026-09-20"), "9/20 调休补班必须响")
        // 9/19 周六，普通周末 → 不响
        XCTAssertFalse(result.contains("2026-09-19"), "9/19 普通周六不该响")
        // 9/21–9/24 正常工作周 → 响
        for day in 21...24 {
            XCTAssertTrue(result.contains("2026-09-\(day)"), "9/\(day) 应该响")
        }
        // 9/25–9/27 中秋连休 → 不响
        for day in 25...27 {
            XCTAssertFalse(result.contains("2026-09-\(day)"), "9/\(day) 中秋放假，不该响")
        }
        // 9/28–9/30 正常上班 → 响
        for day in 28...30 {
            XCTAssertTrue(result.contains("2026-09-\(day)"), "9/\(day) 应该响")
        }
        // 10/1–10/7 国庆假期 → 不响
        for day in 1...7 {
            XCTAssertFalse(result.contains("2026-10-0\(day)"), "10/\(day) 国庆放假，不该响")
        }
        // 10/8 周四、10/9 周五 上班 → 响
        XCTAssertTrue(result.contains("2026-10-08"))
        XCTAssertTrue(result.contains("2026-10-09"))
        // 10/10 周六 调休补班 → 响
        XCTAssertTrue(result.contains("2026-10-10"), "10/10 调休补班必须响")
        // 10/11 周日 → 不响
        XCTAssertFalse(result.contains("2026-10-11"), "10/11 周日不该响")
    }

    /// 关掉「跟随国务院」后行为应当退回旧版 iOS：长假照响、补班不响
    func testIgnoringStateHolidaysReproducesLegacyBehaviour() {
        let alarm = AlarmModel(hour: 7, minute: 0, windowDays: 30)
        let workday = makeCalendar(respectsStateHolidays: false)
        let fires = planner().fires(for: alarm, workday: workday, from: TestCalendar.date(2026, 9, 30, 8, 0))
        let result = Set(keys(fires))

        XCTAssertTrue(result.contains("2026-10-01"), "不跟随调休时，国庆当天的周四照响（旧行为）")
        XCTAssertFalse(result.contains("2026-10-10"), "不跟随调休时，补班的周六不响（旧行为）")
    }

    // MARK: - 只响一次

    func testOnceModeRingsExactlyOnce() {
        let day = TestCalendar.date(2026, 10, 3) // 法定假日，但用户显式指定
        let alarm = AlarmModel(hour: 8, minute: 0, repeatMode: .once(day), windowDays: 21)
        let fires = planner().fires(for: alarm, workday: makeCalendar(), from: TestCalendar.date(2026, 9, 17))

        XCTAssertEqual(fires.count, 1)
        XCTAssertTrue(cal.isDate(fires[0].fireDate, inSameDayAs: day))
        XCTAssertEqual(cal.component(.hour, from: fires[0].fireDate), 8)
        XCTAssertEqual(cal.component(.minute, from: fires[0].fireDate), 0)
    }

    func testOnceModeInThePastProducesNothing() {
        let day = TestCalendar.date(2026, 10, 3)
        let alarm = AlarmModel(hour: 8, minute: 0, repeatMode: .once(day))
        XCTAssertTrue(planner().fires(for: alarm, workday: makeCalendar(), from: TestCalendar.date(2026, 11, 1)).isEmpty)
    }

    // MARK: - 预告（日历视图用）

    func testPreviewLengthAndConsistency() {
        let alarm = AlarmModel(hour: 7, minute: 0)
        let workday = makeCalendar()
        let previews = planner().preview(for: alarm, workday: workday, from: TestCalendar.date(2026, 9, 25), days: 20)

        XCTAssertEqual(previews.count, 20)
        for preview in previews {
            XCTAssertEqual(preview.rings, workday.isWorkday(preview.date), "\(preview.key) 的预告与判定不一致")
            if preview.rings {
                XCTAssertNotNil(preview.fireDate)
            } else {
                XCTAssertNil(preview.fireDate)
            }
        }
    }

    func testPreviewIncludesNonRingingDays() {
        let alarm = AlarmModel(hour: 7, minute: 0)
        let previews = planner().preview(
            for: alarm,
            workday: makeCalendar(),
            from: TestCalendar.date(2026, 10, 1),
            days: 7
        )
        XCTAssertEqual(previews.count, 7)
        XCTAssertTrue(previews.allSatisfy { !$0.rings }, "10/1–10/7 整段都该是静音的")
        XCTAssertTrue(previews.allSatisfy { $0.kind == .statutoryHoliday(name: "国庆节") })
    }

    func testNextFireReturnsFirstUpcomingOccurrence() throws {
        let alarm = AlarmModel(hour: 7, minute: 0, windowDays: 30)
        let next = try XCTUnwrap(planner().nextFire(
            for: alarm,
            workday: makeCalendar(),
            from: TestCalendar.date(2026, 9, 30, 8, 0)
        ))
        // 9/30 08:00 之后，最近的响铃应当是 10/8（国庆 7 天 + 之后的第一个上班日）
        XCTAssertEqual(DateKey.string(next.fireDate, calendar: cal), "2026-10-08")
    }

    // MARK: - 排期 ID 稳定性

    /// 同一闹钟同一时刻必须派生同一个系统闹钟 ID，否则滚动刷新会堆出重复闹钟
    func testPlannedFireIDsAreStableAcrossRuns() {
        let alarm = AlarmModel(hour: 7, minute: 0, windowDays: 30)
        let workday = makeCalendar()
        let from = TestCalendar.date(2026, 9, 17, 0, 1)

        let first = planner().fires(for: alarm, workday: workday, from: from)
        let second = planner().fires(for: alarm, workday: workday, from: from)

        XCTAssertEqual(first.map(\.uuid), second.map(\.uuid), "两次排期的 ID 必须完全一致，才能幂等对账")
    }

    /// 改时间后，新旧 ID 必须完全不重叠 —— 否则旧闹钟不会被取消，改时间等于没改。
    /// 这条是被测试抓出来的真实缺陷：ID 原先只精确到「天」，把时间漏掉了。
    func testChangingTimeReplacesSystemAlarmIDs() {
        let alarm = AlarmModel(hour: 7, minute: 0, windowDays: 7)
        var later = alarm
        later.hour = 8
        later.minute = 30

        let from = TestCalendar.date(2026, 9, 17, 0, 1)
        let workday = makeCalendar()

        let earlyIDs = Set(planner().fires(for: alarm, workday: workday, from: from).map(\.uuid))
        let laterIDs = Set(planner().fires(for: later, workday: workday, from: from).map(\.uuid))

        XCTAssertFalse(earlyIDs.isEmpty)
        XCTAssertFalse(laterIDs.isEmpty)
        XCTAssertTrue(earlyIDs.isDisjoint(with: laterIDs), "改时间后 ID 必须完全不同，旧排期才会被对账取消")
        XCTAssertEqual(earlyIDs.count, laterIDs.count, "改时间不该改变会响的天数")
    }
}
