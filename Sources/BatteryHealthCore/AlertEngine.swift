public struct Alert: Equatable, Sendable {
    public var key: String
    public var title: String
    public var body: String
    public var critical: Bool
}

/// Які умови вже повідомлені — щоб кожна подія сповіщала один раз (зберігається між запусками).
public struct AlertState: Codable, Equatable, Sendable {
    public var active: Set<String> = []

    public init() {}
}

public enum AlertEngine {
    public static func diff(
        mac: MacBattery?, peripherals: [Peripheral], thresholds t: Thresholds, state: inout AlertState
    ) -> [Alert] {
        var alerts: [Alert] = []

        func condition(_ key: String, on: Bool, title: String, body: @autoclosure () -> String, critical: Bool) {
            if on {
                if state.active.insert(key).inserted {
                    alerts.append(Alert(key: key, title: title, body: body(), critical: critical))
                }
            } else {
                state.active.remove(key)
            }
        }

        if let b = mac {
            let title = String(localized: "Mac battery")
            // Ключ здоров'я містить поріг: після зміни порогу старий ключ прибираємо, інакше він «залипне».
            let healthKey = "mac|health\(t.macHealthWarning)"
            state.active = state.active.filter { !$0.hasPrefix("mac|health") || $0 == healthKey }

            condition("mac|service", on: b.serviceRecommended, title: title,
                      body: String(localized: "macOS recommends servicing the battery."), critical: true)
            let health = b.healthPercent ?? 100
            condition(healthKey, on: health < t.macHealthWarning, title: title,
                      body: String(localized: "Battery health dropped to \(health)% (threshold \(t.macHealthWarning)%)."),
                      critical: false)
            let temp = Int(b.temperatureC ?? 0)
            condition("mac|hot", on: temp >= t.hotC, title: title,
                      body: String(localized: "Battery temperature \(temp) °C (threshold \(t.hotC) °C)."),
                      critical: false)
        }

        for p in peripherals {
            guard let low = p.lowestPercent else { continue }
            let key = "\(p.id)|low"
            // Гістерезис: між lowCharge і lowChargeRearm стан не змінюється, тож коливання 14–16 % не спамлять.
            if low <= t.lowCharge {
                if state.active.insert(key).inserted {
                    alerts.append(Alert(key: key, title: p.name,
                                        body: String(localized: "Charge \(low)%. Time to charge."), critical: false))
                }
            } else if low > t.lowChargeRearm {
                state.active.remove(key)
            }
        }

        return alerts
    }
}
