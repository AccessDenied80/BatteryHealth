import Foundation

public struct HistorySample: Codable, Equatable, Sendable {
    public var date: Date
    public var healthPercent: Int?
    public var cycleCount: Int?
    public var chargePercent: Int?

    public init(date: Date, healthPercent: Int? = nil, cycleCount: Int? = nil, chargePercent: Int? = nil) {
        self.date = date
        self.healthPercent = healthPercent
        self.cycleCount = cycleCount
        self.chargePercent = chargePercent
    }
}

/// Історія показників за пристроями в JSON-файлі: 365 днів, не частіше одного зразка на годину.
public final class HistoryStore: @unchecked Sendable {
    static let retention: TimeInterval = 365 * 86_400
    static let minSpacing: TimeInterval = 3_600

    public let fileURL: URL
    private var byID: [String: [HistorySample]] = [:]
    private let lock = NSLock()

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func append(_ sample: HistorySample, for id: String) {
        lock.lock(); defer { lock.unlock() }
        var list = byID[id] ?? []
        // Батарея Mac оновлюється щохвилини; в історії досить одного зразка на годину — беремо найсвіжіший.
        if let last = list.last, sample.date.timeIntervalSince(last.date) < Self.minSpacing {
            list[list.count - 1] = sample
        } else {
            list.append(sample)
        }
        let cutoff = sample.date.addingTimeInterval(-Self.retention)
        byID[id] = list.filter { $0.date >= cutoff }
    }

    public func samples(for id: String) -> [HistorySample] {
        lock.lock(); defer { lock.unlock() }
        return byID[id] ?? []
    }

    public func save() throws {
        lock.lock(); let snapshot = byID; lock.unlock()
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(snapshot).write(to: fileURL, options: .atomic)
    }

    /// Відсутній або пошкоджений файл означає порожню історію.
    public func load() {
        let loaded = (try? Data(contentsOf: fileURL))
            .flatMap { try? JSONDecoder().decode([String: [HistorySample]].self, from: $0) } ?? [:]
        lock.lock(); byID = loaded; lock.unlock()
    }
}
