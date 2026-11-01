/// Пороги попереджень. Значення за замовчуванням — зі специфікації.
public struct Thresholds: Codable, Equatable, Sendable {
    public var macHealthWarning = 80
    public var hotC = 45
    public var lowCharge = 15
    /// Повторне сповіщення про низький заряд — лише після заряджання вище цього рівня.
    public var lowChargeRearm = 25
    public var phoneHealthWarning = 80

    public init() {}
}
