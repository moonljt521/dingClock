import SwiftUI

struct SettingsView: View {

    @EnvironmentObject private var store: AlarmStore

    /// 系统里实际排着的响铃日（审计用，不信任自己的计算，直接问系统要）
    @State private var audit: [AlarmStore.SystemAlarmAuditEntry] = []
    @State private var isAuditing = false

    var body: some View {
        NavigationStack {
            List {
                Section("响铃能力") {
                    LabeledContent("后端", value: store.scheduler.backendName)
                    LabeledContent("授权状态", value: store.authState.label)
                    LabeledContent("已排期", value: "\(store.scheduledCount) 次")

                    Button {
                        Task {
                            isAuditing = true
                            await store.refreshSchedule()
                            audit = await store.auditSystemAlarms()
                            isAuditing = false
                        }
                    } label: {
                        HStack {
                            Label("重新对账", systemImage: "checkmark.seal")
                            if isAuditing { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(isAuditing)
                }

                auditSection

                Section("说明") {
                    Text(store.scheduler.backendNote)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if !store.scheduler.isSupported {
                        Text(store.authState.guidance)
                            .font(.caption)
                            .foregroundStyle(Palette.makeup)
                    } else if store.authState != .authorized {
                        Button {
                            Task { await store.requestAuthorization() }
                        } label: {
                            Label("申请闹钟权限", systemImage: "bell.badge.fill")
                        }
                    }

                    if let error = store.lastError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                Section("节假日数据") {
                    LabeledContent("覆盖范围", value: store.holidayCoverage)
                    if let updated = store.holidayUpdatedAt {
                        LabeledContent("上次更新", value: updated.chineseDayLabel())
                    } else {
                        LabeledContent("上次更新", value: "仅使用内置数据")
                    }

                    Button {
                        Task { await store.refreshHolidayData(force: true) }
                    } label: {
                        HStack {
                            Label("立即更新", systemImage: "arrow.triangle.2.circlepath")
                            if store.isRefreshingHolidays {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(store.isRefreshingHolidays)

                    Text("数据来自国务院办公厅公告。内置 2024–2026 年数据，联网时自动同步最新年份。拉不到也不影响判定——会退回内置数据继续跑。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("手动例外") {
                    if store.sortedOverrides.isEmpty {
                        Text("还没有手动标记的日子")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(store.sortedOverrides, id: \.key) { item in
                            HStack(spacing: 8) {
                                Image(systemName: item.override.kind == .rest
                                      ? "hand.raised.slash.fill" : "hand.raised.fill")
                                    .font(.caption)
                                    .foregroundStyle(Palette.manual)
                                    .frame(width: 18)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.key).font(.subheadline).monospacedDigit()
                                    if !item.override.note.isEmpty {
                                        Text(item.override.note)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Text(item.override.kind.label)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .onDelete { offsets in
                            for index in offsets {
                                store.setOverride(key: store.sortedOverrides[index].key, kind: nil)
                            }
                            Task { await store.refreshSchedule() }
                        }
                    }
                    Text("手动标记优先于国家调休安排。在「响铃日历」里点任意一天即可添加。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("它是怎么工作的") {
                    ExplanationRow(
                        index: 1,
                        title: "判定日期属性",
                        detail: "先查这天在国务院文件里是什么：法定放假、调休补班，还是普通周几。"
                    )
                    ExplanationRow(
                        index: 2,
                        title: "展开成具体日期",
                        detail: "系统的重复闹钟只认「每周固定周几」，认不出节假日。所以要把未来 N 天里的每个工作日逐个展开。"
                    )
                    ExplanationRow(
                        index: 3,
                        title: "逐个排进系统",
                        detail: "每个工作日挂一个一次性系统闹钟，具体日期精确到秒。"
                    )
                    ExplanationRow(
                        index: 4,
                        title: "滚动刷新窗口",
                        detail: "每次回到前台或后台唤醒时重新对账，把窗口向前滚，永不落空。"
                    )
                }

                Section("关于") {
                    LabeledContent("版本", value: "1.0")
                    LabeledContent("包标识", value: "com.moonding.dingclock")
                }
            }
            .navigationTitle("设置")
        }
    }

    /// 系统对账：把 AlarmKit 里**实际**排着的日子读回来，逐条核对是否真是工作日。
    /// 我们自己算一百遍也不算数，得以系统为准 —— 这是「周末/假日不会响」的直接证据。
    private var auditSection: some View {
        Section("系统对账（实际排期）") {
            if audit.isEmpty {
                Text("还没有读回系统排期。点上面的「重新对账」。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                let mismatches = audit.filter(\.isMismatch)
                if mismatches.isEmpty {
                    Label("共 \(audit.count) 条，全部落在工作日 ✓", systemImage: "checkmark.seal.fill")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.green)
                } else {
                    Label("有 \(mismatches.count) 条不该响却排着，这是 bug", systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.red)
                }

                ForEach(audit) { entry in
                    HStack(spacing: 8) {
                        Text(entry.key)
                            .font(.system(.caption, design: .monospaced))
                            .frame(width: 84, alignment: .leading)
                        Text("周\(entry.weekday)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if entry.isMismatch {
                            Text("不该响 ⚠️")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.red)
                        } else {
                            Text(entry.reason)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Text("这是从 AlarmKit 读回来的系统真实排期，不是我们自己算的。休息日不该出现在这个列表里。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct ExplanationRow: View {
    let index: Int
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(index)")
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 20, height: 20)
                .background(Color.accentColor.opacity(0.16), in: Circle())
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.medium))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView().environmentObject(AlarmStore())
    }
}
