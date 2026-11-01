import Foundation
import Testing

@Test func fixtureLoads() throws {
    let battery = try #require(try fixturePlist("mac_battery") as? [String: Any])
    #expect(battery["CycleCount"] as? Int == 197)
}
