import Foundation

/// Будує `MacBattery` зі словника IOKit `AppleSmartBattery` і опису джерела живлення IOPS.
public enum MacBatteryParser {
    public static func parse(registry r: [String: Any], powerSource ps: [String: Any]?) -> MacBattery? {
        guard r["BatteryInstalled"] as? Bool == true else { return nil }

        var b = MacBattery()
        let design = int(r["DesignCapacity"])
        // На Apple Silicon MaxCapacity/CurrentCapacity — відсотки; справжні мА·год — у AppleRaw*.
        let rawMax = int(r["AppleRawMaxCapacity"]) ?? int(r["MaxCapacity"]).flatMap { $0 > 100 ? $0 : nil }
        let rawCurrent = int(r["AppleRawCurrentCapacity"]) ?? int(r["CurrentCapacity"]).flatMap { $0 > 100 ? $0 : nil }

        b.designCapacityMAh = design
        b.maxCapacityMAh = rawMax
        b.currentCapacityMAh = rawCurrent
        if let design, design > 0, let rawMax {
            b.healthPercent = Int((Double(rawMax) * 100 / Double(design)).rounded())
        }

        if let c = int(ps?["Current Capacity"]), let m = int(ps?["Max Capacity"]), m > 0 {
            b.chargePercent = Int((Double(c) * 100 / Double(m)).rounded())
        } else if let rawCurrent, let rawMax, rawMax > 0 {
            b.chargePercent = Int((Double(rawCurrent) * 100 / Double(rawMax)).rounded())
        }

        b.cycleCount = int(r["CycleCount"])
        b.designCycleCount = int(r["DesignCycleCount9C"]) ?? int(ps?["DesignCycleCount"])
        b.temperatureC = int(r["Temperature"]).map { Double($0) / 100 }
        b.voltageV = int(r["Voltage"]).map { Double($0) / 1000 }
        b.cellVoltagesMV = ((r["BatteryData"] as? [String: Any])?["CellVoltage"] as? [Any])?.compactMap(int) ?? []
        b.amperageMA = int(r["InstantAmperage"]) ?? int(r["Amperage"])
        b.isCharging = r["IsCharging"] as? Bool ?? false
        b.externalConnected = r["ExternalConnected"] as? Bool ?? false
        b.fullyCharged = r["FullyCharged"] as? Bool ?? false

        let healthCondition = (ps?["BatteryHealthCondition"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        b.condition = healthCondition ?? (ps?["BatteryHealth"] as? String)
        b.serviceRecommended = (b.condition?.localizedCaseInsensitiveContains("service") ?? false)
            || (int(r["PermanentFailureStatus"]) ?? 0) != 0

        let adapter = r["AdapterDetails"] as? [String: Any]
        b.adapterName = adapter?["Name"] as? String
        b.adapterWatts = int(adapter?["Watts"])
        b.deviceName = r["DeviceName"] as? String
        b.manufacturer = r["Manufacturer"] as? String
        return b
    }

    /// IOKit віддає числа як NSNumber різних типів (а деякі лічильники — як великі беззнакові).
    static func int(_ v: Any?) -> Int? {
        switch v {
        case let n as Int: n
        case let n as NSNumber: n.intValue
        default: nil
        }
    }
}
