import SwiftUI

struct RootView: View {

    @EnvironmentObject private var store: AlarmStore
    @Environment(\.scenePhase) private var scenePhase

    /// 启动时默认停在哪个标签页。可以通过环境变量 `DINGCLOCK_TAB` 指定，
    /// 方便截图与自动化验证（`simctl launch` 用 `SIMCTL_CHILD_DINGCLOCK_TAB=1` 传入）。
    @State private var selection: Int = RootView.initialTab

    /// 0=闹钟 1=倒计时 2=秒表 3=响铃日历 4=设置
    static var initialTab: Int {
        guard let raw = ProcessInfo.processInfo.environment["DINGCLOCK_TAB"],
              let index = Int(raw) else { return 0 }
        return min(max(index, 0), 4)
    }

    var body: some View {
        TabView(selection: $selection) {
            AlarmListView()
                .tabItem { Label("闹钟", systemImage: "alarm.fill") }
                .tag(0)

            CountdownView()
                .tabItem { Label("倒计时", systemImage: "timer") }
                .tag(1)

            StopwatchView()
                .tabItem { Label("秒表", systemImage: "stopwatch") }
                .tag(2)

            SchedulePreviewView()
                .tabItem { Label("响铃日历", systemImage: "calendar") }
                .tag(3)

            SettingsView()
                .tabItem { Label("设置", systemImage: "gearshape.fill") }
                .tag(4)
        }
        .task {
            await store.bootstrap()
        }
        .onChange(of: scenePhase) { _, phase in
            // 每次回到前台：节假日数据限频刷新（国务院改了调休会自动跟上）+ 排期对账
            guard phase == .active, store.didBootstrap else { return }
            Task { await store.refreshOnForeground() }
        }
    }
}

// 用 PreviewProvider（协议）而不是 #Preview（宏）：
// 宏需要编译期启动 swift-plugin-server 做展开，对工具链状态有硬依赖；
// 协议式预览不需要任何插件，稳定性优先。
struct RootView_Previews: PreviewProvider {
    static var previews: some View {
        RootView().environmentObject(AlarmStore())
    }
}
