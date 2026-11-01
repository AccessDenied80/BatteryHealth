import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        Form {
            Section("General") {
                Picker("Check every", selection: $settings.pollMinutes) {
                    Text("1 min").tag(1)
                    Text("5 min").tag(5)
                    Text("15 min").tag(15)
                    Text("30 min").tag(30)
                }
                Toggle("Show Mac charge in the menu bar", isOn: $settings.showChargeInMenuBar)
                Toggle("Monitor connected iPhone", isOn: $settings.monitorIPhone)
                Toggle("Launch at login", isOn: Binding(
                    get: { settings.launchAtLogin },
                    set: { settings.launchAtLogin = $0 }
                ))
            }
            Section("Warning thresholds") {
                Stepper("Mac battery health below: \(settings.macHealthWarning)%", value: $settings.macHealthWarning, in: 50...100, step: 5)
                Stepper("Battery temperature: \(settings.hotC) °C", value: $settings.hotC, in: 35...60, step: 5)
                Stepper("Device charge at or below: \(settings.lowCharge)%", value: $settings.lowCharge, in: 5...50, step: 5)
                Stepper("iPhone battery health below: \(settings.phoneHealthWarning)%", value: $settings.phoneHealthWarning, in: 50...100, step: 5)
            }
            Section("Notifications") {
                Toggle("Show system notifications", isOn: $settings.notificationsEnabled)
            }
        }
        .formStyle(.grouped)
        // Згрупована Form не має власної висоти: без явного розміру вікно стискається до нуля.
        .frame(width: 460, height: 540)
    }
}
