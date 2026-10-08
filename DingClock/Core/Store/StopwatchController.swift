import Combine
import Foundation

/// 秒表状态的持久化键。
///
/// 定义在类型外面而不是塞进 `StopwatchController`：那个类是 `@MainActor` 的，
/// 它的 static 存储属性会跟着被主线程隔离，而这个键偶尔要在别处读。
let stopwatchStorageKey = "stopwatch.state"

/// 一次计次
struct StopwatchLap: Identifiable, Codable, Equatable {
    /// 第几次，从 1 开始
    var index: Int
    /// 计次那一刻的总用时
    var total: TimeInterval
    /// 距上一次计次之间的用时
    var split: TimeInterval

    var id: Int { index }
}

/// 秒表状态存档
struct StopwatchSnapshot: Codable, Equatable {

    enum Phase: String, Codable {
        case idle
        case running
        case paused
    }

    var phase: Phase
    var accumulated: TimeInterval
    var startedAt: Date?
    var laps: [StopwatchLap]
}

/// 秒表的状态机。
///
/// 和倒计时不同，秒表**完全不碰 AlarmKit** —— 它不提醒、不响铃，只把时间量出来。
/// 所以这里没有任何授权、没有任何系统调用，纯粹是本地状态 + 墙钟计算。
///
/// - Note: 读数刻意不靠定时器累加，而是每次读的时候用**墙钟**算（见 `elapsed`）。
///   App 退到后台、甚至被杀掉再回来，读数依然准确 —— 定时器会随 App 挂起而停摆，
///   墙钟不会。
@MainActor
final class StopwatchController: ObservableObject {

    typealias Phase = StopwatchSnapshot.Phase

    // MARK: - 对外状态

    @Published private(set) var phase: Phase = .idle
    /// 已经冻结的累计秒数（暂停时定格在这里）
    @Published private(set) var accumulated: TimeInterval = 0
    /// 本轮起跑的时刻；只在 `running` 时有值
    @Published private(set) var startedAt: Date?
    /// 计次记录，**最新的一次在最前面**
    @Published private(set) var laps: [StopwatchLap] = []

    /// 当前读数
    var elapsed: TimeInterval {
        guard phase == .running, let startedAt else { return accumulated }
        return accumulated + Date().timeIntervalSince(startedAt)
    }

    var isRunning: Bool { phase == .running }
    var isIdle: Bool { phase == .idle }
    var hasLaps: Bool { !laps.isEmpty }

    /// 左侧按钮：跑着的时候是「计次」，停下来是「重置」
    var leftButtonTitle: String { isRunning ? "计次" : "重置" }

    /// 左侧按钮能不能按。停在 0 上的「重置」没有任何意义，置灰。
    var canUseLeftButton: Bool { isRunning || elapsed > 0 }

    /// 右侧主按钮
    var primaryButtonTitle: String {
        switch phase {
        case .idle: return "开始"
        case .running: return "停止"
        case .paused: return "继续"
        }
    }

    // MARK: - 依赖

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        restore()
    }

    // MARK: - 操作

    func start() {
        guard phase != .running else { return }
        startedAt = Date()
        phase = .running
        persist()
    }

    func pause() {
        guard phase == .running else { return }
        // 先把读数冻进 accumulated，再清掉起跑点 —— 顺序反了就会丢掉这一段
        accumulated = elapsed
        startedAt = nil
        phase = .paused
        persist()
    }

    func toggle() {
        isRunning ? pause() : start()
    }

    /// 计次：记下「此刻总用时」和「距上次计次用了多久」
    func lap() {
        guard phase == .running else { return }
        let total = elapsed
        let previous = laps.first?.total ?? 0
        laps.insert(
            StopwatchLap(index: laps.count + 1, total: total, split: total - previous),
            at: 0
        )
        persist()
    }

    func reset() {
        phase = .idle
        accumulated = 0
        startedAt = nil
        laps = []
        persist()
    }

    // MARK: - 持久化

    private func persist() {
        let snapshot = StopwatchSnapshot(
            phase: phase,
            accumulated: accumulated,
            startedAt: startedAt,
            laps: laps
        )
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: stopwatchStorageKey)
    }

    /// 启动时恢复。
    ///
    /// 存档里是 `running` 的话，`startedAt` 是过去某个时刻，读数由墙钟算出来 ——
    /// 所以「App 关了半小时再打开，秒表还在走」是**正确**行为，不需要特殊处理。
    /// 这一点和倒计时刚好相反：那边过了点就得复位。
    private func restore() {
        guard let data = defaults.data(forKey: stopwatchStorageKey),
              let saved = try? JSONDecoder().decode(StopwatchSnapshot.self, from: data) else { return }

        accumulated = max(0, saved.accumulated)
        laps = saved.laps

        switch saved.phase {
        case .idle:
            phase = .idle
            startedAt = nil
        case .running:
            phase = .running
            startedAt = saved.startedAt ?? Date()
        case .paused:
            phase = .paused
            startedAt = nil
        }
    }

    // MARK: - 格式化

    /// `mm:ss.cc`；超过一小时自动补上小时位。
    ///
    /// 百分秒用 `rounded(.down)` 而不是四舍五入 —— 秒表读数只该向下取，
    /// 否则 12.999 会显示成 13.00，比实际走得快。
    static func format(_ seconds: TimeInterval) -> String {
        let total = max(0, seconds)
        let whole = Int(total)
        let h = whole / 3600
        let m = (whole % 3600) / 60
        let s = whole % 60
        let centis = min(99, Int(((total - Double(whole)) * 100).rounded(.down)))

        if h > 0 {
            return String(format: "%d:%02d:%02d.%02d", h, m, s, centis)
        }
        return String(format: "%02d:%02d.%02d", m, s, centis)
    }
}
