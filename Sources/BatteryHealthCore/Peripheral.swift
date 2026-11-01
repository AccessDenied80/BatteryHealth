public enum PeripheralKind: String, Codable, Sendable {
    case headphones, mouse, keyboard, trackpad, gamepad, phone, other
}

/// Рівень заряду однієї частини пристрою (у AirPods — лівий, правий навушник і кейс).
public struct BatteryLevel: Codable, Hashable, Sendable {
    public enum Label: String, Codable, Sendable {
        case main, left, right
        case case_ = "case"
    }

    public var label: Label
    public var percent: Int

    public init(label: Label, percent: Int) {
        self.label = label
        self.percent = percent
    }
}

/// Бездротовий пристрій із відомим рівнем заряду.
public struct Peripheral: Codable, Hashable, Sendable, Identifiable {
    /// Bluetooth-адреса у вигляді `aa:bb:…`, а якщо її немає — `name:<назва>`.
    public var id: String
    public var name: String
    public var kind: PeripheralKind
    public var levels: [BatteryLevel]
    /// Звідки дані: `hid`, `bluetooth`, `gamecontroller`, `iphone`.
    public var source: String

    public init(id: String, name: String, kind: PeripheralKind, levels: [BatteryLevel], source: String) {
        self.id = id
        self.name = name
        self.kind = kind
        self.levels = levels
        self.source = source
    }

    public var lowestPercent: Int? { levels.map(\.percent).min() }
}
