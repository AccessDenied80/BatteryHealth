import Foundation
import Testing
@testable import BatteryHealthCore

@Suite struct PeripheralParserTests {
    func bluetooth() throws -> [Peripheral] { try PeripheralParser.parseBluetooth(json: fixtureData("bluetooth", "json")) }
    func hid() throws -> [Peripheral] {
        PeripheralParser.parseHID(try #require(try fixturePlist("hid") as? [[String: Any]]))
    }

    @Test func bluetoothAirPods() throws {
        let airpods = try #require(try bluetooth().first { $0.name == "AirPods Pro" })
        #expect(airpods.kind == .headphones)
        #expect(airpods.id == "00:00:00:00:00:01")
        #expect(airpods.levels == [
            BatteryLevel(label: .left, percent: 85),
            BatteryLevel(label: .right, percent: 90),
            BatteryLevel(label: .case_, percent: 100),
        ])
        #expect(airpods.lowestPercent == 85)
    }

    @Test func bluetoothMouse() throws {
        let mouse = try #require(try bluetooth().first { $0.name == "Magic Mouse" })
        #expect(mouse.kind == .mouse)
        #expect(mouse.levels == [BatteryLevel(label: .main, percent: 60)])
    }

    @Test func bluetoothSkipsWithoutLevels() throws {
        #expect(try bluetooth().contains { $0.name == "HBQ-Q32 tws" } == false)
    }

    @Test func bluetoothSkipsDisconnected() throws {
        #expect(try bluetooth().contains { $0.name == "iPhone" } == false)
    }

    @Test func hidParses() throws {
        let list = try hid()
        #expect(list.count == 2)
        #expect(list[0].name == "Magic Mouse")
        #expect(list[0].lowestPercent == 61)
        #expect(list[0].id == "00:00:00:00:00:02")
        #expect(list[1].kind == .keyboard)
        #expect(list[1].lowestPercent == 12)
    }

    @Test func mergeDedupesByAddressHIDWins() throws {
        let merged = PeripheralParser.merge(try hid(), try bluetooth())
        let mice = merged.filter { $0.id == "00:00:00:00:00:02" }
        #expect(mice.count == 1)
        #expect(mice.first?.lowestPercent == 61)
        #expect(merged.count == 3) // мишка, клавіатура, AirPods
    }

    @Test func percentParsing() {
        #expect(PeripheralParser.percent("85%") == 85)
        #expect(PeripheralParser.percent(85) == 85)
        #expect(PeripheralParser.percent(NSNumber(value: 40)) == 40)
        #expect(PeripheralParser.percent("n/a") == nil)
        #expect(PeripheralParser.percent(nil) == nil)
        #expect(PeripheralParser.percent(150) == nil)
    }

    @Test func garbageJSONThrows() {
        #expect(throws: (any Error).self) { try PeripheralParser.parseBluetooth(json: Data("nope".utf8)) }
    }
}
