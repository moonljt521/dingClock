import Foundation

/// 某一天的性质。这是整个 App 的核心输出类型——
/// 闹钟响不响，取决于这一天的 `isWorkday`。
enum DayKind: Equatable, Sendable {
    /// 常规工作日（由周模式判定，且没有节假日干扰）
    case regularWorkday
    /// 普通周末
    case weekend
    /// 法定节假日（放假）——不响
    case statutoryHoliday(name: String)
    /// 调休补班日（周末上班）——必须响，这是最容易睡过头的一天
    case makeupWorkday(name: String)
    /// 用户手动标记为上班（优先级最高）
    case manualWorkday(note: String)
    /// 用户手动标记为放假（优先级最高）
    case manualRest(note: String)

    /// 最终答案：这天闹钟该不该响
    var isWorkday: Bool {
        switch self {
        case .regularWorkday, .makeupWorkday, .manualWorkday: return true
        case .weekend, .statutoryHoliday, .manualRest: return false
        }
    }

    /// 短标签，用在日历格子里
    var shortLabel: String {
        switch self {
        case .regularWorkday: return "班"
        case .weekend: return "休"
        case .statutoryHoliday: return "假"
        case .makeupWorkday: return "班"
        case .manualWorkday: return "班"
        case .manualRest: return "休"
        }
    }

    /// 完整解释，让用户一眼看懂「为什么今天响/不响」
    var reason: String {
        switch self {
        case .regularWorkday: return "常规工作日"
        case .weekend: return "周末休息"
        case .statutoryHoliday(let name): return "\(name) · 法定放假"
        case .makeupWorkday(let name): return "\(name) · 调休补班"
        case .manualWorkday(let note): return note.isEmpty ? "手动标记上班" : "手动标记上班 · \(note)"
        case .manualRest(let note): return note.isEmpty ? "手动标记放假" : "手动标记放假 · \(note)"
        }
    }

    /// 是否属于「特殊安排」（用于在 UI 上高亮，提醒用户这不是普通的周几）
    var isSpecialArrangement: Bool {
        switch self {
        case .statutoryHoliday, .makeupWorkday, .manualWorkday, .manualRest: return true
        case .regularWorkday, .weekend: return false
        }
    }

    /// 是否是「反直觉」的一天——法定假日落在周一至周五、或补班落在周末。
    /// 这类日子最需要提醒用户，也正是旧版 iOS 闹钟最容易出错的场景。
    var isCounterIntuitive: Bool {
        switch self {
        case .statutoryHoliday, .makeupWorkday: return true
        default: return false
        }
    }
}
