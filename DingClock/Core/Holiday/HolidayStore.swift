import Foundation

/// 节假日数据仓库：**先本地、后远程**。
///
/// 1. 启动时从 App 包内置的 JSON 装载（离线可用，保证 2024–2026 完全准确）；
/// 2. 之后尝试从 holiday-cn 拉取增量更新，成功则写入沙盒缓存，下次启动优先用缓存。
///
/// 远程永远只是「锦上添花」：拉不到就用内置数据继续跑，绝不因为网络失败而影响响铃。
actor HolidayStore {

    /// 内置数据从哪一年开始
    static let bundledYears = [2024, 2025, 2026, 2027]

    /// 远程数据源。jsdelivr 国内可直连；失败时自动回退到 raw.githubusercontent。
    static let remoteTemplates = [
        "https://fastly.jsdelivr.net/gh/NateScarlet/holiday-cn@master/%d.json",
        "https://cdn.jsdelivr.net/gh/NateScarlet/holiday-cn@master/%d.json",
        "https://raw.githubusercontent.com/NateScarlet/holiday-cn/master/%d.json"
    ]

    private let session: URLSession
    private let cacheDirectory: URL

    private(set) var index: HolidayIndex = .empty
    private(set) var lastUpdated: Date?
    private(set) var lastError: String?

    init(session: URLSession = .shared) {
        self.session = session
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        self.cacheDirectory = base.appendingPathComponent("DingClock/Holidays", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    /// 同步装载内置数据（启动时立刻调用，保证 UI 一出现就有正确结果）
    @discardableResult
    func loadBundled() -> HolidayIndex {
        var records: [HolidayYearData] = []
        for year in Self.bundledYears {
            if let data = Self.bundledData(year: year), let parsed = try? JSONDecoder().decode(HolidayYearData.self, from: data) {
                records.append(parsed)
            }
        }
        // 沙盒缓存里的（可能是更新过的）数据覆盖内置数据
        for url in cachedFiles() {
            if let data = try? Data(contentsOf: url),
               let parsed = try? JSONDecoder().decode(HolidayYearData.self, from: data) {
                records.append(parsed)
            }
        }
        var idx = HolidayIndex()
        idx.merge(records)
        index = idx
        return idx
    }

    /// 从远程更新指定年份（默认覆盖内置年份 + 明年）
    /// - Returns: 是否有数据发生变化
    @discardableResult
    func refreshFromRemote(years: [Int]? = nil, timeout: TimeInterval = 12) async -> Bool {
        let calendar = Calendar.current
        let currentYear = calendar.component(.year, from: Date())
        let targets = years ?? Array((currentYear - 1)...(currentYear + 1))

        var changed = false
        var firstError: String?

        for year in targets {
            guard let data = await fetch(year: year, timeout: timeout) else {
                firstError = firstError ?? "第 \(year) 年数据拉取失败"
                continue
            }
            guard let parsed = try? JSONDecoder().decode(HolidayYearData.self, from: data) else { continue }
            // 空数据（国务院还没发当年通知）不覆盖本地
            guard !parsed.days.isEmpty else { continue }
            let target = cacheDirectory.appendingPathComponent("\(year).json")
            let isNew = (try? Data(contentsOf: target)) != data
            if isNew {
                try? data.write(to: target, options: .atomic)
                changed = true
            }
        }

        lastError = firstError
        if changed { _ = loadBundled() }
        if firstError == nil { lastUpdated = Date() }
        return changed
    }

    // MARK: - Private

    private func fetch(year: Int, timeout: TimeInterval) async -> Data? {
        for template in Self.remoteTemplates {
            guard let url = URL(string: String(format: template, year)) else { continue }
            var request = URLRequest(url: url)
            request.timeoutInterval = timeout
            request.cachePolicy = .reloadIgnoringLocalCacheData
            if let (data, response) = try? await session.data(for: request),
               let http = response as? HTTPURLResponse, http.statusCode == 200,
               !data.isEmpty {
                return data
            }
        }
        return nil
    }

    private func cachedFiles() -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension == "json" } ?? []
    }

    private static func bundledData(year: Int) -> Data? {
        guard let url = Bundle.main.url(forResource: "\(year)", withExtension: "json", subdirectory: "Holidays")
            ?? Bundle.main.url(forResource: "\(year)", withExtension: "json") else { return nil }
        return try? Data(contentsOf: url)
    }
}
