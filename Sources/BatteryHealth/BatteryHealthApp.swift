import BatteryHealthCore
import SwiftUI

@main
struct BatteryHealthApp: App {
    @StateObject private var settings: AppSettings
    @StateObject private var model: AppModel

    init() {
        let settings = AppSettings()
        let model = AppModel(settings: settings)
        _settings = StateObject(wrappedValue: settings)
        _model = StateObject(wrappedValue: model)
        #if DEBUG
        if DebugTools.handle(model: model, settings: settings) { return }
        #endif
        model.start()
    }

    var body: some Scene {
        MenuBarExtra {
            BatteryListView()
                .environmentObject(model)
                .environmentObject(settings)
        } label: {
            MenuBarLabel(model: model, settings: settings)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Іконка батареї Mac (за зарядом) з кольором найгіршого стану і, за бажанням, відсотком заряду.
private struct MenuBarLabel: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: AppSettings

    var body: some View {
        let mac = model.mac
        let symbol = mac == nil ? "battery.100" : batterySymbol(charge: mac?.chargePercent, charging: mac?.isCharging ?? false)
        HStack(spacing: 3) {
            Image(systemName: symbol)
                .symbolRenderingMode(.palette)
                .foregroundStyle(model.overall >= .warning ? model.overall.color : .primary)
            if settings.showChargeInMenuBar, let charge = mac?.chargePercent {
                Text("\(charge)%")
            }
        }
    }
}
