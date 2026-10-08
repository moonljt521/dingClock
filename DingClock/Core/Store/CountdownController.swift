import Combine
import Foundation

/// 倒计时状态的持久化键。
///
/// 定义在类型外面而不是塞进 `CountdownController`：那个类是 `@MainActor` 的，
/// 它的 static 存储属性会跟着被主线程隔离，而后台 Intent 需要在非主线程读同一个键。
let countdownStorageKey = "countdown.state"

/// 倒计时状态存档
struct CountdownSnapshot: Codable, Equatable {

    enum Phase: String, Codable {
        case idle
        case running
        case paused
    }

    var phase: Phase
    var totalDuration: TimeInterval
    var endDate: Date?
    var pausedRemaining: TimeInterval
}

/// 倒计时页的状态机与编排。
///
/// 三件事它要负责：
/// 1. 把「起 / 暂停 / 继续 / 取消」翻译成后端调用
/// 2. 维护界面要用的剩余时间与进度
/// 3. 把状态落盘 —— 倒计时起完之后用户很可能会杀掉 App，回来时得知道还在跑
///
/// 后端只负责"到点叫醒"，剩余时间的推进完全由本地时钟算，不依赖系统回调。
@MainActor
final class CountdownController: ObservableObject {

    typealias Phase = CountdownSnapshot.Phase

    // MARK: - 对外状态

    @Published private(set) var phase: Phase = .idle
    /// 选定的总时长（待机时可直接改）
    @Published private(set) var totalDuration: TimeInterval = 5 * 60
    /// 运行中的结束时刻
    @Published private(set) var endDate: Date?
    /// 暂停时冻结的剩余秒数
    @Published private(set) var pausedRemaining: TimeInterval = 0
    @Published private(set) var lastError: String?

    let scheduler: any CountdownScheduling

    var isSupported: Bool { scheduler.isSupported }
    var backendNote: String { scheduler.backendNote }

    /// 剩余秒数。运行中由本地时钟实时算，所以每秒取值都不同。
    var remaining: TimeInterval {
        switch phase {
        case .idle: return totalDuration
        case .running: return max(0, endDate?.timeIntervalSinceNow ?? 0)
        case .paused: return pausedRemaining
        }
    }

    /// 时间已经走完、系统正在响铃
    var isRinging: Bool {
        phase == .running && remaining <= 0
    }

    /// 待机（可以改时长、点开始）
    var isIdle: Bool { phase == .idle }

    /// 正在倒数
    var isRunning: Bool { phase == .running }

    // MARK: - 依赖

    private let defaults: UserDefaults

    init(
        scheduler: any CountdownScheduling = CountdownSchedulerFactory.make(),
        defaults: UserDefaults = .standard
    ) {
        self.scheduler = scheduler
        self.defaults = defaults
        restore()
    }

    // MARK: - 操作

    func setDuration(_ seconds: TimeInterval) {
        // 跑起来之后不让改 —— 改了也不会作用于已经在系统里排好的那一次，只会误导
        guard phase == .idle else { return }
        totalDuration = min(max(seconds, 10), 24 * 60 * 60)
        persist()
    }

    func start() async {
        guard phase == .idle else { return }
        let duration = max(10, totalDuration)
        do {
            try await scheduler.start(duration: duration)
            totalDuration = duration
            endDate = Date().addingTimeInterval(duration)
            phase = .running
            lastError = nil
            persist()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func pause() async {
        guard phase == .running else { return }
        let left = remaining
        do {
            try await scheduler.pause()
            pausedRemaining = left
            endDate = nil
            phase = .paused
            lastError = nil
            persist()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func resume() async {
        guard phase == .paused else { return }
        do {
            try await scheduler.resume()
            endDate = Date().addingTimeInterval(pausedRemaining)
            phase = .running
            lastError = nil
            persist()
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// 取消（还没响）或停止（已经在响），两者对界面的结果是一样的
    func cancel() async {
        try? await scheduler.cancel()
        reset()
    }

    func stop() async {
        try? await scheduler.stop()
        reset()
    }

    func reset() {
        phase = .idle
        endDate = nil
        pausedRemaining = 0
        lastError = nil
        persist()
    }

    // MARK: - 持久化

    private func snapshot() -> CountdownSnapshot {
        CountdownSnapshot(
            phase: phase,
            totalDuration: totalDuration,
            endDate: endDate,
            pausedRemaining: pausedRemaining
        )
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(snapshot()) else { return }
        defaults.set(data, forKey: countdownStorageKey)
    }

    /// 启动时恢复。
    ///
    /// 关键判断：存档里写着「运行中」但结束时刻已经过去了 —— 说明倒计时在
    /// App 不在的时候已经响过（或被系统清掉了），这时必须复位成待机，
    /// 否则界面会停在一个永远不会归零的倒计时上。
    private func restore() {
        guard let data = defaults.data(forKey: countdownStorageKey),
              let saved = try? JSONDecoder().decode(CountdownSnapshot.self, from: data) else { return }

        totalDuration = saved.totalDuration

        switch saved.phase {
        case .idle:
            phase = .idle

        case .running:
            guard let end = saved.endDate, end > Date() else {
                reset()
                return
            }
            phase = .running
            endDate = end

        case .paused:
            phase = .paused
            pausedRemaining = max(0, saved.pausedRemaining)
            endDate = nil
        }
    }

    /// 后台 Intent 调用的复位。
    ///
    /// 刻意用 `nonisolated`：系统拉起 App 执行 Intent 时不保证在主线程，
    /// 而这里只碰 UserDefaults，不需要主线程。反过来若标成 `@MainActor`，
    /// 后台回调就得先等主线程调度，容易在时间预算里被掐掉。
    nonisolated static func markStoppedInBackground() {
        UserDefaults.standard.removeObject(forKey: countdownStorageKey)
    }
}
