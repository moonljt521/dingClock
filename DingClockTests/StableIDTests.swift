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

        let a = StableID.fireID(alarmID: alarmID, fireDate: day1, appearance: "test", calendar: cal)
        let b = StableID.fireID(alarmID: alarmID, fireDate: day1, appearance: "test", calendar: cal)
        let c = StableID.fireID(alarmID: alarmID, fireDate: day2, appearance: "test", calendar: cal)

        XCTAssertEqual(a, b, "同一闹钟同一天必须派生同一个 ID")
        XCTAssertNotEqual(a, c, "不同日期必须是不同的系统闹钟")
    }

    func testFireIDDiffersBetweenAlarms() {
        let day = TestCalendar.date(2026, 10, 10, 7, 0)
        let a = StableID.fireID(alarmID: UUID(), fireDate: day, appearance: "test", calendar: cal)
        let b = StableID.fireID(alarmID: UUID(), fireDate: day, appearance: "test", calendar: cal)
        XCTAssertNotEqual(a, b, "两个闹钟在同一天要各自独立，不能互相覆盖")
    }

    /// 时刻变了，ID 也应该变 —— 否则改时间不会生效
    func testFireIDChangesWhenTimeChanges() {
        let alarmID = UUID()
        let morning = TestCalendar.date(2026, 10, 10, 7, 0)
        let later = TestCalendar.date(2026, 10, 10, 8, 30)
        XCTAssertNotEqual(
            StableID.fireID(alarmID: alarmID, fireDate: morning, appearance: "test", calendar: cal),
            StableID.fireID(alarmID: alarmID, fireDate: later, appearance: "test", calendar: cal)
        )
    }

    // MARK: - 呈现配置参与 ID 派生

    /// 改了铃声 / 标签 / 稍后提醒，ID 必须跟着变。
    ///
    /// 这条守住的是一个真实事故：AlarmKit 对**已存在的 ID** 调 schedule 会直接报
    /// `Not scheduling an alarm with a duplicate ID`，而不是覆盖。所以对账只能下发
    /// "系统里还没有的 ID" —— 如果呈现配置不参与 ID，那改了铃声永远生效不了。
    func testAppearanceChangesDeriveNewFireID() {
        let alarmID = UUID()
        let day = TestCalendar.date(2026, 10, 10, 7, 0)

        let base = StableID.appearanceFingerprint(label: "起床", ringtoneID: "birds", snoozeEnabled: true)
        let otherRingtone = StableID.appearanceFingerprint(label: "起床", ringtoneID: "guitar", snoozeEnabled: true)
        let otherLabel = StableID.appearanceFingerprint(label: "开会", ringtoneID: "birds", snoozeEnabled: true)
        let noSnooze = StableID.appearanceFingerprint(label: "起床", ringtoneID: "birds", snoozeEnabled: false)

        let ids = [base, otherRingtone, otherLabel, noSnooze].map {
            StableID.fireID(alarmID: alarmID, fireDate: day, appearance: $0, calendar: cal)
        }
        XCTAssertEqual(Set(ids).count, 4, "四种配置必须派生四个不同的系统闹钟 ID，否则改动不会生效")
    }

    /// 指纹本身要稳定：同样的配置永远得到同样的字符串
    func testAppearanceFingerprintIsStable() {
        let a = StableID.appearanceFingerprint(label: "起床", ringtoneID: nil, snoozeEnabled: true)
        let b = StableID.appearanceFingerprint(label: "起床", ringtoneID: nil, snoozeEnabled: true)
        XCTAssertEqual(a, b)
        XCTAssertTrue(a.contains(RingtoneCatalog.systemDefaultID), "系统默认铃声要有明确占位，不能是空串")
    }
}
