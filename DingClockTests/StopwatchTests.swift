import XCTest
@testable import DingClock

/// 秒表的状态机与格式化。
///
/// 刻意不去断言「跑了 0.1 秒读数就该是 0.10」—— 那种测试依赖真实时钟，
/// 在 CI 上必然随机失败。这里只测**确定的东西**：格式化、状态迁移、
/// 以及计次之间的算术关系。
@MainActor
final class StopwatchTests: XCTestCase {

    /// 每个用例用独立的 UserDefaults，互不干扰、也不污染 App 的真实存档
    private func freshDefaults() -> UserDefaults {
        let name = "dingclock.stopwatch.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    // MARK: - 格式化

    func testFormatBelowOneMinute() {
        XCTAssertEqual(StopwatchController.format(0), "00:00.00")
        XCTAssertEqual(StopwatchController.format(5.25), "00:05.25")
        XCTAssertEqual(StopwatchController.format(59.99), "00:59.99")
    }

    func testFormatOverOneMinute() {
        XCTAssertEqual(StopwatchController.format(60), "01:00.00")
        XCTAssertEqual(StopwatchController.format(65.5), "01:05.50")
        XCTAssertEqual(StopwatchController.format(599.99), "09:59.99")
    }

    func testFormatOverOneHour() {
        XCTAssertEqual(StopwatchController.format(3600), "1:00:00.00")
        XCTAssertEqual(StopwatchController.format(3661.5), "1:01:01.50")
    }

    /// 百分秒必须**向下取**。四舍五入的话 12.999 会显示成 13.00，
    /// 读数比实际跑得快，秒表就没意义了。
    func testFormatTruncatesCentiseconds() {
        XCTAssertEqual(StopwatchController.format(12.999), "00:12.99")
        XCTAssertEqual(StopwatchController.format(0.999), "00:00.99")
    }

    func testFormatClampsNegativeToZero() {
        XCTAssertEqual(StopwatchController.format(-3), "00:00.00")
    }

    // MARK: - 状态机

    func testStartsIdleAndCanStart() {
        let stopwatch = StopwatchController(defaults: freshDefaults())
        XCTAssertEqual(stopwatch.phase, .idle)
        XCTAssertEqual(stopwatch.elapsed, 0, accuracy: 0.0001)
        XCTAssertEqual(stopwatch.primaryButtonTitle, "开始")
        XCTAssertFalse(stopwatch.canUseLeftButton, "停在 0 上的重置没有意义，该置灰")

        stopwatch.start()
        XCTAssertTrue(stopwatch.isRunning)
        XCTAssertEqual(stopwatch.primaryButtonTitle, "停止")
        XCTAssertEqual(stopwatch.leftButtonTitle, "计次")
        XCTAssertTrue(stopwatch.canUseLeftButton)
    }

    /// 暂停之后读数必须冻住，不能还在涨
    func testPauseFreezesElapsed() {
        let stopwatch = StopwatchController(defaults: freshDefaults())
        stopwatch.start()
        stopwatch.pause()

        let frozen = stopwatch.elapsed
        Thread.sleep(forTimeInterval: 0.05)

        XCTAssertEqual(stopwatch.phase, .paused)
        XCTAssertEqual(stopwatch.elapsed, frozen, accuracy: 0.0001)
        XCTAssertEqual(stopwatch.primaryButtonTitle, "继续")
    }

    /// 继续之后应当在暂停前的读数上接着走，而不是从 0 重来
    func testResumeContinuesFromPausedValue() {
        let stopwatch = StopwatchController(defaults: freshDefaults())
        stopwatch.start()
        stopwatch.pause()
        let paused = stopwatch.elapsed

        stopwatch.start()
        XCTAssertEqual(stopwatch.phase, .running)
        XCTAssertGreaterThanOrEqual(stopwatch.elapsed, paused)
    }

    func testResetClearsEverything() {
        let stopwatch = StopwatchController(defaults: freshDefaults())
        stopwatch.start()
        stopwatch.lap()
        stopwatch.pause()
        stopwatch.reset()

        XCTAssertEqual(stopwatch.phase, .idle)
        XCTAssertEqual(stopwatch.elapsed, 0, accuracy: 0.0001)
        XCTAssertTrue(stopwatch.laps.isEmpty)
        XCTAssertFalse(stopwatch.hasLaps)
    }

    // MARK: - 计次

    func testLapRecordsSplitAndTotal() {
        let stopwatch = StopwatchController(defaults: freshDefaults())
        stopwatch.start()
        stopwatch.lap()
        stopwatch.lap()

        XCTAssertEqual(stopwatch.laps.count, 2)
        // 最新的一次排在最前面
        XCTAssertEqual(stopwatch.laps[0].index, 2)
        XCTAssertEqual(stopwatch.laps[1].index, 1)

        // 第 1 次的分段就等于它的总用时（之前没有任何一段）
        XCTAssertEqual(stopwatch.laps[1].split, stopwatch.laps[1].total, accuracy: 0.0001)
        // 第 2 次的分段 = 总用时 − 上一次的总用时
        XCTAssertEqual(
            stopwatch.laps[0].split,
            stopwatch.laps[0].total - stopwatch.laps[1].total,
            accuracy: 0.0001
        )
    }

    /// 没跑起来的时候计次不该生效 —— 否则会记下一堆 0
    func testLapIsIgnoredWhenNotRunning() {
        let stopwatch = StopwatchController(defaults: freshDefaults())
        stopwatch.lap()
        XCTAssertTrue(stopwatch.laps.isEmpty)

        stopwatch.start()
        stopwatch.pause()
        stopwatch.lap()
        XCTAssertTrue(stopwatch.laps.isEmpty, "暂停状态也不该计次")
    }

    // MARK: - 持久化

    func testStateSurvivesRelaunch() {
        let defaults = freshDefaults()

        let first = StopwatchController(defaults: defaults)
        first.start()
        first.lap()
        first.pause()

        let second = StopwatchController(defaults: defaults)
        XCTAssertEqual(second.phase, .paused)
        XCTAssertEqual(second.laps.count, 1)
        XCTAssertEqual(second.elapsed, first.elapsed, accuracy: 0.0001)
    }

    /// 跑着的时候被杀掉，回来应当还在跑，而且读数把「不在的那段时间」也算上
    func testRunningStateKeepsCountingAcrossRelaunch() {
        let defaults = freshDefaults()

        let first = StopwatchController(defaults: defaults)
        first.start()

        // 模拟「App 被关掉一段时间」：把起跑点往前挪
        let rewound = StopwatchSnapshot(
            phase: .running,
            accumulated: 0,
            startedAt: Date().addingTimeInterval(-30),
            laps: []
        )
        defaults.set(try! JSONEncoder().encode(rewound), forKey: stopwatchStorageKey)

        let second = StopwatchController(defaults: defaults)
        XCTAssertEqual(second.phase, .running)
        XCTAssertGreaterThanOrEqual(second.elapsed, 30, "墙钟算出来的读数要把 App 不在的那段时间算进去")
    }
}
