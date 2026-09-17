import XCTest
@testable import DingClock

/// 系统闹钟 ID 的稳定性测试。
///
/// 排期是滚动对账式的：App 每次回到前台都会重算未来 N 天。如果 ID 不稳定，
/// 系统里就会堆满重复闹钟 —— 这组测试守住这条底线。
final class StableIDTests: XCTestCase {

    private let cal = TestCalendar.calendar

    func testSameSeedProducesSameUUID() {
        XCTAssertEqual(StableID.uuid("dingclock"), StableID.uuid("dingclock"))
    }

    func testDifferentSeedsProduceDifferentUUIDs() {
        XCTAssertNotEqual(StableID.uuid("dingclock"), StableID.uuid("dingclocj"))
        XCTAssertNotEqual(StableID.uuid("a"), StableID.uuid("b"))
    }

    func testUUIDIsWellFormed() {
        let uuid = StableID.uuid("2026-10-10")
        XCTAssertEqual(uuid.uuidString.count, 36)
        // 版本位应当是 5
        let versionChar = Array(uuid.uuidString)[14]
        XCTAssertEqual(versionChar, "5")
    }

    func testFireIDIsDeterministicPerAlarmPerDate() {
        let alarmID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let day1 = TestCalendar.date(2026, 10, 10, 7, 0)
        let day2 = TestCalendar.date(2026, 10, 12, 7, 0)

        let a = StableID.fireID(alarmID: alarmID, fireDate: day1, calendar: cal)
        let b = StableID.fireID(alarmID: alarmID, fireDate: day1, calendar: cal)
        let c = StableID.fireID(alarmID: alarmID, fireDate: day2, calendar: cal)

        XCTAssertEqual(a, b, "同一闹钟同一天必须派生同一个 ID")
        XCTAssertNotEqual(a, c, "不同日期必须是不同的系统闹钟")
    }

    func testFireIDDiffersBetweenAlarms() {
        let day = TestCalendar.date(2026, 10, 10, 7, 0)
        let a = StableID.fireID(alarmID: UUID(), fireDate: day, calendar: cal)
        let b = StableID.fireID(alarmID: UUID(), fireDate: day, calendar: cal)
        XCTAssertNotEqual(a, b, "两个闹钟在同一天要各自独立，不能互相覆盖")
    }

    /// 时刻变了，ID 也应该变 —— 否则改时间不会生效
    func testFireIDChangesWhenTimeChanges() {
        let alarmID = UUID()
        let morning = TestCalendar.date(2026, 10, 10, 7, 0)
        let later = TestCalendar.date(2026, 10, 10, 8, 30)
        XCTAssertNotEqual(
            StableID.fireID(alarmID: alarmID, fireDate: morning, calendar: cal),
            StableID.fireID(alarmID: alarmID, fireDate: later, calendar: cal)
        )
    }
}
