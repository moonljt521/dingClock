import Combine
import Foundation

/// App 的单一数据源与编排中心。
///
/// 职责链很清楚：
/// `HolidayStore`（拿到节假日数据）
///   → `WorkdayCalendar`（判定每天性质）
///   → `SchedulePlanner`（展开成具体日期）
///   → `AlarmScheduling`（下发给系统）
///
/// - Note: 这里刻意用 `ObservableObject` 而不是 `@Observable`。
///   `@Observable` 依赖编译期宏展开，对工具链的 `swift-plugin-server` 有硬依赖；
///   一旦插件服务异常（部分 Xcode 安装会出现），整个工程都编译不过。
///   `ObservableObject` 没有这个风险，代价只是更新粒度粗一些 —— 对本 App 完全够用。
@MainActor
final class AlarmStore: ObservableObject {

    // MARK: - 对外状态

    @Published private(set) var alarms: [AlarmModel] = []
    @Published private(set) var holidays: HolidayIndex = .empty
    @Published private(set) var overrides: [String: ManualOverride] = [:]
    @Published private(set) var authState: AlarmAuthState = .notDetermined
    @Published private(set) var scheduledCount: Int = 0
    @Published private(set) var statusMessage: String = ""
    @Published private(set) var lastError: String?
    @Published private(set) var isRefreshingHolidays = false
    @Published private(set) var holidayUpdatedAt: Date?

    /// 上次拉取节假日数据的时刻，用于回前台时限频
    private var lastHolidayFetch: Date?
    /// 节假日数据远程刷新的最小间隔。一年才变一两次，6 小时足够跟上国务院的节奏
    private let holidayRefreshInterval: TimeInterval = 6 * 60 * 60
    @Published private(set) var didBootstrap = false

    // MARK: - 依赖

    let scheduler: any AlarmScheduling
    let planner: SchedulePlanner
    private let holidayStore: HolidayStore
    private let fileManager = FileManager.default

    private var storageDirectory: URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return base.appendingPathComponent("DingClock", isDirectory: true)
    }

    init(
        scheduler: any AlarmScheduling = AlarmSchedulerFactory.make(),
        holidayStore: HolidayStore = HolidayStore(),
        calendar: Calendar = .current
    ) {
        self.scheduler = scheduler
        self.holidayStore = holidayStore
        self.planner = SchedulePlanner(calendar: calendar)
    }

    // MARK: - 生命周期

    func bootstrap() async {
        guard !didBootstrap else { return }
        didBootstrap = true

        try? fileManager.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
        loadPersistedState()

        // 先装载内置数据，保证界面一出现判定就是对的；远程更新随后异步进行
        holidays = await holidayStore.loadBundled()

        if alarms.isEmpty { alarms = [AlarmModel()] }

        authState = await scheduler.authorizationState()
        await refreshSchedule()
        await refreshHolidayData()
    }

    /// 重新计算并下发排期。幂等，可反复调用（进入前台、后台刷新、数据更新后都会调用）
    func refreshSchedule() async {
        guard !alarms.isEmpty || !overrides.isEmpty else {
            statusMessage = "还没有闹钟"
            return
        }

        // AlarmKit 必须先授权，否则 schedule() 直接抛错（com.apple.AlarmKit.Alarm 错误 1）。
        // 未决定时就地请求；被拒绝则明确告诉用户去哪里开，而不是甩一个系统错误码。
        if scheduler.isSupported {
            authState = await scheduler.authorizationState()
            if authState == .notDetermined {
                _ = try? await scheduler.requestAuthorization()
                authState = await scheduler.authorizationState()
            }
            if authState != .authorized {
                statusMessage = "还没给闹钟权限：设置 → 叮咚 → 打开「闹钟」"
                lastError = nil
                return
            }
        }

        var plans: [PlannedFire] = []
        var seen = Set<UUID>()
        for alarm in alarms where alarm.isEnabled {
            for fire in planner.fires(for: alarm, workday: workdayCalendar(for: alarm)) {
                if seen.insert(fire.uuid).inserted { plans.append(fire) }
            }
        }
        plans.sort { $0.fireDate < $1.fireDate }

        let spec = AlarmPresentationSpec(
            title: alarms.first?.label ?? "该起床了",
            snoozeEnabled: alarms.contains { $0.snoozeEnabled }
        )

        do {
            try await scheduler.reconcile(plans: plans, spec: spec)
            scheduledCount = (try? await scheduler.scheduledCount()) ?? plans.count
            lastError = nil

            // 覆盖到哪天，比"排了几次"更直观
            let horizon: String = {
                guard let last = plans.last else { return "" }
                let c = planner.calendar.dateComponents([.month, .day], from: last.fireDate)
                return "，覆盖到 \(c.month ?? 0)月\(c.day ?? 0)日"
            }()

            if scheduler.limitHit {
                // 系统对同时存在的闹钟数有动态上限。plans 按时间升序，
                // 留下的是最早的，所以近期的响铃一定有保障；窗口会随使用自动前滚。
                statusMessage = "已排定 \(scheduledCount) 次\(horizon)（到系统上限了，打开 App 会自动滚动窗口）"
            } else if scheduler.isSupported {
                statusMessage = "已排定 \(scheduledCount) 次响铃\(horizon)"
            } else {
                statusMessage = "已算出 \(plans.count) 个响铃时刻（调试模式，不会真响）"
            }
            // 排期成功后请求一次后台唤醒，把窗口往前滚
            if scheduler.isSupported {
                BackgroundRefresh.requestReschedule()
            }
        } catch {
            lastError = error.localizedDescription
            statusMessage = "排期失败：\(error.localizedDescription)"
        }
    }

    func requestAuthorization() async {
        do {
            let ok = try await scheduler.requestAuthorization()
            authState = await scheduler.authorizationState()
            if ok { await refreshSchedule() }
        } catch {
            lastError = error.localizedDescription
            authState = await scheduler.authorizationState()
        }
    }

    func refreshHolidayData(force: Bool = false) async {
        guard !isRefreshingHolidays else { return }

        // 限频：回前台很频繁，不必每次都打网络。
        // 节假日数据一年才变一两次，6 小时拉一次足够跟上国务院的节奏。
        if !force, let last = lastHolidayFetch,
           Date().timeIntervalSince(last) < holidayRefreshInterval {
            return
        }
        isRefreshingHolidays = true
        defer {
            isRefreshingHolidays = false
            lastHolidayFetch = Date()
        }

        let changed = await holidayStore.refreshFromRemote()
        if changed {
            // 数据变了必须立刻重算 —— 否则已经排进系统的闹钟还是旧判定，
            // 会出现「该响的周六没响 / 不该响的假日响了」
            holidays = await holidayStore.loadBundled()
        }
        holidayUpdatedAt = await holidayStore.lastUpdated
        if let err = await holidayStore.lastError, changed == false {
            // 远程失败不影响本地判定，仅作提示
            lastError = nil
            _ = err
        }
        await refreshSchedule()
    }

    /// 回前台 / 后台唤醒时调用：节假日数据限频刷新（变了会自动重排），排期无论如何都对一次账。
    /// 这条链路是「国务院临时改调休 → 你的闹钟自动跟着改」的关键。
    func refreshOnForeground() async {
        let stale = lastHolidayFetch.map { Date().timeIntervalSince($0) > holidayRefreshInterval } ?? true
        if stale {
            await refreshHolidayData()
        } else {
            await refreshSchedule()
        }
    }

    // MARK: - 闹钟增删改

    func upsert(_ alarm: AlarmModel) {
        if let idx = alarms.firstIndex(where: { $0.id == alarm.id }) {
            alarms[idx] = alarm
        } else {
            alarms.append(alarm)
        }
        sortAlarms()
        persistAlarms()
    }

    func delete(_ alarm: AlarmModel) {
        alarms.removeAll { $0.id == alarm.id }
        persistAlarms()
    }

    func setEnabled(_ alarm: AlarmModel, _ enabled: Bool) {
        guard let idx = alarms.firstIndex(where: { $0.id == alarm.id }) else { return }
        alarms[idx].isEnabled = enabled
        persistAlarms()
    }

    private func sortAlarms() {
        alarms.sort { ($0.hour * 60 + $0.minute) < ($1.hour * 60 + $1.minute) }
    }

    // MARK: - 手动例外

    func setOverride(key: String, kind: ManualOverride.Kind?, note: String = "") {
        if let kind {
            overrides[key] = ManualOverride(kind: kind, note: note)
        } else {
            overrides.removeValue(forKey: key)
        }
        persistOverrides()
    }

    func override(for date: Date) -> ManualOverride? {
        overrides[DateKey.string(date, calendar: planner.calendar)]
    }

    var sortedOverrides: [(key: String, override: ManualOverride)] {
        overrides
            .map { (key: $0.key, override: $0.value) }
            .sorted { $0.key < $1.key }
    }

    // MARK: - 派生查询

    /// 某个闹钟对应的判定日历
    func workdayCalendar(for alarm: AlarmModel) -> WorkdayCalendar {
        alarm.workdayCalendar(holidays: holidays, overrides: overrides, calendar: planner.calendar)
    }

    /// 全局判定日历（「工作日（含调休）」口径），用于日历视图与「今天」状态
    var globalWorkdayCalendar: WorkdayCalendar {
        WorkdayCalendar(
            weekPattern: .fiveDay,
            holidays: holidays,
            overrides: overrides,
            respectsStateHolidays: true,
            calendar: planner.calendar
        )
    }

    func kind(for date: Date) -> DayKind { globalWorkdayCalendar.kind(for: date) }

    func nextFire(for alarm: AlarmModel, from now: Date = Date()) -> PlannedFire? {
        planner.nextFire(for: alarm, workday: workdayCalendar(for: alarm), from: now)
    }

    /// 全 App 即将到来的响铃（跨所有已启用的闹钟）
    func upcomingFires(limit: Int = 6, from now: Date = Date()) -> [PlannedFire] {
        var all: [PlannedFire] = []
        var seen = Set<UUID>()
        for alarm in alarms where alarm.isEnabled {
            for fire in planner.fires(for: alarm, workday: workdayCalendar(for: alarm), from: now, maxCount: limit) {
                if seen.insert(fire.uuid).inserted { all.append(fire) }
            }
        }
        return Array(all.sorted { $0.fireDate < $1.fireDate }.prefix(limit))
    }

    /// 系统里**实际**排着的响铃日，逐条核对面前的判定。
    /// 这是给「系统对账」视图用的：不信任自己的计算，直接问系统要。
    struct SystemAlarmAuditEntry: Identifiable, Equatable, Sendable {
        var id: String { key }
        let key: String
        let date: Date
        let weekday: String
        let isWorkday: Bool
        let reason: String
        /// 当前判定说这天不该响，但系统里却排着 —— 这是真 bug
        var isMismatch: Bool { !isWorkday }
    }

    func auditSystemAlarms() async -> [SystemAlarmAuditEntry] {
        let dates = await scheduler.scheduledSystemDates()
        let calendar = planner.calendar
        let workday = globalWorkdayCalendar

        return dates.map { date in
            let kind = workday.kind(for: date)
            return SystemAlarmAuditEntry(
                key: DateKey.string(date, calendar: calendar),
                date: date,
                weekday: WeekdaySymbols.chinese(forWeekday: calendar.component(.weekday, from: date)),
                isWorkday: kind.isWorkday,
                reason: kind.reason
            )
        }
    }

    /// 今天是否响铃（任一启用的闹钟）

    var holidayCoverage: String { holidays.coverageDescription }

    // MARK: - 持久化

    private func loadPersistedState() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        if let data = try? Data(contentsOf: storageDirectory.appendingPathComponent("alarms.json")),
           let decoded = try? decoder.decode([AlarmModel].self, from: data) {
            alarms = decoded
        }
        if let data = try? Data(contentsOf: storageDirectory.appendingPathComponent("overrides.json")),
           let decoded = try? decoder.decode([String: ManualOverride].self, from: data) {
            overrides = decoded
        }
    }

    private func persistAlarms() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(alarms) {
            try? data.write(to: storageDirectory.appendingPathComponent("alarms.json"), options: .atomic)
        }
    }

    private func persistOverrides() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(overrides) {
            try? data.write(to: storageDirectory.appendingPathComponent("overrides.json"), options: .atomic)
        }
    }
}
