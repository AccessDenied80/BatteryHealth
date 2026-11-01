import BatteryHealthCore
import Combine
import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var mac: MacBattery?
    @Published private(set) var peripherals: [Peripheral] = []
    @Published private(set) var macReport: HealthReport?
    @Published private(set) var reports: [String: HealthReport] = [:]
    @Published private(set) var lastUpdate: Date?
    @Published private(set) var isRefreshing = false

    let settings: AppSettings
    let history: HistoryStore
    private let macSource = MacBatterySource()
    private let iPhone = IPhoneSource.shared
    private var phones: [Peripheral] = []
    private var lastPhoneRead: Date?
    private let alertStateURL: URL
    private var alertState: AlertState
    private var timer: Timer?
    private var cancellables: Set<AnyCancellable> = []

    static let phoneInterval: TimeInterval = 30 * 60

    var overall: HealthLevel {
        HealthLevel.overall([macReport?.level].compactMap { $0 } + peripherals.map { reports[$0.id]?.level ?? .unknown })
    }

    init(settings: AppSettings) {
        self.settings = settings
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BatteryHealth", isDirectory: true)
        history = HistoryStore(fileURL: dir.appendingPathComponent("history.json"))
        history.load()
        alertStateURL = dir.appendingPathComponent("alert-state.json")
        alertState = (try? Data(contentsOf: alertStateURL))
            .flatMap { try? JSONDecoder().decode(AlertState.self, from: $0) } ?? AlertState()
    }

    func start() {
        Notifier.requestAuthorization()
        scheduleTimer()
        settings.objectWillChange
            .debounce(for: .seconds(1), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.scheduleTimer()
                if !self.settings.monitorIPhone { self.phones = [] }
                self.publish()
            }
            .store(in: &cancellables)
        // Зміна стану живлення (заряд, адаптер) — лише дешеве оновлення батареї Mac.
        macSource.observe { [weak self] in self?.refreshMac() }
        iPhone.onChange = { [weak self] in
            Task { @MainActor in await self?.refresh(includePhone: true) }
        }
        if settings.monitorIPhone { iPhone.start() }
        Task { await refresh(includePhone: true) }
    }

    /// Повне оновлення. iPhone опитуємо не частіше ніж раз на 30 хв, окрім ручного оновлення й підключення.
    func refresh(includePhone: Bool = false) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        mac = MacBatterySource.read()
        let others = await PeripheralSource.read()
        let phoneDue = lastPhoneRead.map { Date().timeIntervalSince($0) >= Self.phoneInterval } ?? true
        if settings.monitorIPhone && (includePhone || phoneDue) {
            iPhone.start()
            phones = await iPhone.read()
            lastPhoneRead = Date()
        }
        peripherals = PeripheralParser.merge(others, phones)
        lastUpdate = Date()
        publish()
        recordHistory()
    }

    private func refreshMac() {
        mac = MacBatterySource.read()
        publish()
    }

    /// Перераховує стани й перевіряє сповіщення на вже зчитаних даних.
    private func publish() {
        let t = settings.thresholds
        macReport = mac.map { HealthEvaluator.evaluate($0, t) }
        reports = Dictionary(peripherals.map { ($0.id, HealthEvaluator.evaluate($0, t)) }, uniquingKeysWith: { a, _ in a })
        guard lastUpdate != nil else { return }
        let alerts = AlertEngine.diff(mac: mac, peripherals: peripherals, thresholds: t, state: &alertState)
        if settings.notificationsEnabled { Notifier.post(alerts) }
        saveAlertState()
    }

    private func recordHistory() {
        let now = Date()
        if let mac {
            history.append(HistorySample(date: now, healthPercent: mac.healthPercent, cycleCount: mac.cycleCount,
                                         chargePercent: mac.chargePercent), for: "mac")
        }
        for p in peripherals where p.health != nil {
            history.append(HistorySample(date: now, healthPercent: p.health?.healthPercent,
                                         cycleCount: p.health?.cycleCount, chargePercent: p.lowestPercent), for: p.id)
        }
        try? history.save()
    }

    private func scheduleTimer() {
        let interval = TimeInterval(max(1, settings.pollMinutes) * 60)
        if let timer, timer.timeInterval == interval { return }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
    }

    private func saveAlertState() {
        do {
            try FileManager.default.createDirectory(at: alertStateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(alertState).write(to: alertStateURL, options: .atomic)
        } catch {
            NSLog("BatteryHealth: cannot save alert state: %@", String(describing: error))
        }
    }
}
