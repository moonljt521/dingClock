import XCTest
@testable import DingClock

/// 数据层测试：确认我们解析的就是 holiday-cn（进而就是国务院公告）的真实结构。
final class HolidayDataTests: XCTestCase {

    private let cal = TestCalendar.calendar

    /// 真实 holiday-cn JSON 的字段名与我们的模型必须对得上
    func testDecodesRealHolidayCNSchema() throws {
        let json = """
        {
          "$schema": "https://raw.githubusercontent.com/NateScarlet/holiday-cn/master/schema.json",
          "$id": "https://raw.githubusercontent.com/NateScarlet/holiday-cn/master/2026.json",
          "year": 2026,
          "papers": ["https://www.gov.cn/zhengce/zhengceku/202511/content_7047091.htm"],
          "days": [
            { "name": "元旦", "date": "2026-01-01", "isOffDay": true },
            { "name": "元旦", "date": "2026-01-04", "isOffDay": false }
          ]
        }
        """
        let decoded = try JSONDecoder().decode(HolidayYearData.self, from: Data(json.utf8))

        XCTAssertEqual(decoded.year, 2026)
        XCTAssertEqual(decoded.papers?.count, 1)
        XCTAssertEqual(decoded.days.count, 2)
        XCTAssertEqual(decoded.days[0].name, "元旦")
        XCTAssertTrue(decoded.days[0].isOffDay)
        XCTAssertFalse(decoded.days[1].isOffDay)
    }

    func testHolidayIndexSeparatesOffDayFromMakeupDay() {
        let index = TestFixtures.holidayIndex2026()

        XCTAssertNotNil(index.offDay(on: "2026-10-01"), "10/1 是法定放假日")
        XCTAssertNil(index.makeupWorkday(on: "2026-10-01"))

        XCTAssertNil(index.offDay(on: "2026-10-10"), "10/10 不是放假日")
        XCTAssertNotNil(index.makeupWorkday(on: "2026-10-10"), "10/10 是调休补班日")

        XCTAssertNil(index.special(on: "2026-09-17"), "9/17 是普通工作日，不该有特殊标记")
    }

    func testDateKeyRoundTrip() {
        let date = TestCalendar.date(2026, 10, 10)
        XCTAssertEqual(DateKey.string(date, calendar: cal), "2026-10-10")
        XCTAssertEqual(DateKey.date("2026-10-10", calendar: cal).map { DateKey.string($0, calendar: cal) }, "2026-10-10")
        XCTAssertNil(DateKey.date("不是日期", calendar: cal))
    }

    /// 空的年份数据（国务院还没发文）不能算作「已覆盖」，
    /// 否则设置页会谎报数据范围
    func testEmptyYearIsNotCountedAsCovered() {
        var index = HolidayIndex()
        index.merge(HolidayYearData(year: 2027, papers: [], days: []))
        XCTAssertFalse(index.loadedYears.contains(2027))
        XCTAssertEqual(index.coverageDescription, "未装载节假日数据")
    }

    /// 内置资源随包发布（软校验：宿主没提供资源时跳过，不让环境差异变成红灯）
    func testBundledHolidayResourcesAreDecodable() throws {
        var decodedYears: [Int] = []

        for year in HolidayStore.bundledYears {
            guard let url = Bundle.main.url(forResource: "\(year)", withExtension: "json"),
                  let data = try? Data(contentsOf: url),
                  let parsed = try? JSONDecoder().decode(HolidayYearData.self, from: data),
                  parsed.year == year else { continue }
            decodedYears.append(year)
        }

        try XCTSkipIf(decodedYears.isEmpty, "测试宿主未提供资源包，跳过内置数据校验")

        // 内置数据至少要能覆盖到今年
        let currentYear = cal.component(.year, from: Date())
        XCTAssertTrue(
            decodedYears.contains(where: { $0 == currentYear }),
            "内置数据里缺少 \(currentYear) 年，离线时会判定错误。实际解出：\(decodedYears)"
        )
    }
}
