import BatteryHealthCore
import Charts
import SwiftUI

struct DetailView: View {
    enum Subject {
        case mac(MacBattery)
        case peripheral(Peripheral)
    }

    @EnvironmentObject private var model: AppModel
    let subject: Subject
    let report: HealthReport?
    let onBack: () -> Void
    /// `false` лише для рендеру в PNG без прокрутки.
    var scrollable = true

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            if scrollable {
                FittedScrollView(maxHeight: 600) { details }
            } else {
                details
            }
        }
    }

    private var title: String {
        switch subject {
        case .mac: String(localized: "MacBook battery")
        case .peripheral(let p): p.name
        }
    }

    private var historyID: String {
        switch subject {
        case .mac: "mac"
        case .peripheral(let p): p.id
        }
    }

    private var topBar: some View {
        HStack {
            Button(action: onBack) { Label("Back", systemImage: "chevron.left") }
                .buttonStyle(.borderless)
            Spacer()
            Text(title).font(.headline).lineLimit(1)
            Spacer()
            Button { MenuBarWindow.close() } label: { Image(systemName: "xmark.circle.fill") }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Close")
        }
        .padding(12)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 14) {
            status
            attributes
            charts
        }
        .padding(12)
    }

    private var status: some View {
        let level = report?.level ?? .unknown
        return HStack {
            Circle().fill(level.color).frame(width: 12, height: 12)
            Text(level.title).font(.title3.bold())
            Spacer()
            if let health = healthPercent { Text("Health \(health)%").font(.title3) }
        }
    }

    private var healthPercent: Int? {
        switch subject {
        case .mac(let b): b.healthPercent
        case .peripheral(let p): p.health?.healthPercent
        }
    }

    @ViewBuilder private var attributes: some View {
        section("Attributes") {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                switch subject {
                case .mac(let b): macRows(b)
                case .peripheral(let p): peripheralRows(p)
                }
            }
            .font(.callout)
        }
        if let reasons = report?.reasons, !reasons.isEmpty {
            Text(reasons.joined(separator: " · ")).font(.callout).foregroundStyle(report?.level.color ?? .secondary)
        }
    }

    @ViewBuilder private func macRows(_ b: MacBattery) -> some View {
        row("Charge", b.chargePercent.map { Format.percent($0) })
        row("Health", b.healthPercent.map { Format.percent($0) })
        row("Capacity", b.maxCapacityMAh.map { String(localized: "\(Format.mAh($0)) of \(Format.mAh(b.designCapacityMAh))") })
        row("Cycles", b.cycleCount.map { Format.cycles($0, of: b.designCycleCount) })
        // Стан приходить від macOS англійською («Good», «Service Recommended») — перекладаємо відомі значення.
        row("Condition", b.condition.map { Bundle.main.localizedString(forKey: $0, value: $0, table: nil) })
        row("Temperature", b.temperatureC.map { Format.temperature($0) })
        row("Voltage", b.voltageV.map { Format.volts($0) })
        row("Cells", b.cellVoltagesMV.isEmpty ? nil : b.cellVoltagesMV.map { Format.decimal(Double($0) / 1000, digits: 3) }.joined(separator: " · ") + " " + String(localized: "V"))
        row("Current", b.amperageMA.map { String(localized: "\($0) mA") })
        row("Power adapter", b.adapterName.map { name in b.adapterWatts.map { "\(name) (\($0) W)" } ?? name })
        row("Battery model", [b.manufacturer, b.deviceName].compactMap { $0 }.joined(separator: " ").nilIfEmpty)
    }

    @ViewBuilder private func peripheralRows(_ p: Peripheral) -> some View {
        ForEach(p.levels, id: \.label) { l in
            row(levelTitle(l.label), Format.percent(l.percent))
        }
        if let h = p.health {
            row("Health", Format.percent(h.healthPercent))
            row("Capacity", String(localized: "\(Format.mAh(h.nominalCapacityMAh)) of \(Format.mAh(h.designCapacityMAh))"))
            row("Cycles", h.cycleCount.map(String.init))
        }
    }

    private func levelTitle(_ label: BatteryLevel.Label) -> LocalizedStringKey {
        switch label {
        case .main: "Charge"
        case .left: "Left earbud"
        case .right: "Right earbud"
        case .case_: "Case"
        }
    }

    @ViewBuilder private var charts: some View {
        let samples = model.history.samples(for: historyID)
        let health = samples.compactMap { s in s.healthPercent.map { (s.date, $0) } }
        let cycles = samples.compactMap { s in s.cycleCount.map { (s.date, $0) } }
        if health.count >= 2 {
            section("Health, %") {
                Chart(health, id: \.0) { LineMark(x: .value("Date", $0.0), y: .value("%", $0.1)) }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .frame(height: 110)
            }
        }
        if cycles.count >= 2 {
            section("Cycles") {
                Chart(cycles, id: \.0) {
                    LineMark(x: .value("Date", $0.0), y: .value("Cycles", $0.1)).foregroundStyle(.orange)
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(height: 110)
            }
        }
        if health.count < 2 && healthPercent != nil {
            Text("Charts will appear after a few hours of readings.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func row(_ title: LocalizedStringKey, _ value: String?) -> some View {
        if let value {
            GridRow {
                Text(title).foregroundStyle(.secondary)
                Text(value).textSelection(.enabled)
            }
        }
    }

    private func section<C: View>(_ title: LocalizedStringKey, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.bold())
            content()
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
