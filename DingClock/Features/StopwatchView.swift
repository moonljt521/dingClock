import SwiftUI

/// 秒表页。
///
/// 界面只做三件事：显示读数、开始/停、计次。没有任何提醒相关的东西 ——
/// 秒表就是用来量时间的，要「到点提醒」那是倒计时该干的事。
struct StopwatchView: View {

    @EnvironmentObject private var stopwatch: StopwatchController

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                timeDisplay
                controls

                if stopwatch.hasLaps {
                    Divider()
                    lapList
                        .frame(maxHeight: .infinity)
                } else {
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 12)
            .navigationTitle("秒表")
        }
    }

    // MARK: - 读数

    private var timeDisplay: some View {
        Group {
            if stopwatch.isRunning {
                // 只有跑起来才需要高频刷新；停着的时候一次就够，不必每秒重绘
                TimelineView(.periodic(from: .now, by: 1.0 / 60.0)) { _ in
                    readout
                }
            } else {
                readout
            }
        }
    }

    private var readout: some View {
        Text(StopwatchController.format(stopwatch.elapsed))
            .font(.system(size: 58, weight: .thin, design: .rounded))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
    }

    // MARK: - 按钮

    private var controls: some View {
        HStack(spacing: 14) {
            Button {
                if stopwatch.isRunning {
                    stopwatch.lap()
                } else {
                    stopwatch.reset()
                }
            } label: {
                Text(stopwatch.leftButtonTitle)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(Color.secondary.opacity(0.12), in: Capsule())
                    .foregroundStyle(stopwatch.canUseLeftButton ? Color.primary : Color.secondary.opacity(0.45))
            }
            .buttonStyle(.plain)
            .disabled(!stopwatch.canUseLeftButton)

            Button {
                stopwatch.toggle()
            } label: {
                Text(stopwatch.primaryButtonTitle)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(primaryTint.opacity(0.16), in: Capsule())
                    .foregroundStyle(primaryTint)
            }
            .buttonStyle(.plain)
        }
    }

    /// 开始/继续用绿，停止用红 —— 和系统时钟 App 的习惯一致
    private var primaryTint: Color {
        stopwatch.isRunning ? .red : .green
    }

    // MARK: - 计次列表

    private var lapList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(stopwatch.laps) { lap in
                    HStack(spacing: 8) {
                        Text("计次 \(lap.index)")
                            .foregroundStyle(.secondary)
                            .frame(width: 68, alignment: .leading)

                        Text(StopwatchController.format(lap.split))
                            .frame(maxWidth: .infinity, alignment: .trailing)

                        Text(StopwatchController.format(lap.total))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .font(.system(size: 15, design: .rounded))
                    .monospacedDigit()
                    .padding(.vertical, 11)

                    Divider()
                }
            }
        }
    }
}

struct StopwatchView_Previews: PreviewProvider {
    static var previews: some View {
        StopwatchView().environmentObject(StopwatchController())
    }
}
