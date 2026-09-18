import SwiftUI

struct SettingsView: View {

    @EnvironmentObject private var store: AlarmStore

    var body: some View {
        NavigationStack {
            List {
                Section("闹钟权限") {
                    LabeledContent("授权状态", value: store.authState.label)

                    if store.scheduler.isSupported {
                        Text("闹钟由系统接管，能突破静音模式与专注模式，锁屏和灵动岛同步显示。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(store.authState.guidance)
                            .font(.caption)
                            .foregroundStyle(Palette.makeup)
                    }

                    if store.authState != .authorized {
                        Button {
                            Task { await store.requestAuthorization() }
                        } label: {
                            Label("允许闹钟提醒", systemImage: "bell.badge.fill")
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

                Section("关于") {
                    LabeledContent("版本", value: "1.0")
                }

            }
            .navigationTitle("设置")
        }
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView().environmentObject(AlarmStore())
    }
}
