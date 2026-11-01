import BatteryHealthCore
import Foundation
import GameController
import IOKit

/// Збирає заряд бездротових пристроїв з трьох джерел і зводить їх в один список.
enum PeripheralSource {
    static func read() async -> [Peripheral] {
        let hid = PeripheralParser.parseHID(hidEntries())
        let bluetooth = await bluetoothDevices()
        let gamepads = await MainActor.run { gameControllers() }
        // HID найточніший для Apple-периферії, тож він перший і виграє при збігу адрес.
        return PeripheralParser.merge(hid, bluetooth, gamepads)
    }

    /// IOKit-сервіси з властивістю `BatteryPercent` (Magic Mouse / Keyboard / Trackpad).
    static func hidEntries() -> [[String: Any]] {
        var entries: [[String: Any]] = []
        for className in ["AppleDeviceManagementHIDEventService", "IOHIDDevice"] {
            var iterator: io_iterator_t = 0
            guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(className), &iterator) == KERN_SUCCESS else {
                continue
            }
            defer { IOObjectRelease(iterator) }
            while case let service = IOIteratorNext(iterator), service != IO_OBJECT_NULL {
                defer { IOObjectRelease(service) }
                var props: Unmanaged<CFMutableDictionary>?
                guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                      let d = props?.takeRetainedValue() as? [String: Any],
                      d["BatteryPercent"] != nil
                else { continue }
                entries.append(d)
            }
        }
        return entries
    }

    /// `system_profiler` знає заряд AirPods та деяких інших навушників. Працює ~1–2 с, тому поза головним потоком.
    static func bluetoothDevices() async -> [Peripheral] {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .utility).async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
                p.arguments = ["SPBluetoothDataType", "-json"]
                let pipe = Pipe()
                p.standardOutput = pipe
                p.standardError = FileHandle.nullDevice
                do {
                    try p.run()
                } catch {
                    cont.resume(returning: [])
                    return
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + 20) { if p.isRunning { p.terminate() } }
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                cont.resume(returning: (try? PeripheralParser.parseBluetooth(json: data)) ?? [])
            }
        }
    }

    @MainActor
    static func gameControllers() -> [Peripheral] {
        GCController.controllers().compactMap { c in
            guard let battery = c.battery else { return nil }
            let name = c.vendorName ?? String(localized: "Game controller")
            return Peripheral(
                id: "gc:\(name)",
                name: name,
                kind: .gamepad,
                levels: [BatteryLevel(label: .main, percent: Int((battery.batteryLevel * 100).rounded()))],
                source: "gamecontroller"
            )
        }
    }
}
