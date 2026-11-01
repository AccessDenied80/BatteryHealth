public enum HealthLevel: Int, Codable, Comparable, Sendable {
    case unknown = 0, ok, warning, critical

    public static func < (a: HealthLevel, b: HealthLevel) -> Bool { a.rawValue < b.rawValue }

    public static func overall(_ levels: [HealthLevel]) -> HealthLevel { levels.max() ?? .unknown }
}

public struct HealthReport: Equatable, Sendable {
    public var level: HealthLevel
    public var reasons: [String]

    public init(level: HealthLevel, reasons: [String]) {
        self.level = level
        self.reasons = reasons
    }
}

public enum HealthEvaluator {
    public static func evaluate(_ b: MacBattery, _ t: Thresholds) -> HealthReport {
        var r = HealthReport(level: .ok, reasons: [])
        if b.serviceRecommended { r.flag(.critical, String(localized: "Service recommended")) }
        if let h = b.healthPercent, h < t.macHealthWarning { r.flag(.warning, String(localized: "Battery health \(h)%")) }
        if let temp = b.temperatureC, temp >= Double(t.hotC) {
            r.flag(.warning, String(localized: "Battery temperature \(Int(temp)) °C"))
        }
        return r
    }

    public static func evaluate(_ p: Peripheral, _ t: Thresholds) -> HealthReport {
        var r = HealthReport(level: .ok, reasons: [])
        if let low = p.lowestPercent, low <= t.lowCharge { r.flag(.warning, String(localized: "Charge \(low)%")) }
        return r
    }
}

extension HealthReport {
    mutating func flag(_ l: HealthLevel, _ reason: String) {
        level = max(level, l)
        reasons.append(reason)
    }
}
