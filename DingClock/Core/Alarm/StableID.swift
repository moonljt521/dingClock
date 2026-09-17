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
    static func fireSeed(alarmID: UUID, fireDate: Date, calendar: Calendar = .current) -> String {
        "\(alarmID.uuidString)@\(DateKey.timestamp(fireDate, calendar: calendar))"
    }

    /// 某个闹钟在某个具体时刻的系统闹钟 ID
    static func fireID(alarmID: UUID, fireDate: Date, calendar: Calendar = .current) -> UUID {
        uuid(fireSeed(alarmID: alarmID, fireDate: fireDate, calendar: calendar))
    }
}
