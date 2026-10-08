import SwiftUI

struct AlarmListView: View {

    @EnvironmentObject private var store: AlarmStore

    @State private var editingAlarm: AlarmModel?
    @State private var isCreating = false
    /// 用户拨关某个闹钟时暂存下来，等他回答「仅这次还是永久」
    @State private var pendingTurnOff: AlarmModel?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TodayStatusCard()
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 12, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }

                Section("闹钟") {
                    if store.alarms.isEmpty {
                        Text("还没有闹钟，点右上角加一个")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(store.alarms) { alarm in
                            AlarmRowView(
                                alarm: alarm,
                                onTap: { editingAlarm = alarm },
                                onTurnOn: { turnOn(alarm) },
                                onTurnOff: { pendingTurnOff = alarm }
                            )
                        }
                        .onDelete(perform: delete)
                    }
                }

                Section("响铃后端") {
                    BackendSummaryRow()
                }
            }
            .navigationTitle("叮咚")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isCreating = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("新建闹钟")
                }
            }
            .sheet(isPresented: $isCreating) {
                NavigationStack { AlarmEditView(alarm: AlarmModel()) }
            }
            .sheet(item: $editingAlarm) { alarm in
                NavigationStack { AlarmEditView(alarm: alarm) }
            }
            .confirmationDialog(
                turnOffTitle,
                isPresented: Binding(
                    get: { pendingTurnOff != nil },
                    set: { if !$0 { pendingTurnOff = nil } }
                ),
                titleVisibility: .visible,
                presenting: pendingTurnOff
            ) { alarm in
                Button("仅这次关闭") {
                    store.skipNextFire(alarm)
                    Task { await store.refreshSchedule() }
                }
                Button("永久关闭", role: .destructive) {
                    store.disablePermanently(alarm)
                    Task { await store.refreshSchedule() }
                }
                Button("取消", role: .cancel) {}
            } message: { alarm in
                Text(turnOffMessage(for: alarm))
            }
        }
    }

    private var turnOffTitle: String {
        "关闭「\(pendingTurnOff?.label ?? "闹钟")」？"
    }

    private func turnOffMessage(for alarm: AlarmModel) -> String {
        if let next = store.nextFire(for: alarm) {
            return "「仅这次」跳过 \(next.fireDate.relativeDescription()) 这一次，之后照常响；「永久关闭」会停用这个闹钟，直到你手动打开。"
        }
        return "「仅这次」跳过下一次响铃，之后照常响；「永久关闭」会停用这个闹钟，直到你手动打开。"
    }

    private func turnOn(_ alarm: AlarmModel) {
        store.turnOn(alarm)
        Task { await store.refreshSchedule() }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets { store.delete(store.alarms[index]) }
        Task { await store.refreshSchedule() }
    }
}

// MARK: - 顶部状态卡

struct TodayStatusCard: View {

    @EnvironmentObject private var store: AlarmStore
    /// 点徽标弹出文案编辑
    @State private var showBadgeEditor = false

    var body: some View {
        let now = Date()
        let kind = store.kind(for: now)
        let next = store.upcomingFires(limit: 1, from: now).first

        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(now.chineseDayLabel())
                    .font(.headline)
                Spacer()
                Label(kind.isWorkday ? store.workdayBadge : store.restBadge, systemImage: kind.symbolName)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(kind.tint.opacity(0.16), in: Capsule())
                    .foregroundStyle(kind.tint)
                    .onTapGesture { showBadgeEditor = true }
            }

            Text(kind.reason)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Divider()

            if let next {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(next.fireDate.relativeDescription(from: now))
                        .font(.title3.weight(.medium))
                    Text(next.label)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text(store.alarms.isEmpty ? "还没有闹钟" : "接下来没有排定的响铃")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .sheet(isPresented: $showBadgeEditor) {
            BadgeTextEditorView()
                .presentationDetents([.medium])
        }
    }
}

// MARK: - 顶部徽标文案编辑（点首页徽标弹出）

struct BadgeTextEditorView: View {

    @EnvironmentObject private var store: AlarmStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("上班日的徽标") {
                    TextField(AlarmStore.defaultWorkdayBadge, text: $store.badgeWorkdayText)
                }
                Section("休息日的徽标") {
                    TextField(AlarmStore.defaultRestBadge, text: $store.badgeRestText)
                }
                Section {
                    Text("首页顶部那枚徽标会显示你填的字。清空即恢复默认「\(AlarmStore.defaultWorkdayBadge)」/「\(AlarmStore.defaultRestBadge)」。")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button(role: .destructive) {
                        store.resetBadgeText()
                    } label: {
                        Label("恢复默认文案", systemImage: "arrow.uturn.backward")
                    }
                }
            }
            .navigationTitle("顶部文案")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}

// MARK: - 单条闹钟

struct AlarmRowView: View {

    @EnvironmentObject private var store: AlarmStore

    let alarm: AlarmModel
    var onTap: () -> Void
    /// 用户把开关拨开
    var onTurnOn: () -> Void
    /// 用户把开关拨关 —— 不直接关，交给上层问「仅这次还是永久」
    var onTurnOff: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(alarm.timeDescription)
                    .font(.system(size: 42, weight: .light, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(alarm.isOn ? Color.primary : Color.secondary)

                Spacer()

                // 注意这里读的是 isOn 而不是 isEnabled：
                // 「仅这次关闭」之后 isEnabled 仍是 true，但开关必须显示成关的。
                Toggle("", isOn: Binding(
                    get: { alarm.isOn },
                    set: { newValue in
                        if newValue { onTurnOn() } else { onTurnOff() }
                    }
                ))
                .labelsHidden()
            }

            HStack(spacing: 8) {
                Text(alarm.label)
                    .font(.subheadline.weight(.medium))
                PatternBadge(text: alarm.patternDescription)
                if alarm.skippedFireDate != nil {
                    PatternBadge(text: "仅这次已跳过")
                }
            }
            .foregroundStyle(alarm.isOn ? Color.primary : Color.secondary)

            if let skipped = alarm.skippedFireDate {
                HStack(spacing: 5) {
                    Image(systemName: "moon.zzz.fill")
                        .font(.system(size: 10))
                    Text("跳过 \(skipped.relativeDescription()) 这一次，之后照常响")
                        .font(.caption)
                }
                .foregroundStyle(Palette.manual)
            }

            if let next = store.nextFire(for: alarm) {
                HStack(spacing: 5) {
                    Image(systemName: Palette.symbol(for: next.dayKind))
                        .font(.system(size: 10))
                    Text("下次 \(next.fireDate.relativeDescription()) · \(next.dayKind.reason)")
                        .font(.caption)
                }
                .foregroundStyle(next.dayKind.tint)
            } else {
                Text(alarm.isEnabled ? "当前设置下不会响铃" : "已关闭，不再响铃")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            WeekStripView(alarm: alarm)
                .padding(.top, 2)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}

struct PatternBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Color.secondary.opacity(0.14), in: Capsule())
            .foregroundStyle(.secondary)
    }
}

/// 未来 7 天的响/静小圆点
struct WeekStripView: View {

    @EnvironmentObject private var store: AlarmStore

    let alarm: AlarmModel

    var body: some View {
        let previews = store.planner.preview(
            for: alarm,
            workday: store.workdayCalendar(for: alarm),
            days: 7
        )

        HStack(spacing: 4) {
            ForEach(previews) { day in
                VStack(spacing: 3) {
                    Text(WeekdaySymbols.chinese(forWeekday: store.planner.calendar.component(.weekday, from: day.date)))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Circle()
                        .fill(day.rings ? Palette.tint(for: day.kind) : Color.secondary.opacity(0.22))
                        .frame(width: 8, height: 8)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

// MARK: - 后端状态

struct BackendSummaryRow: View {

    @EnvironmentObject private var store: AlarmStore

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: store.scheduler.isSupported ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(store.scheduler.isSupported ? Color.green : Color.orange)
                Text(store.scheduler.backendName)
                    .font(.subheadline.weight(.medium))
            }
            Text(store.scheduler.backendNote)
                .font(.caption)
                .foregroundStyle(.secondary)
            if !store.statusMessage.isEmpty {
                Text(store.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

struct AlarmListView_Previews: PreviewProvider {
    static var previews: some View {
        AlarmListView().environmentObject(AlarmStore())
    }
}
