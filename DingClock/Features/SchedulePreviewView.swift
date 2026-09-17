import SwiftUI

/// 「响铃日历」—— 这个 App 的杀手锏。
///
/// 把一个月的每一天都标出来：响还是不响、几点响、为什么不响。
/// 用户不需要相信我们的算法，看一眼就懂了。
struct SchedulePreviewView: View {

    @EnvironmentObject private var store: AlarmStore

    @State private var monthAnchor: Date = Date()
    @State private var selection: DaySelection?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    monthHeader
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)

                    calendarGrid
                        .listRowInsets(EdgeInsets(top: 0, leading: 12, bottom: 8, trailing: 12))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)

                    legend
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 8, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }

                Section("接下来的响铃") {
                    let fires = store.upcomingFires(limit: 6)
                    if fires.isEmpty {
                        Text("没有已排定的响铃")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(fires) { fire in
                            HStack(spacing: 10) {
                                Image(systemName: Palette.symbol(for: fire.dayKind))
                                    .font(.caption)
                                    .foregroundStyle(Palette.tint(for: fire.dayKind))
                                    .frame(width: 18)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(fire.fireDate.relativeDescription())
                                        .font(.subheadline.weight(.medium))
                                    Text("\(fire.label) · \(fire.dayKind.reason)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                Section {
                    Text("点日历里的任意一天，可以手动把它标记成「放假」或「上班」——优先级高于国家调休安排。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("响铃日历")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("今天") { monthAnchor = Date() }
                        .font(.footnote)
                }
            }
            .sheet(item: $selection) { sel in
                NavigationStack { DayOverrideSheet(date: sel.date) }
            }
        }
    }

    // MARK: - 头部

    private var monthHeader: some View {
        HStack {
            Button {
                shiftMonth(-1)
            } label: {
                Image(systemName: "chevron.left").font(.body.weight(.semibold))
            }
            .buttonStyle(.plain)

            Spacer()
            VStack(spacing: 2) {
                Text(monthAnchor.chineseMonthTitle)
                    .font(.headline)
                Text(monthSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()

            Button {
                shiftMonth(1)
            } label: {
                Image(systemName: "chevron.right").font(.body.weight(.semibold))
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 6)
    }

    private var monthSummary: String {
        let counts = monthStats
        return "\(counts.ring) 天响铃 · \(counts.special) 天特殊安排"
    }

    private var monthStats: (ring: Int, special: Int) {
        var ring = 0, special = 0
        for date in monthDays {
            if fireTimes(for: date) != nil { ring += 1 }
            if store.kind(for: date).isSpecialArrangement { special += 1 }
        }
        return (ring, special)
    }

    // MARK: - 日历网格

    private var calendarGrid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
        return VStack(spacing: 6) {
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(Array(WeekdaySymbols.chinese.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(Array(gridCells.enumerated()), id: \.offset) { _, cell in
                    if let date = cell {
                        DayCellView(
                            date: date,
                            kind: store.kind(for: date),
                            fireTimes: fireTimes(for: date) ?? [],
                            isToday: Calendar.current.isDateInToday(date),
                            hasOverride: store.override(for: date) != nil
                        )
                        .onTapGesture { selection = DaySelection(date: date) }
                    } else {
                        Color.clear.frame(height: 48)
                    }
                }
            }
        }
    }

    private var legend: some View {
        HStack(spacing: 14) {
            legendItem(color: Palette.workday, text: "响铃")
            legendItem(color: Palette.makeup, text: "调休补班")
            legendItem(color: Palette.holiday, text: "法定放假")
            legendItem(color: Palette.rest, text: "周末")
            Spacer()
        }
    }

    private func legendItem(color: Color, text: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text).font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    // MARK: - 数据

    private var gridCells: [Date?] {
        let calendar = store.planner.calendar
        guard let first = calendar.date(from: calendar.dateComponents([.year, .month], from: monthAnchor)),
              let range = calendar.range(of: .day, in: .month, for: first) else { return [] }

        let leading = calendar.component(.weekday, from: first) - 1 // 表头从周日开始
        var cells: [Date?] = Array(repeating: nil, count: max(0, leading))
        for offset in 0..<range.count {
            cells.append(calendar.date(byAdding: .day, value: offset, to: first))
        }
        while cells.count % 7 != 0 { cells.append(nil) }
        return cells
    }

    private var monthDays: [Date] { gridCells.compactMap { $0 } }

    /// 该月内每天的响铃时刻（取所有已启用闹钟里最早的一次）
    private func fireTimes(for date: Date) -> [Date]? {
        let calendar = store.planner.calendar
        let key = DateKey.string(date, calendar: calendar)
        var times: [Date] = []
        for alarm in store.alarms where alarm.isEnabled {
            let previews = store.planner.preview(
                for: alarm,
                workday: store.workdayCalendar(for: alarm),
                from: date,
                days: 1
            )
            if let p = previews.first, p.rings, let fire = p.fireDate {
                times.append(fire)
            }
        }
        return times.isEmpty ? nil : times.sorted()
    }

    private func shiftMonth(_ delta: Int) {
        if let next = store.planner.calendar.date(byAdding: .month, value: delta, to: monthAnchor) {
            monthAnchor = next
        }
    }
}

// MARK: - 单格

struct DayCellView: View {

    let date: Date
    let kind: DayKind
    let fireTimes: [Date]
    let isToday: Bool
    let hasOverride: Bool

    var body: some View {
        let rings = !fireTimes.isEmpty
        let tint = Palette.tint(for: kind)

        VStack(spacing: 1) {
            Text("\(Calendar.current.component(.day, from: date))")
                .font(.system(size: 15, weight: isToday ? .bold : .regular))
                .foregroundStyle(rings ? tint : Color.primary.opacity(0.75))

            if let first = fireTimes.first {
                Text(Self.timeFormatter.string(from: first))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(tint)
            } else {
                Text(kind.shortLabel)
                    .font(.system(size: 10))
                    .foregroundStyle(tint.opacity(0.9))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 48)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(rings ? tint.opacity(0.16) : Color.secondary.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    isToday ? Color.primary.opacity(0.5) : (hasOverride ? Palette.manual : Color.clear),
                    lineWidth: isToday ? 1.5 : 1.2
                )
        )
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        return f
    }()
}

// MARK: - 选中某天

struct DaySelection: Identifiable {
    let id = UUID()
    let date: Date
}

/// 手动标记某一天。优先级高于国务院调休安排——
/// 因为很多公司（尤其是大小周的公司）并不跟着国家调休走。
struct DayOverrideSheet: View {

    @EnvironmentObject private var store: AlarmStore
    @Environment(\.dismiss) private var dismiss

    let date: Date

    @State private var note: String = ""

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(date.chineseDayLabel())
                        .font(.headline)
                    HStack(spacing: 6) {
                        Image(systemName: kind.symbolName).font(.caption)
                        Text(kind.reason).font(.subheadline)
                    }
                    .foregroundStyle(kind.tint)
                }
                .padding(.vertical, 2)
            }

            Section("手动标记") {
                Button {
                    store.setOverride(key: key, kind: .rest, note: note)
                    Task { await store.refreshSchedule() }
                    dismiss()
                } label: {
                    Label("这天放假，别响", systemImage: "hand.raised.slash.fill")
                }

                Button {
                    store.setOverride(key: key, kind: .work, note: note)
                    Task { await store.refreshSchedule() }
                    dismiss()
                } label: {
                    Label("这天上班，要响", systemImage: "hand.raised.fill")
                }

                if store.override(for: date) != nil {
                    Button(role: .destructive) {
                        store.setOverride(key: key, kind: nil)
                        Task { await store.refreshSchedule() }
                        dismiss()
                    } label: {
                        Label("清除标记，跟随默认判定", systemImage: "arrow.uturn.backward")
                    }
                }
            }

            Section("备注（可选）") {
                TextField("比如「公司团建放假」", text: $note)
            }
        }
        .navigationTitle("调整这一天")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("关闭") { dismiss() }
            }
        }
    }

    private var kind: DayKind { store.kind(for: date) }

    private var key: String { DateKey.string(date, calendar: store.planner.calendar) }
}

struct SchedulePreviewView_Previews: PreviewProvider {
    static var previews: some View {
        SchedulePreviewView().environmentObject(AlarmStore())
    }
}
