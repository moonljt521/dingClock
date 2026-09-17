import SwiftUI
import WidgetKit

/// 灵动岛 / 锁屏上的闹钟呈现。
///
/// AlarmKit 的闹钟在**响铃时由系统渲染**，我们不需要自绘；
/// 但倒计时与暂停这两种状态需要 App 提供 Live Activity 界面，
/// 所以必须有这个 Widget Extension。
///
/// 实现上刻意只依赖两类东西：
/// 1. `AlarmAttributes.presentation.alert.title`（Apple 官方示例用法）
/// 2. 我们自己的 `DingClockAlarmMetadata`（含 `fireDate`，用来渲染倒计时）
///
/// 这样就不必去猜 `AlarmPresentationState` 各状态内部的字段命名。
@main
struct DingClockWidgetBundle: WidgetBundle {
    @WidgetBundleBuilder
    var body: some Widget {
        DingClockAlarmWidget()
    }
}

#if canImport(AlarmKit)
import AlarmKit

/// 接入 AlarmKit 后的真·闹钟 Live Activity
struct DingClockAlarmWidget: Widget {

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmAttributes<DingClockAlarmMetadata>.self) { context in
            AlarmLockScreenView(context: context)
                .activityBackgroundTint(Color.orange.opacity(0.10))
                .activitySystemActionForegroundColor(.orange)

        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "alarm.fill")
                        .foregroundStyle(.orange)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.attributes.metadata?.alarmLabel ?? "闹钟")
                            .font(.caption.weight(.semibold))
                        Text(context.attributes.metadata?.dayReason ?? "")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    AlarmCountdownText(context: context, maxWidth: 60)
                }
            } compactLeading: {
                Image(systemName: "alarm.fill")
                    .foregroundStyle(.orange)
            } compactTrailing: {
                AlarmCountdownText(context: context, maxWidth: 42)
            } minimal: {
                Image(systemName: "alarm.fill")
                    .foregroundStyle(.orange)
            }
        }
    }
}

/// 锁屏呈现
struct AlarmLockScreenView: View {
    let context: ActivityViewContext<AlarmAttributes<DingClockAlarmMetadata>>

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "alarm.fill")
                    .foregroundStyle(.orange)
                Text(context.attributes.presentation.alert.title.key)
                    .font(.headline)
                Spacer()
                AlarmCountdownText(context: context, maxWidth: 90)
            }
            Text(context.attributes.metadata?.dayReason ?? "")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
    }
}

/// 倒计时文本。时刻来自我们自己的 metadata，只用到标准 SwiftUI 的 `Text(timerInterval:)`。
struct AlarmCountdownText: View {
    let context: ActivityViewContext<AlarmAttributes<DingClockAlarmMetadata>>
    var maxWidth: CGFloat

    @ViewBuilder
    var body: some View {
        if let fireDate = context.attributes.metadata?.fireDate, fireDate > Date() {
            Text(timerInterval: Date()...fireDate, countsDown: true)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .monospacedDigit()
                .frame(maxWidth: maxWidth)
        } else {
            Text("响铃中")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)
        }
    }
}

#else

/// 没有 iOS 26 SDK 时的占位 Widget。
///
/// 存在的唯一目的是让 Widget Extension 目标保持可编译、可打包，等 Xcode 26 到位后
/// 自动切换到上面的 AlarmKit 版本（`canImport` 会在那时变成真）。
struct DingClockAlarmWidget: Widget {

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "DingClockPlaceholder", provider: PlaceholderProvider()) { entry in
            VStack(spacing: 6) {
                Image(systemName: "alarm.fill")
                    .foregroundStyle(.orange)
                Text("叮咚")
                    .font(.headline)
                Text(entry.message)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("叮咚")
        .description("需要 iOS 26 SDK 才能显示闹钟倒计时")
        .supportedFamilies([.systemSmall])
    }
}

struct PlaceholderProvider: TimelineProvider {
    struct Entry: TimelineEntry {
        let date: Date
        let message: String
    }

    func placeholder(in context: Context) -> Entry {
        Entry(date: Date(), message: "等待接入 AlarmKit")
    }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(Entry(date: Date(), message: "等待接入 AlarmKit"))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        let entry = Entry(date: Date(), message: "需要 Xcode 26 + iOS 26 SDK")
        completion(Timeline(entries: [entry], policy: .never))
    }
}

#endif
