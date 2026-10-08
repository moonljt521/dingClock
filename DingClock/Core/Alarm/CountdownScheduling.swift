import Foundation

/// 倒计时后端抽象。
///
/// 和 `AlarmScheduling` 分开，是因为两者的语义差得比较远：
/// 闹钟是「未来 N 天里哪几天要响」的对账问题，倒计时是「从现在起 M 分钟后响一次」。
/// 硬塞进同一个协议只会让两边都别扭。
///
/// 共用的是同一片 AlarmKit ID 空间和同一份授权 —— 所以倒计时的 ID
/// 在 `StableID` 里登记为**保留 ID**，闹钟对账时会跳过它。
protocol CountdownScheduling: AnyObject, Sendable {
    /// 当前环境能否真的在到点时把用户叫醒
    var isSupported: Bool { get }
    /// 说明文案
    var backendNote: String { get }

    /// 起一个倒计时。重复调用会覆盖上一个。
    func start(duration: TimeInterval) async throws
    func pause() async throws
    func resume() async throws
    /// 用户主动取消（还没响）
    func cancel() async throws
    /// 已经在响了，把它按停
    func stop() async throws
    /// 系统里是否还挂着这个倒计时
    func isActive() async -> Bool
}

enum CountdownSchedulerFactory {
    static func make() -> any CountdownScheduling {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            return AlarmKitCountdownScheduler()
        }
        #endif
        return DebugCountdownScheduler()
    }
}

/// 没有 AlarmKit 时的降级实现：界面照常走，到点不会响。
///
/// 刻意**不做本地通知兜底** —— 理由和闹钟那边一样：本地通知突破不了静音模式，
/// 拿它冒充倒计时提醒，只会让人在需要被提醒的时候什么也没听见。
/// 宁可明说「这个环境不会响」。
final class DebugCountdownScheduler: CountdownScheduling, @unchecked Sendable {

    private let lock = NSLock()
    private var _active = false

    var isSupported: Bool { false }
    var backendNote: String { "当前工具链没有 iOS 26 SDK，倒计时只在界面里走，到点不会响。" }

    func start(duration: TimeInterval) async throws {
        lock.lock(); _active = true; lock.unlock()
    }

    func pause() async throws {}
    func resume() async throws {}

    func cancel() async throws {
        lock.lock(); _active = false; lock.unlock()
    }

    func stop() async throws {
        lock.lock(); _active = false; lock.unlock()
    }

    func isActive() async -> Bool {
        lock.lock(); defer { lock.unlock() }
        return _active
    }
}
