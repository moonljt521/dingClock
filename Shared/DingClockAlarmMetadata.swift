import Foundation

#if canImport(AlarmKit)
import AlarmKit

/// 挂在闹钟上的自定义数据。AlarmKit 会把它传给 Live Activity，
/// 让锁屏和灵动岛能显示「这次几点响、今天为什么响」。
///
/// 放在共享目录里，是因为主 App（下发排期）和 Widget Extension
/// （渲染 Live Activity）必须使用**同一个** metadata 类型。
///
/// 刻意把 `fireDate` 一并带上：Live Activity 因此可以只依赖我们自己定义的类型
/// 来渲染倒计时，而不必去猜 `AlarmPresentationState` 内部各状态的字段名。
struct DingClockAlarmMetadata: AlarmMetadata {
    /// 闹钟标签，比如「起床」
    var alarmLabel: String
    /// 这天的日期属性说明，比如「国庆节 · 调休补班」
    var dayReason: String
    /// 这次响铃的确切时刻
    var fireDate: Date
}
#endif
