import SwiftUI

/// 倒计时页。
///
/// 界面只做三件事：显示还剩多久、选多久、开始/停。复杂的东西（锁屏倒计时、
/// 静音下响铃）全在系统那边，这里不重复造。
struct CountdownView: View {

    @EnvironmentObject private var store: AlarmStore
    @EnvironmentObject private var countdown: CountdownController

    @State private var isEditingDuration = false

    /// 常用时长。25 是番茄钟，其余是做饭/午休/泡面这类常见档位。
    private let quickMinutes = [1, 3, 5, 10, 15, 25, 30, 45, 60]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    readout

                    if countdown.isIdle {
                        quickPicks
                    }

                    controls

                    notices

                    Text(countdown.backendNote)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .navigationTitle("倒计时")
            .sheet(isPresented: $isEditingDuration) {
                DurationPickerSheet(seconds: Int(countdown.totalDuration)) { newValue in
                    countdown.setDuration(newValue)
                }
            }
        }
    }

    // MARK: - 读数

    /// 大号数字读数。
    ///
    /// 刻意不做进度环：倒计时真正要传达的信息只有一个 —— 还剩多久。
    /// 圆环既占地方，又得让人把角度换算回时间才能读，不如直接把数字放大。
    /// 数字变化用 `numericText` 过渡，这是 iOS 上数字跳动最标准的做法：
    /// 旧的往上走、新的从下面进来，不闪烁也不整块重绘。
    private var readout: some View {
        Group {
            if countdown.isRunning {
                // 只有跑起来才需要跟着秒走；停着的时候读数根本不变，不必空转
                TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                    readoutContent
                }
            } else {
                readoutContent
            }
        }
    }

    private var readoutContent: some View {
        // 用整秒做动画的触发值：同一秒内的重绘不该反复触发过渡
        let tick = Int(countdown.remaining.rounded(.up))

        return VStack(spacing: 12) {
            Text(Self.formatDuration(countdown.remaining))
                .font(.system(size: 76, weight: .thin, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .contentTransition(.numericText(countsDown: true))
                .animation(.snappy(duration: 0.3), value: tick)
                .foregroundStyle(countdown.isRinging ? Color.red : Color.primary)

            Text(statusText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
    }

    private var statusText: String {
        if countdown.isRinging { return "时间到" }
        switch countdown.phase {
        case .idle: return "准备好了"
        case .running: return "倒计时中"
        case .paused: return "已暂停"
        }
    }

    // MARK: - 时长

    private var quickPicks: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("时长")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3),
                spacing: 8
            ) {
                ForEach(quickMinutes, id: \.self) { minutes in
                    let selected = Int(countdown.totalDuration) == minutes * 60
                    Button {
                        countdown.setDuration(TimeInterval(minutes * 60))
                    } label: {
                        Text(Self.label(forMinutes: minutes))
                            .font(.subheadline.weight(selected ? .semibold : .regular))
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(selected
                                          ? Color.accentColor.opacity(0.16)
                                          : Color.secondary.opacity(0.10))
                            )
                            .foregroundStyle(selected ? Color.accentColor : Color.primary)
                    }
                    .buttonStyle(.plain)
                }
            }

            Button {
                isEditingDuration = true
            } label: {
                Label("自定义时长", systemImage: "slider.horizontal.3")
                    .font(.subheadline)
            }
            .padding(.top, 2)
        }
    }

    // MARK: - 按钮

    private var controls: some View {
        VStack(spacing: 12) {
            if countdown.isRinging {
                primaryButton("停止", icon: "stop.fill", tint: .red) {
                    Task { await countdown.stop() }
                }
            } else if countdown.isIdle {
                primaryButton("开始", icon: "play.fill", tint: .accentColor) {
                    Task { await countdown.start() }
                }
            } else if countdown.phase == .running {
                primaryButton("暂停", icon: "pause.fill", tint: .orange) {
                    Task { await countdown.pause() }
                }
                secondaryButton("取消倒计时") {
                    Task { await countdown.cancel() }
                }
            } else {
                primaryButton("继续", icon: "play.fill", tint: .accentColor) {
                    Task { await countdown.resume() }
                }
                secondaryButton("取消倒计时") {
                    Task { await countdown.cancel() }
                }
            }
        }
    }

    private func primaryButton(
        _ title: String,
        icon: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 14))
                .foregroundStyle(tint)
        }
        .buttonStyle(.plain)
    }

    private func secondaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 提示

    @ViewBuilder
    private var notices: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !countdown.isSupported {
                notice(
                    icon: "exclamationmark.triangle.fill",
                    tint: .orange,
                    text: "当前环境不会真的响铃，只能当个界面上的计时器。"
                )
            } else if store.authState != .authorized {
                notice(
                    icon: "bell.badge.fill",
                    tint: .orange,
                    text: "还没给闹钟权限，倒计时到点无法突破静音模式。"
                )
                Button {
                    Task { await store.requestAuthorization() }
                } label: {
                    Label("允许闹钟提醒", systemImage: "bell.badge.fill")
                        .font(.subheadline)
                }
            }

            if let error = countdown.lastError {
                notice(
                    icon: "xmark.octagon.fill",
                    tint: .red,
                    text: error
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func notice(icon: String, tint: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(tint)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - 格式化

    static func label(forMinutes minutes: Int) -> String {
        if minutes >= 60 {
            let h = minutes / 60
            let m = minutes % 60
            return m == 0 ? "\(h) 小时" : "\(h) 小时 \(m) 分"
        }
        return "\(minutes) 分钟"
    }

    /// 剩不到一小时就只显示 mm:ss，否则 h:mm:ss
    static func formatDuration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.up)))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }
}

// MARK: - 自定义时长

struct DurationPickerSheet: View {

    @Environment(\.dismiss) private var dismiss

    @State private var hours: Int
    @State private var minutes: Int
    @State private var seconds: Int

    let onCommit: (TimeInterval) -> Void

    init(seconds total: Int, onCommit: @escaping (TimeInterval) -> Void) {
        _hours = State(initialValue: total / 3600)
        _minutes = State(initialValue: (total % 3600) / 60)
        _seconds = State(initialValue: total % 60)
        self.onCommit = onCommit
    }

    var body: some View {
        NavigationStack {
            HStack(spacing: 0) {
                wheel(title: "时", value: $hours, range: 0..<24)
                wheel(title: "分", value: $minutes, range: 0..<60)
                wheel(title: "秒", value: $seconds, range: 0..<60)
            }
            .padding(.horizontal, 8)
            .navigationTitle("自定义时长")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        let total = TimeInterval(hours * 3600 + minutes * 60 + seconds)
                        onCommit(max(10, total))
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.height(320)])
    }

    private func wheel(title: String, value: Binding<Int>, range: Range<Int>) -> some View {
        Picker(title, selection: value) {
            ForEach(range, id: \.self) { number in
                Text("\(number) \(title)").tag(number)
            }
        }
        .pickerStyle(.wheel)
        .frame(maxWidth: .infinity)
        .labelsHidden()
    }
}

struct CountdownView_Previews: PreviewProvider {
    static var previews: some View {
        CountdownView()
            .environmentObject(AlarmStore())
            .environmentObject(CountdownController())
    }
}
