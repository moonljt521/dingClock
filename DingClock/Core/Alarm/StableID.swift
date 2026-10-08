import CryptoKit
import Foundation

/// 由字符串派生**确定性 UUID**。
///
/// 为什么必须确定性：排期是「对账式」的——每次刷新都会重算未来 N 天并重新下发。
/// 如果每次生成随机 UUID，系统里就会堆满重复闹钟。
/// 用内容派生 ID 后，同一天同一时刻永远是同一个 ID，重复下发天然幂等。
enum StableID {

    static func uuid(_ seed: String) -> UUID {
        let digest = SHA256.hash(data: Data(seed.utf8))
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50   // 版本 5
        bytes[8] = (bytes[8] & 0x3F) | 0x80   // RFC 4122 variant
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    /// 某个闹钟在某个**具体时刻**的唯一种子。
    ///
    /// 刻意精确到分钟而不是天：同一闹钟同一天改时间必须产生不同的 ID，
    /// 这样对账时旧 ID 会被判定为「不再需要」而取消，新 ID 被下发 —— 改时间才会真正生效。
    ///
    /// 同样刻意把 `appearance`（标签 / 铃声 / 稍后提醒）编进来。
    /// 原因是 AlarmKit 的硬约束：对**已存在的 ID** 调 `schedule` 不是覆盖，而是直接报
    /// `Not scheduling an alarm with a duplicate ID`。既然对账只能「下发系统里还没有的」，
    /// 那「改了铃声还想让它生效」就只剩一条路 —— 让 ID 跟着配置一起变。
    static func fireSeed(
        alarmID: UUID,
        fireDate: Date,
        appearance: String,
        calendar: Calendar = .current
    ) -> String {
        "\(alarmID.uuidString)@\(DateKey.timestamp(fireDate, calendar: calendar))@\(appearance)"
    }

    /// 某个闹钟在某个具体时刻的系统闹钟 ID
    static func fireID(
        alarmID: UUID,
        fireDate: Date,
        appearance: String,
        calendar: Calendar = .current
    ) -> UUID {
        uuid(fireSeed(alarmID: alarmID, fireDate: fireDate, appearance: appearance, calendar: calendar))
    }

    /// 影响「响铃时怎么呈现」的配置指纹，参与系统闹钟 ID 的派生。
    ///
    /// 任何一项变了，这一批排期就会换一组新 ID：旧的被对账取消、新的被下发，
    /// 改动才会真正作用到系统闹钟上。
    static func appearanceFingerprint(
        label: String,
        ringtoneID: String?,
        snoozeEnabled: Bool
    ) -> String {
        [
            label,
            ringtoneID ?? RingtoneCatalog.systemDefaultID,
            snoozeEnabled ? "snooze" : "plain"
        ].joined(separator: "|")
    }

    // MARK: - 保留 ID

    /// 倒计时占用的系统闹钟 ID。
    ///
    /// 倒计时和闹钟共用 AlarmKit 的同一片 ID 空间，但对账逻辑是
    /// 「系统里有、这次不想要的，一律取消」——倒计时不在任何一份排期里，
    /// 所以**必须在 `reconcile` 里显式跳过**，否则每次刷新排期都会把
    /// 正在跑的倒计时顺手掐掉。
    static let countdownTimerID = uuid("DingClock.countdown.timer")

    /// 不属于「闹钟排期」的保留 ID。
    ///
    /// 以后再有功能往 AlarmKit 里放东西，在这里登记即可 ——
    /// `reconcile` / `scheduledCount` / `scheduledSystemDates` 三处都已按这个集合跳过。
    static let reservedIDs: Set<UUID> = [countdownTimerID]

    /// 这个 ID 是否不属于「闹钟排期」
    static func isReserved(_ id: UUID) -> Bool {
        reservedIDs.contains(id)
    }
}
