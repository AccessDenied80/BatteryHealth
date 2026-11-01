import Foundation
import Testing
@testable import BatteryHealthCore

@Suite struct HistoryStoreTests {
    func tempFile() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("history.json")
    }

    let sample = HistorySample(date: Date(), healthPercent: 95, cycleCount: 197, chargePercent: 80)

    @Test func appendAndReload() throws {
        let url = tempFile()
        let s = HistoryStore(fileURL: url)
        s.append(sample, for: "mac")
        try s.save()
        let s2 = HistoryStore(fileURL: url)
        s2.load()
        #expect(s2.samples(for: "mac") == [sample])
    }

    @Test func prunesOlderThan365Days() {
        let s = HistoryStore(fileURL: tempFile())
        var old = sample
        old.date = Date().addingTimeInterval(-400 * 86_400)
        s.append(old, for: "mac")
        s.append(sample, for: "mac")
        #expect(s.samples(for: "mac") == [sample])
    }

    @Test func coalescesWithinAnHour() {
        let s = HistoryStore(fileURL: tempFile())
        var first = sample
        first.date = Date().addingTimeInterval(-600)
        first.chargePercent = 70
        s.append(first, for: "mac")
        s.append(sample, for: "mac")
        #expect(s.samples(for: "mac") == [sample])
    }

    @Test func keepsSamplesHourApart() {
        let s = HistoryStore(fileURL: tempFile())
        var first = sample
        first.date = Date().addingTimeInterval(-3_700)
        s.append(first, for: "mac")
        s.append(sample, for: "mac")
        #expect(s.samples(for: "mac").count == 2)
    }

    @Test func missingFileIsEmpty() {
        let s = HistoryStore(fileURL: tempFile())
        s.load()
        #expect(s.samples(for: "mac").isEmpty)
    }
}
