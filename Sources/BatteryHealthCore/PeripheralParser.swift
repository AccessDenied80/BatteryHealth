import Foundation

/// Перетворює дані `system_profiler SPBluetoothDataType -json` і HID-сервісів IOKit у `Peripheral`.
public enum PeripheralParser {
    /// Лише підключені пристрої, для яких macOS знає хоча б один рівень заряду.
    public static func parseBluetooth(json: Data) throws -> [Peripheral] {
        let root = try JSONSerialization.jsonObject(with: json) as? [String: Any]
        let controllers = root?["SPBluetoothDataType"] as? [[String: Any]] ?? []
        var result: [Peripheral] = []
        for controller in controllers {
            for entry in controller["device_connected"] as? [[String: Any]] ?? [] {
                for (name, value) in entry {
                    guard let info = value as? [String: Any] else { continue }
                    let levels: [BatteryLevel] = [
                        ("device_batteryLevelMain", .main),
                        ("device_batteryLevelLeft", .left),
                        ("device_batteryLevelRight", .right),
                        ("device_batteryLevelCase", .case_),
                    ].compactMap { key, label in percent(info[key]).map { BatteryLevel(label: label, percent: $0) } }
                    guard !levels.isEmpty else { continue }
                    result.append(Peripheral(
                        id: normalizedAddress(info["device_address"] as? String) ?? "name:\(name)",
                        name: name,
                        kind: kind(minorType: info["device_minorType"] as? String, name: name),
                        levels: levels,
                        source: "bluetooth"
                    ))
                }
            }
        }
        return result
    }

    /// Записи IOKit-сервісів із властивістю `BatteryPercent` (Magic Mouse/Keyboard/Trackpad).
    public static func parseHID(_ entries: [[String: Any]]) -> [Peripheral] {
        entries.compactMap { e in
            guard let pct = percent(e["BatteryPercent"]) else { return nil }
            let name = e["Product"] as? String ?? String(localized: "Unknown device")
            return Peripheral(
                id: normalizedAddress(e["DeviceAddress"] as? String) ?? "name:\(name)",
                name: name,
                kind: kind(minorType: nil, name: name),
                levels: [BatteryLevel(label: .main, percent: pct)],
                source: "hid"
            )
        }
    }

    /// Об'єднує списки за `id`; за збігу лишається запис із першого списку.
    public static func merge(_ lists: [Peripheral]...) -> [Peripheral] {
        var seen = Set<String>()
        var result: [Peripheral] = []
        for p in lists.joined() where seen.insert(p.id).inserted {
            result.append(p)
        }
        return result
    }

    static func percent(_ v: Any?) -> Int? {
        let value: Int?
        switch v {
        case let n as Int: value = n
        case let n as NSNumber: value = n.intValue
        case let s as String: value = Int(s.trimmingCharacters(in: CharacterSet(charactersIn: "% ")))
        default: value = nil
        }
        return value.flatMap { (0...100).contains($0) ? $0 : nil }
    }

    static func normalizedAddress(_ s: String?) -> String? {
        guard let s, !s.isEmpty else { return nil }
        return s.replacingOccurrences(of: "-", with: ":").lowercased()
    }

    static func kind(minorType: String?, name: String) -> PeripheralKind {
        let hint = "\(minorType ?? "") \(name)".lowercased()
        if hint.contains("headphone") || hint.contains("headset") || hint.contains("airpods") { return .headphones }
        if hint.contains("mouse") { return .mouse }
        if hint.contains("trackpad") { return .trackpad }
        if hint.contains("keyboard") { return .keyboard }
        if hint.contains("gamepad") || hint.contains("controller") { return .gamepad }
        if hint.contains("phone") { return .phone }
        return .other
    }
}
