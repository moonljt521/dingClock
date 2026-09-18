import SwiftUI
import AVFoundation

/// 编辑界面的重复模式选项。
/// 注意「工作日（含调休）」与「周一至周五」的差别 —— 前者正是 iOS 27 时钟 App 新增的能力。
enum AlarmEditMode: String, CaseIterable, Identifiable {
    case stateWorkday
    case fiveDay
    case bigSmall
    case custom
    case once

    var id: String { rawValue }

    var title: String {
        switch self {
        case .stateWorkday: return "工作日（含调休）"
        case .fiveDay: return "周一至周五"
        case .bigSmall: return "大小周"
        case .custom: return "自定义星期"
        case .once: return "只响一次"
        }
    }

    var subtitle: String {
        switch self {
        case .stateWorkday: return "跳过周末和法定节假日，调休补班日照响"
        case .fiveDay: return "只看周几，不管节假日与调休"
        case .bigSmall: return "小周周六上班，大周双休"
        case .custom: return "自己挑一周里哪几天响"
        case .once: return "指定某一天响一次"
        }
    }
}

struct AlarmEditView: View {

    @EnvironmentObject private var store: AlarmStore
    @Environment(\.dismiss) private var dismiss

    @State private var alarm: AlarmModel
    @State private var mode: AlarmEditMode
    @State private var customDays: Set<Int>
    @State private var anchorIsSmallWeek: Bool
    @State private var respectsState: Bool
    @State private var timeDate: Date
    @State private var onceDate: Date
    /// 铃声试听用。AlarmKit 没有"试听"API，这里是 AVFoundation 本地播放
    @State private var previewPlayer: AVAudioPlayer?
    @State private var isPreviewing = false
    /// 包内缺音频资源时置真（打包流程漏了资源，如实提示而不是无声失败）
    @State private var previewMissing = false

    /// 当前选中的铃声 id（nil 视作系统默认）
    private var selectedRingtoneID: String {
        alarm.ringtoneID ?? RingtoneCatalog.systemDefaultID
    }

    /// 铃声绑定为非可选（nil 一律视作系统默认）
    private var ringtoneBinding: Binding<String> {
        Binding(
            get: { selectedRingtoneID },
            set: { newValue in
                stopPreview()
                alarm.ringtoneID = (newValue == RingtoneCatalog.systemDefaultID) ? nil : newValue
                // 换铃声立即试听新效果，不用再手动点
                if RingtoneCatalog.soundName(forID: newValue) != nil {
                    startPreview()
                }
            }
        )
    }

    /// 拆成独立属性：整段塞在 body 里会让 Swift 的类型检查器超时
    private var ringtonePicker: some View {
        Picker("铃声", selection: ringtoneBinding) {
            ForEach(RingtoneCatalog.all) { ringtone in
                Text(ringtone.label).tag(ringtone.id)
            }
        }
    }

    private func startPreview() {
        // 关键：默认音频类别 .soloAmbient 会跟着手机侧面的静音拨片走——
        // 拨片一拨静音就一点声都没有（这正是"一直在转圈听不到声"的原因）。
        // .playback 无视静音开关，保证试听一定能听见。
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default)
        try? session.setActive(true)

        guard let fileName = RingtoneCatalog.soundName(forID: selectedRingtoneID) else { return }
        guard let url = Bundle.main.url(forResource: fileName, withExtension: "caf") else {
            previewMissing = true
            return
        }
        previewMissing = false
        previewPlayer = try? AVAudioPlayer(contentsOf: url)
        // 循环播放，直到手动停或换铃声 —— 闹钟声本来就是要循环的
        previewPlayer?.numberOfLoops = -1
        previewPlayer?.prepareToPlay()
        // play() 可能失败（资源缺失/会话被占），失败就不进入"播放中"状态
        isPreviewing = ((previewPlayer?.play()) == true)
        if !isPreviewing { previewPlayer = nil }
    }

    private func stopPreview() {
        previewPlayer?.stop()
        previewPlayer = nil
        isPreviewing = false
    }

    init(alarm: AlarmModel) {
        _alarm = State(initialValue: alarm)

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        _timeDate = State(initialValue: calendar.date(
            byAdding: DateComponents(hour: alarm.hour, minute: alarm.minute),
            to: today
        ) ?? Date())

        var resolvedMode: AlarmEditMode = .stateWorkday
        var days: Set<Int> = [2, 3, 4, 5, 6]
        var isSmall = true
        var once = calendar.date(byAdding: .day, value: 1, to: today) ?? Date()

        switch alarm.repeatMode {
        case .fiveDay:
            resolvedMode = alarm.respectsStateHolidays ? .stateWorkday : .fiveDay
        case .alternatingBigSmall(_, let small):
            resolvedMode = .bigSmall
            isSmall = small
        case .custom(let d):
            resolvedMode = .custom
            if !d.isEmpty { days = d }
        case .once(let d):
            resolvedMode = .once
            once = d
        }

        _mode = State(initialValue: resolvedMode)
        _customDays = State(initialValue: days)
        _anchorIsSmallWeek = State(initialValue: isSmall)
        _respectsState = State(initialValue: alarm.respectsStateHolidays)
        _onceDate = State(initialValue: once)
    }

    var body: some View {
        Form {
            Section {
                DatePicker("响铃时间", selection: $timeDate, displayedComponents: .hourAndMinute)
                TextField("标签", text: $alarm.label)
            }

            Section("重复") {
                ForEach(AlarmEditMode.allCases) { candidate in
                    Button {
                        mode = candidate
                        if candidate == .stateWorkday { respectsState = true }
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(candidate.title)
                                    .foregroundStyle(Color.primary)
                                Text(candidate.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if mode == candidate {
                                Image(systemName: "checkmark")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            if mode == .bigSmall {
                Section("大小周") {
                    Toggle("本周是小周（周六上班）", isOn: $anchorIsSmallWeek)
                    Text("小周单休、大周双休，每两周轮换一次。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if mode == .custom {
                Section("哪几天响") {
                    WeekdaySelector(selection: $customDays)
                    Text("已选：\(WeekPattern.customLabel(for: customDays))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if mode == .once {
                Section("日期") {
                    DatePicker("响铃日期", selection: $onceDate, displayedComponents: .date)
                    if !onceKind.isWorkday {
                        Label("这天是\(onceKind.reason)，确认要响吗？", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(Palette.makeup)
                    }
                }
            }

            if mode == .bigSmall || mode == .custom {
                Section("节假日") {
                    Toggle("跟随国务院放假与调休安排", isOn: $respectsState)
                    Text("不开的话，就完全按你选的星期来，不管国家调休。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("铃声") {
                ringtonePicker

                if RingtoneCatalog.soundName(forID: selectedRingtoneID) != nil {
                    if previewMissing {
                        Label("铃声资源缺失，请更新 App", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    } else {
                        Button {
                            isPreviewing ? stopPreview() : startPreview()
                        } label: {
                            Label(isPreviewing ? "停止试听" : "试听铃声",
                                  systemImage: isPreviewing ? "stop.circle.fill" : "play.circle")
                        }
                        .foregroundStyle(isPreviewing ? .red : Color.accentColor)
                    }
                } else {
                    Text("系统默认铃声无试听。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("响铃时手机震不震由系统「声音与触感 → 触感」决定；想要轻一点可以选「轻柔渐强」。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if mode != .once {
                Section("高级") {
                    Toggle("稍后提醒", isOn: $alarm.snoozeEnabled)
                    Stepper(value: $alarm.windowDays, in: 7...60, step: 7) {
                        HStack {
                            Text("排期窗口")
                            Spacer()
                            Text("\(alarm.windowDays) 天")
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text("窗口内的工作日会被逐个排进系统。窗口越长越稳，App 每次回到前台会自动向前滚动。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("接下来会响") {
                if previews.isEmpty {
                    Text("按当前设置，接下来不会响")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(previews) { fire in
                        HStack(spacing: 8) {
                            Image(systemName: Palette.symbol(for: fire.dayKind))
                                .font(.caption)
                                .foregroundStyle(Palette.tint(for: fire.dayKind))
                                .frame(width: 16)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(fire.fireDate.relativeDescription())
                                    .font(.subheadline)
                                Text(fire.dayKind.reason)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(alarm.label.isEmpty ? "闹钟" : alarm.label)
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { stopPreview() }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") { save() }
                    .fontWeight(.semibold)
            }
        }
    }

    // MARK: - 派生

    private var onceKind: DayKind {
        store.kind(for: onceDate)
    }

    private var draft: AlarmModel { build() }

    private var previews: [PlannedFire] {
        store.planner.fires(
            for: draft,
            workday: draft.workdayCalendar(holidays: store.holidays, overrides: store.overrides),
            from: Date(),
            maxCount: 3
        )
    }

    private func build() -> AlarmModel {
        var result = alarm
        let calendar = Calendar.current

        let comps = calendar.dateComponents([.hour, .minute], from: timeDate)
        result.hour = comps.hour ?? alarm.hour
        result.minute = comps.minute ?? alarm.minute

        switch mode {
        case .stateWorkday:
            result.repeatMode = .fiveDay
            result.respectsStateHolidays = true

        case .fiveDay:
            result.repeatMode = .fiveDay
            result.respectsStateHolidays = false

        case .bigSmall:
            // 锚点必须沿用原有的，否则每保存一次大小周的奇偶就翻一次
            let anchor: Date
            if case .alternatingBigSmall(let existing, _) = alarm.repeatMode {
                anchor = existing
            } else {
                anchor = WeekPattern.startOfWeek(for: Date())
            }
            result.repeatMode = .alternatingBigSmall(anchor: anchor, anchorIsSmallWeek: anchorIsSmallWeek)
            result.respectsStateHolidays = respectsState

        case .custom:
            result.repeatMode = .custom(customDays.isEmpty ? [2, 3, 4, 5, 6] : customDays)
            result.respectsStateHolidays = respectsState

        case .once:
            var c = calendar.dateComponents([.year, .month, .day], from: onceDate)
            c.hour = result.hour
            c.minute = result.minute
            c.second = 0
            result.repeatMode = .once(calendar.date(from: c) ?? onceDate)
            result.respectsStateHolidays = respectsState
        }
        return result
    }

    private func save() {
        store.upsert(build())
        Task { await store.refreshSchedule() }
        dismiss()
    }
}

/// 七个圆钮，选一周里哪几天响
struct WeekdaySelector: View {

    @Binding var selection: Set<Int>

    /// 按周一到周日排列，周日（1）放最后
    private let ordered = [2, 3, 4, 5, 6, 7, 1]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(ordered, id: \.self) { weekday in
                let isOn = selection.contains(weekday)
                Button {
                    if isOn { selection.remove(weekday) } else { selection.insert(weekday) }
                } label: {
                    Text(WeekdaySymbols.chinese(forWeekday: weekday))
                        .font(.system(size: 14, weight: isOn ? .semibold : .regular))
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(
                            Circle().fill(isOn ? Color.accentColor : Color.secondary.opacity(0.14))
                        )
                        .foregroundStyle(isOn ? Color.white : Color.primary)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct AlarmEditView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            AlarmEditView(alarm: AlarmModel())
        }
        .environmentObject(AlarmStore())
    }
}
