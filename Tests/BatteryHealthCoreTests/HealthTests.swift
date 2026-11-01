import Foundation
import Testing
@testable import BatteryHealthCore

func realMac() throws -> MacBattery {
    let r = try #require(try fixturePlist("mac_battery") as? [String: Any])
    let ps = try #require(try fixturePlist("ps_good") as? [String: Any])
    return try #require(MacBatteryParser.parse(registry: r, powerSource: ps))
}

func device(_ pct: Int, id: String = "kb") -> Peripheral {
    Peripheral(id: id, name: "Magic Keyboard", kind: .keyboard, levels: [BatteryLevel(label: .main, percent: pct)], source: "hid")
}

@Suite struct HealthTests {
    let t = Thresholds()

    @Test func goodMacIsOK() throws {
        #expect(HealthEvaluator.evaluate(try realMac(), t).level == .ok)
    }

    @Test func lowHealthWarns() throws {
        var b = try realMac(); b.healthPercent = 75
        let r = HealthEvaluator.evaluate(b, t)
        #expect(r.level == .warning)
        #expect(r.reasons == ["Battery health 75%"])
    }

    @Test func serviceIsCritical() throws {
        var b = try realMac(); b.serviceRecommended = true
        let r = HealthEvaluator.evaluate(b, t)
        #expect(r.level == .critical)
        #expect(r.reasons.contains("Service recommended"))
    }

    @Test func hotWarns() throws {
        var b = try realMac(); b.temperatureC = 46.2
        let r = HealthEvaluator.evaluate(b, t)
        #expect(r.level == .warning)
        #expect(r.reasons == ["Battery temperature 46 °C"])
    }

    @Test func lowPeripheralWarns() {
        let r = HealthEvaluator.evaluate(device(12), t)
        #expect(r.level == .warning)
        #expect(r.reasons == ["Charge 12%"])
        #expect(HealthEvaluator.evaluate(device(50), t).level == .ok)
    }

    @Test func overall() {
        #expect(HealthLevel.overall([.ok, .warning]) == .warning)
        #expect(HealthLevel.overall([]) == .unknown)
    }
}
