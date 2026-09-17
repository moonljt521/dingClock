import Foundation

/// 调试/降级后端。
///
/// **它不是闹钟。** 它只把「本来该排什么」记下来，让界面在没有 iOS 26 SDK 的
/// 环境里（比如 Xcode 16.2 + iOS 18 模拟器）依然能完整跑通并验证排期是否正确。
///
/// 产品决策：**不做本地通知兜底**——本地通知无法突破静音模式、锁屏不可靠，
/// 用它冒充闹钟只会让人睡过头。宁可明确告诉用户「当前环境不支持」。
final class DebugAlarmScheduler: AlarmScheduling, @unchecked Sendable {

    private let lock = NSLock()
    private var _plans: [PlannedFire] = []
    private var _reconcileCount = 0
    private var _limitHit = false

    var isSupported: Bool { false }
    var backendName: String { "调试排期（未接入系统闹钟）" }
    var backendNote: String {
        "当前工具链没有 iOS 26 SDK，无法调用 AlarmKit。排期照样在算，但不会真的响——需要 Xcode 26 + iOS 26 真机才能验证响铃。"
    }

    var limitHit: Bool { false }

    var reconciliationCount: Int {
        lock.lock(); defer { lock.unlock() }
        return _reconcileCount
    }

    var mirroredPlans: [PlannedFire] {
        lock.lock(); defer { lock.unlock() }
        return _plans
    }

    func authorizationState() async -> AlarmAuthState { .unsupported }

    func requestAuthorization() async throws -> Bool { false }

    func reconcile(plans: [PlannedFire], spec: AlarmPresentationSpec) async throws {
        lock.lock()
        _plans = plans
        _reconcileCount += 1
        lock.unlock()
        print("[DingClock] 调试排期：已对账 \(plans.count) 个时刻")
    }

    func cancelAll() async throws {
        lock.lock()
        _plans = []
        lock.unlock()
    }

    func scheduledCount() async throws -> Int {
        lock.lock(); defer { lock.unlock() }
        return _plans.count
    }

    func scheduledSystemDates() async -> [Date] {
        lock.lock(); defer { lock.unlock() }
        return _plans.map(\.fireDate).sorted()
    }
}
