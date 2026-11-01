import BatteryHealthCore
import ServiceManagement
import SwiftUI

@MainActor
final class AppSettings: ObservableObject {
    @AppStorage("pollMinutes") var pollMinutes = 5
    @AppStorage("macHealthWarning") var macHealthWarning = 80
    @AppStorage("hotC") var hotC = 45
    @AppStorage("lowCharge") var lowCharge = 15
    @AppStorage("phoneHealthWarning") var phoneHealthWarning = 80
    @AppStorage("notificationsEnabled") var notificationsEnabled = true
    @AppStorage("showChargeInMenuBar") var showChargeInMenuBar = true
    @AppStorage("monitorIPhone") var monitorIPhone = true

    var thresholds: Thresholds {
        var t = Thresholds()
        t.macHealthWarning = macHealthWarning
        t.hotC = hotC
        t.lowCharge = lowCharge
        t.lowChargeRearm = lowCharge + 10
        t.phoneHealthWarning = phoneHealthWarning
        return t
    }

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            objectWillChange.send()
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("BatteryHealth: launch at login change failed: %@", String(describing: error))
            }
        }
    }
}
