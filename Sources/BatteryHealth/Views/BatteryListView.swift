import BatteryHealthCore
import SwiftUI

/// Що відкрито в деталях: батарея Mac або конкретний пристрій.
enum DetailTarget: Hashable {
    case mac
    case peripheral(String)
}

struct BatteryListView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var settings: AppSettings
    @State private var selected: DetailTarget?

    var body: some View {
        VStack(spacing: 0) {
            if let selected, let detail = detail(for: selected) {
                detail
            } else {
                header
                Divider()
                FittedScrollView(maxHeight: 560) { content }
            }
        }
        .frame(width: 400)
    }

    /// Деталі завжди будуються зі свіжих даних моделі; якщо пристрій зник — повертаємось до списку.
    private func detail(for target: DetailTarget) -> DetailView? {
        let back = { selected = nil }
        switch target {
        case .mac:
            guard let mac = model.mac else { return nil }
            return DetailView(subject: .mac(mac), report: model.macReport, onBack: back)
        case .peripheral(let id):
            guard let p = model.peripherals.first(where: { $0.id == id }) else { return nil }
            return DetailView(subject: .peripheral(p), report: model.reports[id], onBack: back)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Circle().fill(model.overall.color).frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.overall.title).font(.headline)
                updatedText.font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                Task { await model.refresh(includePhone: true) }
            } label: {
                if model.isRefreshing {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .buttonStyle(.borderless)
            .disabled(model.isRefreshing)
            .help("Refresh now")

            Menu {
                Button("Settings…") { SettingsWindow.show(settings: settings) }
                Divider()
                Button("Quit BatteryHealth") { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "gearshape")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()

            Button { MenuBarWindow.close() } label: { Image(systemName: "xmark.circle.fill") }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Close")
        }
        .padding(12)
    }

    /// Вміст без ScrollView — його рендерить і `--snapshot`.
    var content: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let mac = model.mac {
                sectionTitle("This Mac")
                MacBatteryCardView(battery: mac, report: model.macReport)
                    .contentShape(Rectangle())
                    .onTapGesture { selected = .mac }
            }
            if !model.peripherals.isEmpty {
                sectionTitle("Devices")
                ForEach(model.peripherals) { p in
                    PeripheralCardView(peripheral: p, report: model.reports[p.id])
                        .contentShape(Rectangle())
                        .onTapGesture { selected = .peripheral(p.id) }
                }
            } else if model.lastUpdate != nil {
                Text("Connect AirPods, a Magic Mouse/Keyboard, a game controller or an iPhone to see their charge here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
            if model.mac == nil && model.lastUpdate == nil {
                Text("Reading batteries…").foregroundStyle(.secondary).padding(.vertical, 24)
            }
        }
        .padding(12)
    }

    private func sectionTitle(_ title: LocalizedStringKey) -> some View {
        Text(title).font(.caption.bold()).foregroundStyle(.secondary).textCase(.uppercase)
    }

    private var updatedText: Text {
        guard let d = model.lastUpdate else { return Text("Not updated yet") }
        return Text("Updated at \(d.formatted(date: .omitted, time: .shortened))")
    }
}
