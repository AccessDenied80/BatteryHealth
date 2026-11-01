import BatteryHealthCore
import SwiftUI

struct MacBatteryCardView: View {
    let battery: MacBattery
    let report: HealthReport?

    private var level: HealthLevel { report?.level ?? .unknown }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Image(systemName: batterySymbol(charge: battery.chargePercent, charging: battery.isCharging))
                    .font(.title2)
                    .foregroundStyle(level.color)
                VStack(alignment: .leading, spacing: 2) {
                    Text("MacBook battery").font(.headline)
                    Text(powerLine).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                if let health = battery.healthPercent {
                    HealthGauge(percent: health, color: level.color)
                }
            }
            HStack(spacing: 16) {
                stat("bolt.fill", Format.percent(battery.chargePercent))
                stat("arrow.triangle.2.circlepath", String(localized: "\(Format.cycles(battery.cycleCount, of: battery.designCycleCount)) cycles"))
                stat("thermometer.medium", Format.temperature(battery.temperatureC))
            }
            Reasons(report: report)
        }
        .cardStyle(level: level)
    }

    private var powerLine: String {
        if battery.isCharging { return String(localized: "Charging") }
        if battery.externalConnected {
            return battery.fullyCharged ? String(localized: "Charged") : String(localized: "On power adapter, not charging")
        }
        return String(localized: "On battery")
    }
}

struct PeripheralCardView: View {
    let peripheral: Peripheral
    let report: HealthReport?

    private var level: HealthLevel { report?.level ?? .unknown }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center) {
                Image(systemName: peripheral.kind.symbol)
                    .font(.title2)
                    .frame(width: 28)
                    .foregroundStyle(level.color)
                VStack(alignment: .leading, spacing: 2) {
                    Text(peripheral.name).font(.headline).lineLimit(1)
                    Text(levelsText).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if let health = peripheral.health?.healthPercent {
                    HealthGauge(percent: health, color: level.color)
                }
            }
            Reasons(report: report)
        }
        .cardStyle(level: level)
    }

    private var levelsText: String {
        var parts = peripheral.levels.map { l in
            l.label == .main ? "\(l.percent)%" : "\(l.label.title) \(l.percent)%"
        }
        if let cycles = peripheral.health?.cycleCount { parts.append(String(localized: "\(cycles) cycles")) }
        return parts.joined(separator: " · ")
    }
}

/// Кругова шкала здоров'я батареї.
struct HealthGauge: View {
    let percent: Int
    let color: Color

    var body: some View {
        Gauge(value: Double(min(max(percent, 0), 100)), in: 0...100) {
            EmptyView()
        } currentValueLabel: {
            Text("\(percent)%").font(.caption.bold())
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .tint(color)
        .scaleEffect(0.8)
        .frame(width: 44, height: 44)
        .help("Battery health")
    }
}

private struct Reasons: View {
    let report: HealthReport?

    var body: some View {
        if let reasons = report?.reasons, !reasons.isEmpty {
            Text(reasons.joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(report?.level.color ?? .secondary)
        }
    }
}

private func stat(_ symbol: String, _ text: String) -> some View {
    Label(text, systemImage: symbol).font(.caption).foregroundStyle(.secondary)
}

extension View {
    func cardStyle(level: HealthLevel) -> some View {
        padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(level.color.opacity(level >= .warning ? 0.6 : 0), lineWidth: 1))
    }
}
