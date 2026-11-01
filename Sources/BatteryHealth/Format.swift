import BatteryHealthCore
import SwiftUI

enum Format {
    static func percent(_ p: Int?) -> String { p.map { "\($0)%" } ?? "—" }

    static func temperature(_ t: Double?) -> String { t.map { "\(decimal($0, digits: 1)) °C" } ?? "—" }

    /// Дробове число з роздільником за мовою системи (29,9 українською, 29.9 англійською).
    static func decimal(_ v: Double, digits: Int) -> String {
        v.formatted(.number.precision(.fractionLength(digits)))
    }

    static func mAh(_ v: Int?) -> String { v.map { String(localized: "\($0) mAh") } ?? "—" }

    static func cycles(_ count: Int?, of design: Int?) -> String {
        guard let count else { return "—" }
        guard let design else { return "\(count)" }
        return "\(count) / \(design)"
    }

    static func volts(_ v: Double?) -> String { v.map { String(localized: "\(decimal($0, digits: 2)) V") } ?? "—" }
}

extension HealthLevel {
    var color: Color {
        switch self {
        case .unknown: .gray
        case .ok: .green
        case .warning: .orange
        case .critical: .red
        }
    }

    var title: String {
        switch self {
        case .unknown: String(localized: "No data")
        case .ok: String(localized: "All good")
        case .warning: String(localized: "Needs attention")
        case .critical: String(localized: "Critical")
        }
    }
}

extension PeripheralKind {
    var symbol: String {
        switch self {
        case .headphones: "airpodspro"
        case .mouse: "magicmouse"
        case .keyboard: "keyboard"
        case .trackpad: "rectangle.and.hand.point.up.left"
        case .gamepad: "gamecontroller"
        case .phone: "iphone"
        case .other: "dot.radiowaves.left.and.right"
        }
    }
}

extension BatteryLevel.Label {
    var title: String {
        switch self {
        case .main: ""
        case .left: String(localized: "L")
        case .right: String(localized: "R")
        case .case_: String(localized: "Case")
        }
    }
}

/// SF Symbol батареї за рівнем заряду.
func batterySymbol(charge: Int?, charging: Bool) -> String {
    guard let charge else { return "minus.plus.batteryblock" }
    if charging { return "battery.100.bolt" }
    switch charge {
    case 88...: return "battery.100"
    case 63...: return "battery.75"
    case 38...: return "battery.50"
    case 13...: return "battery.25"
    default: return "battery.0"
    }
}
