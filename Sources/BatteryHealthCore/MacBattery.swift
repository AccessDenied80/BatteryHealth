/// Нормалізований знімок стану внутрішньої батареї Mac.
public struct MacBattery: Codable, Hashable, Sendable {
    public var chargePercent: Int?
    /// Поточна максимальна ємність відносно заводської.
    public var healthPercent: Int?
    public var maxCapacityMAh: Int?
    public var designCapacityMAh: Int?
    public var currentCapacityMAh: Int?
    public var cycleCount: Int?
    public var designCycleCount: Int?
    public var temperatureC: Double?
    public var voltageV: Double?
    public var cellVoltagesMV: [Int] = []
    public var amperageMA: Int?
    public var isCharging = false
    public var externalConnected = false
    public var fullyCharged = false
    /// Стан від macOS: «Good», «Service Recommended» тощо.
    public var condition: String?
    public var serviceRecommended = false
    public var adapterName: String?
    public var adapterWatts: Int?
    public var deviceName: String?
    public var manufacturer: String?

    public init() {}
}
