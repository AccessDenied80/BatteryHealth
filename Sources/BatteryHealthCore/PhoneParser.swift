import Foundation

/// Розбирає відповідь служби діагностики iPhone (`IORegistry`, клас `IOPMPowerSource`).
public enum PhoneParser {
    /// Здоров'я = поточна номінальна ємність / заводська (як «Максимальна ємність» у налаштуваннях iOS).
    public static func parseHealth(ioreg: [String: Any]) -> PhoneBatteryHealth? {
        let data = ioreg["BatteryData"] as? [String: Any]
        guard let design = MacBatteryParser.int(data?["DesignCapacity"]), design > 0,
              let nominal = MacBatteryParser.int(data?["NominalChargeCapacity"]) ?? MacBatteryParser.int(data?["FullChargeCapacity"])
        else { return nil }
        return PhoneBatteryHealth(
            healthPercent: Int((Double(nominal) * 100 / Double(design)).rounded()),
            cycleCount: MacBatteryParser.int(ioreg["CycleCount"]),
            designCapacityMAh: design,
            nominalCapacityMAh: nominal
        )
    }

    public static func peripheral(udid: String, name: String, chargePercent: Int?, health: PhoneBatteryHealth?) -> Peripheral {
        Peripheral(
            id: "iphone:\(udid)",
            name: name,
            kind: .phone,
            levels: chargePercent.map { [BatteryLevel(label: .main, percent: $0)] } ?? [],
            source: "iphone",
            health: health
        )
    }
}
