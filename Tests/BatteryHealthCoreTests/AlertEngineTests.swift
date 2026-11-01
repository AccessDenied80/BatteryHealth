import Foundation
import Testing
@testable import BatteryHealthCore

@Suite struct AlertEngineTests {
    let t = Thresholds()

    func run(_ mac: MacBattery?, _ peripherals: [Peripheral], _ s: inout AlertState, _ th: Thresholds? = nil) -> [Alert] {
        AlertEngine.diff(mac: mac, peripherals: peripherals, thresholds: th ?? t, state: &s)
    }

    @Test func lowChargeOnce() {
        var s = AlertState()
        let a = run(nil, [device(12)], &s)
        #expect(a.count == 1)
        #expect(a.first?.body == "Charge 12%. Time to charge.")
        #expect(a.first?.title == "Magic Keyboard")
        #expect(run(nil, [device(12)], &s).isEmpty)
    }

    @Test func lowChargeNoRepeatWhileHovering() {
        var s = AlertState()
        var total = 0
        for pct in [14, 16, 14, 15, 17] { total += run(nil, [device(pct)], &s).count }
        #expect(total == 1)
    }

    @Test func lowChargeRearmsAfterCharging() {
        var s = AlertState()
        var total = 0
        for pct in [14, 30, 14] { total += run(nil, [device(pct)], &s).count }
        #expect(total == 2)
    }

    @Test func disconnectedDeviceKeepsState() {
        // Пристрій зник зі списку (вимкнули) — після повернення з тим самим низьким зарядом не дублюємо.
        var s = AlertState()
        _ = run(nil, [device(10)], &s)
        _ = run(nil, [], &s)
        #expect(run(nil, [device(10)], &s).isEmpty)
    }

    @Test func serviceOnce() throws {
        var s = AlertState()
        var b = try realMac(); b.serviceRecommended = true
        let a = run(b, [], &s)
        #expect(a.count == 1)
        #expect(a.first?.critical == true)
        #expect(run(b, [], &s).isEmpty)
    }

    @Test func lowHealthBody() throws {
        var s = AlertState()
        var b = try realMac(); b.healthPercent = 75
        #expect(run(b, [], &s).first?.body == "Battery health dropped to 75% (threshold 80%).")
    }

    @Test func hotFiresAndClears() throws {
        var s = AlertState()
        var b = try realMac(); b.temperatureC = 47
        #expect(run(b, [], &s).count == 1)
        b.temperatureC = 30
        #expect(run(b, [], &s).isEmpty)
        b.temperatureC = 47
        #expect(run(b, [], &s).count == 1)
    }

    @Test func healthThresholdChangeDropsStaleKey() throws {
        var s = AlertState()
        var b = try realMac(); b.healthPercent = 75
        _ = run(b, [], &s)
        var th = Thresholds(); th.macHealthWarning = 70
        _ = run(b, [], &s, th)
        #expect(!s.active.contains("mac|health80"))
    }

    @Test func goodMacNoAlerts() throws {
        var s = AlertState()
        #expect(run(try realMac(), [device(80)], &s).isEmpty)
    }

    @Test func stateRoundTrip() throws {
        var s = AlertState()
        _ = run(nil, [device(10)], &s)
        var back = try JSONDecoder().decode(AlertState.self, from: JSONEncoder().encode(s))
        #expect(back == s)
        #expect(run(nil, [device(10)], &back).isEmpty)
    }
}
