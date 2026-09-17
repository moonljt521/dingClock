import Foundation

/// 系统闹钟授权状态
enum AlarmAuthState: Equatable, Sendable {
    case notDetermined
    case authorized
    case denied
    /// 当前系统/工具链不支持真正的系统级闹钟
    case unsupported

    var label: String {
        switch self {
        case .notDetermined: return "未授权"
        case .authorized: return "已授权"
        case .denied: return "已拒绝"
        case .unsupported: return "当前环境不支持"
        }
    }

    var guidance: String {
        switch self {
        case .notDetermined: return "需要授权才能像系统闹钟一样突破静音和专注模式"
        case .authorized: return "闹钟可以突破静音模式与专注模式"
        case .denied: return "请到「设置 → 叮咚」中重新开启闹钟权限"
        case .unsupported: return "需要 iOS 26 及以上系统 + Xcode 26 工具链"
        }
    }
}

/// 排期时的呈现参数，与具体框架解耦
struct AlarmPresentationSpec: Sendable, Equatable {
    var title: String
    var snoozeEnabled: Bool
    /// 稍后提醒时长（秒）
    var snoozeDuration: TimeInterval

    init(title: String = "该起床了", snoozeEnabled: Bool = true, snoozeDuration: TimeInterval = 9 * 60) {
        self.title = title
        self.snoozeEnabled = snoozeEnabled
        self.snoozeDuration = snoozeDuration
    }
}

/// 响铃后端抽象。
///
/// 存在的意义：让「工作日判定 + 排期」这套核心逻辑与 Apple 的具体框架解耦，
/// 从而既能在没有 iOS 26 SDK 的机器上编译验证，又能在 Xcode 26 下原样切到真闹钟。
protocol AlarmScheduling: AnyObject, Sendable {
    /// 当前环境是否支持真正的系统级闹钟（AlarmKit）
    var isSupported: Bool { get }
    /// 后端名称，展示给用户/开发者
    var backendName: String { get }
    /// 说明文案：为什么不响，或者响得多可靠
    var backendNote: String { get }

    func authorizationState() async -> AlarmAuthState
    @discardableResult func requestAuthorization() async throws -> Bool

    /// **幂等对账**：让系统里的排期与 `plans` 完全一致。
    /// 实现约定 —— 先取消不在 `plans` 里的，再下发缺失的。
    ///
    /// 系统对**同时存在**的闹钟数有动态上限（官方 FAQ：无固定值，按设备状态定），
    /// 撞上时会收到 `maximumLimitReached`。实现应当**停手而不是抛错**：
    /// 保留已排进去的那些（plans 按时间升序，所以留下的是最早的），
    /// 并把 `limitHit` 置真，由上层如实告知用户。
    func reconcile(plans: [PlannedFire], spec: AlarmPresentationSpec) async throws

    /// 上一次 reconcile 是否撞到了系统的同时闹钟数上限
    var limitHit: Bool { get }

    /// 清空本 App 的所有排期
    func cancelAll() async throws

    /// 当前系统里已排期的数量
    func scheduledCount() async throws -> Int

    /// 系统里**实际**排着的响铃日期，按时间升序。
    /// 这是审计用的：我们的判定说是工作日，系统里到底有没有，得以系统为准读回来核对。
    func scheduledSystemDates() async -> [Date]
}

enum AlarmSchedulerFactory {
    /// 自动挑选可用后端：有 AlarmKit 就用真闹钟，否则退回调试后端
    static func make() -> any AlarmScheduling {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            return AlarmKitScheduler()
        }
        #endif
        return DebugAlarmScheduler()
    }
}
