import Foundation
import Testing
@testable import BatteryHealthCore

@Suite struct PhoneParserTests {
    func ioreg() throws -> [String: Any] { try #require(try fixturePlist("iphone_ioreg") as? [String: Any]) }

    @Test func parsesRealIPhone() throws {
        let h = try #require(PhoneParser.parseHealth(ioreg: try ioreg()))
        #expect(h.cycleCount == 1963)
        #expect(h.designCapacityMAh == 1810)
        #expect(h.nominalCapacityMAh == 1456)
        #expect(h.healthPercent == 80)
    }

    @Test func missingBatteryDataIsNil() {
        #expect(PhoneParser.parseHealth(ioreg: ["CycleCount": 10]) == nil)
    }

    @Test func peripheralFromPhone() throws {
        let p = PhoneParser.peripheral(udid: "abc", name: "iPhone", chargePercent: 91, health: PhoneParser.parseHealth(ioreg: try ioreg()))
        #expect(p.kind == .phone)
        #expect(p.id == "iphone:abc")
        #expect(p.lowestPercent == 91)
        #expect(p.health?.healthPercent == 80)
    }

    @Test func phoneHealthAlertOnce() throws {
        var s = AlertState()
        var health = try #require(PhoneParser.parseHealth(ioreg: try ioreg()))
        health.healthPercent = 78
        let p = PhoneParser.peripheral(udid: "abc", name: "iPhone", chargePercent: 91, health: health)
        let a = AlertEngine.diff(mac: nil, peripherals: [p], thresholds: Thresholds(), state: &s)
        #expect(a.count == 1)
        #expect(a.first?.body == "Battery health dropped to 78% (threshold 80%).")
        #expect(AlertEngine.diff(mac: nil, peripherals: [p], thresholds: Thresholds(), state: &s).isEmpty)
    }

    @Test func phoneHealthAtThresholdNoAlert() throws {
        var s = AlertState()
        let p = PhoneParser.peripheral(udid: "abc", name: "iPhone", chargePercent: 91, health: PhoneParser.parseHealth(ioreg: try ioreg()))
        #expect(AlertEngine.diff(mac: nil, peripherals: [p], thresholds: Thresholds(), state: &s).isEmpty)
        #expect(HealthEvaluator.evaluate(p, Thresholds()).level == .ok)
    }

    @Test func phoneLowHealthEvaluatesWarning() throws {
        var health = try #require(PhoneParser.parseHealth(ioreg: try ioreg()))
        health.healthPercent = 70
        let p = PhoneParser.peripheral(udid: "abc", name: "iPhone", chargePercent: 91, health: health)
        let r = HealthEvaluator.evaluate(p, Thresholds())
        #expect(r.level == .warning)
        #expect(r.reasons == ["Battery health 70%"])
    }
}
