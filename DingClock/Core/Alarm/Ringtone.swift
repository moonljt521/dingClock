import Foundation

/// 一个可选的闹钟铃声。
///
/// `fileName == nil` 表示用 AlarmKit 的系统默认铃声（`.default`）；
/// 否则用 `.named(fileName)` 指向 App 包里的音频资源（由 `scripts/make-ringtones.py` 生成）。
struct Ringtone: Identifiable, Equatable, Sendable {
    /// 持久化标识
    let id: String
    /// 用户可见名
    let label: String
    /// App 包内的音频资源名（不含扩展名）；nil = 系统默认
    let fileName: String?

    var isSystemDefault: Bool { fileName == nil }
}

/// 内置铃声目录。
///
/// ⚠️ AlarmKit 的 `AlertSound` 只有 `.default` 和 `.named(资源名)` 两个选项，
/// **没有**"无声/仅震动" —— 这是苹果有意为之（AlarmKit 的承诺是"一定叫醒你"）。
/// 震动由手机「设置 → 声音与触感 → 触感」的全局开关决定，App 无权指定。
enum RingtoneCatalog {

    static let systemDefaultID = "system_default"

    /// 顺序即编辑页展示顺序；第一个是默认项
    static let all: [Ringtone] = [
        Ringtone(id: systemDefaultID, label: "系统默认", fileName: nil),
        Ringtone(id: "bell_classic",  label: "经典钟声", fileName: "bell_classic"),
        Ringtone(id: "gentle_rise",   label: "轻柔渐强", fileName: "gentle_rise"),
        Ringtone(id: "birds",         label: "清晨鸟鸣", fileName: "birds"),
        Ringtone(id: "soft_pulse",    label: "柔和嗡鸣", fileName: "soft_pulse"),
    ]

    /// 未知 id 一律退回系统默认，保证老数据/脏数据不会让排期失败
    static func find(_ id: String?) -> Ringtone {
        all.first { $0.id == id } ?? all[0]
    }

    /// 喂给 `AlertSound.named()` 的资源名；系统默认返回 nil
    static func soundName(forID id: String?) -> String? {
        find(id).fileName
    }

    static func label(forID id: String?) -> String {
        find(id).label
    }
}
