import BatteryHealthCore
import Foundation
import IOKit
import IOKit.ps

/// Читає внутрішню батарею Mac з IOKit і стежить за змінами джерела живлення.
@MainActor
final class MacBatterySource {
    private var runLoopSource: CFRunLoopSource?
    private var onChange: (() -> Void)?

    nonisolated static func read() -> MacBattery? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != IO_OBJECT_NULL else { return nil }
        defer { IOObjectRelease(service) }

        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let registry = props?.takeRetainedValue() as? [String: Any]
        else { return nil }
        return MacBatteryParser.parse(registry: registry, powerSource: internalPowerSource())
    }

    /// Опис внутрішньої батареї з IOPS — там стан від macOS («Service Recommended») і заряд у %.
    nonisolated static func internalPowerSource() -> [String: Any]? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }
        for ps in list {
            guard let d = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any] else { continue }
            if d[kIOPSTypeKey] as? String == kIOPSInternalBatteryType { return d }
        }
        return nil
    }

    /// Викликає `handler` щоразу, коли macOS повідомляє про зміну стану живлення (заряд, адаптер).
    func observe(_ handler: @escaping () -> Void) {
        onChange = handler
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource({ ctx in
            guard let ctx else { return }
            let me = Unmanaged<MacBatterySource>.fromOpaque(ctx).takeUnretainedValue()
            MainActor.assumeIsolated { me.onChange?() }
        }, ctx)?.takeRetainedValue() else { return }
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
    }
}
