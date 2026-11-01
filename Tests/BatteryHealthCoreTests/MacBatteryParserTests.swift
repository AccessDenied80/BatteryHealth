import Foundation
import Testing
@testable import BatteryHealthCore

@Suite struct MacBatteryParserTests {
    func registry() throws -> [String: Any] { try #require(try fixturePlist("mac_battery") as? [String: Any]) }
    func ps(_ name: String) throws -> [String: Any] { try #require(try fixturePlist(name) as? [String: Any]) }

    @Test func parsesRealBattery() throws {
        let b = try #require(MacBatteryParser.parse(registry: try registry(), powerSource: try ps("ps_good")))
        #expect(b.healthPercent == 95)
        #expect(b.maxCapacityMAh == 6585)
        #expect(b.designCapacityMAh == 6900)
        #expect(b.cycleCount == 197)
        #expect(b.designCycleCount == 1000)
        #expect(abs((b.temperatureC ?? 0) - 29.85) < 0.01)
        #expect(abs((b.voltageV ?? 0) - 12.048) < 0.001)
        #expect(b.cellVoltagesMV == [3963, 4023, 4062])
        #expect(b.adapterName == "87W USB-C Power Adapter")
        #expect(b.adapterWatts == 86)
        #expect(b.condition == "Good")
        #expect(!b.serviceRecommended)
        #expect(b.chargePercent == 80)
        #expect(b.externalConnected)
        #expect(!b.isCharging)
    }

    @Test func serviceRecommendedFromIOPS() throws {
        let b = try #require(MacBatteryParser.parse(registry: try registry(), powerSource: try ps("ps_service")))
        #expect(b.serviceRecommended)
        #expect(b.condition == "Service Recommended")
    }

    @Test func permanentFailureFlag() throws {
        var r = try registry()
        r["PermanentFailureStatus"] = 1
        #expect(MacBatteryParser.parse(registry: r, powerSource: try ps("ps_good"))?.serviceRecommended == true)
    }

    @Test func noBatteryReturnsNil() throws {
        var r = try registry()
        r["BatteryInstalled"] = false
        #expect(MacBatteryParser.parse(registry: r, powerSource: nil) == nil)
        #expect(MacBatteryParser.parse(registry: [:], powerSource: nil) == nil)
    }

    @Test func missingRawMaxFallsBack() throws {
        var r = try registry()
        r.removeValue(forKey: "AppleRawMaxCapacity")
        #expect(MacBatteryParser.parse(registry: r, powerSource: nil)?.healthPercent == 95)
        r["MaxCapacity"] = 100 // на Apple Silicon MaxCapacity — відсотки, а не мА·год
        #expect(MacBatteryParser.parse(registry: r, powerSource: nil)?.healthPercent == nil)
    }

    @Test func chargeWithoutPowerSource() throws {
        // Без IOPS заряд рахуємо з мА·год: 5051 / 6585 ≈ 77 %.
        #expect(MacBatteryParser.parse(registry: try registry(), powerSource: nil)?.chargePercent == 77)
    }
}
