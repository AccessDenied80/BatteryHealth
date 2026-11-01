// Експеримент: чи можна без прав root прочитати батарею iPhone через приватний MobileDevice.framework.
// Запуск: swift spikes/iphone-battery.swift   (iPhone підключений кабелем або по Wi-Fi-синхронізації і довіряє цьому Mac)
import Foundation

typealias Device = UnsafeMutableRawPointer
typealias NotificationCallback = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void

let handle = dlopen("/System/Library/PrivateFrameworks/MobileDevice.framework/MobileDevice", RTLD_NOW)
guard handle != nil else { fatalError("MobileDevice.framework не завантажився") }
func sym<T>(_ name: String, _: T.Type) -> T {
    guard let p = dlsym(handle, name) else { fatalError("немає символу \(name)") }
    return unsafeBitCast(p, to: T.self)
}

let subscribe = sym("AMDeviceNotificationSubscribe",
    (@convention(c) (NotificationCallback, UInt32, UInt32, UnsafeMutableRawPointer?, UnsafeMutablePointer<UnsafeMutableRawPointer?>) -> Int32).self)
let connect = sym("AMDeviceConnect", (@convention(c) (Device) -> Int32).self)
let isPaired = sym("AMDeviceIsPaired", (@convention(c) (Device) -> Int32).self)
let validatePairing = sym("AMDeviceValidatePairing", (@convention(c) (Device) -> Int32).self)
let startSession = sym("AMDeviceStartSession", (@convention(c) (Device) -> Int32).self)
let stopSession = sym("AMDeviceStopSession", (@convention(c) (Device) -> Int32).self)
let disconnect = sym("AMDeviceDisconnect", (@convention(c) (Device) -> Int32).self)
let copyValue = sym("AMDeviceCopyValue", (@convention(c) (Device, CFString?, CFString) -> Unmanaged<CFTypeRef>?).self)
let interfaceType = sym("AMDeviceGetInterfaceType", (@convention(c) (Device) -> Int32).self)
let secureStartService = sym("AMDeviceSecureStartService",
    (@convention(c) (Device, CFString, CFDictionary?, UnsafeMutablePointer<UnsafeMutableRawPointer?>) -> Int32).self)
let connSend = sym("AMDServiceConnectionSend", (@convention(c) (UnsafeMutableRawPointer, UnsafeRawPointer, Int) -> Int).self)
let connReceive = sym("AMDServiceConnectionReceive", (@convention(c) (UnsafeMutableRawPointer, UnsafeMutableRawPointer, Int) -> Int).self)
let connInvalidate = sym("AMDServiceConnectionInvalidate", (@convention(c) (UnsafeMutableRawPointer) -> Void).self)

func value(_ dev: Device, _ domain: String?, _ key: String) -> Any? {
    copyValue(dev, domain as CFString?, key as CFString)?.takeRetainedValue()
}

func receiveExactly(_ conn: UnsafeMutableRawPointer, _ count: Int) -> Data? {
    var data = Data(count: count)
    var got = 0
    while got < count {
        let n = data.withUnsafeMutableBytes { connReceive(conn, $0.baseAddress! + got, count - got) }
        if n <= 0 { return nil }
        got += n
    }
    return data
}

func batteryHealth(_ dev: Device) {
    var conn: UnsafeMutableRawPointer?
    let rc = secureStartService(dev, "com.apple.mobile.diagnostics_relay" as CFString, nil, &conn)
    guard rc == 0, let conn else { print("  diagnostics_relay: не запустився (код \(rc))"); return }
    defer { connInvalidate(conn) }
    for request: [String: Any] in [
        ["Request": "IORegistry", "EntryClass": "IOPMPowerSource"],
        ["Request": "IORegistry", "EntryName": "AppleSmartBattery"],
    ] {
        let body = try! PropertyListSerialization.data(fromPropertyList: request, format: .xml, options: 0)
        var len = UInt32(body.count).bigEndian
        _ = withUnsafeBytes(of: &len) { connSend(conn, $0.baseAddress!, 4) }
        _ = body.withUnsafeBytes { connSend(conn, $0.baseAddress!, body.count) }
        guard let header = receiveExactly(conn, 4) else { print("  діагностика: немає відповіді"); return }
        let size = Int(header.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian })
        guard let reply = receiveExactly(conn, size),
              let plist = try? PropertyListSerialization.propertyList(from: reply, format: nil) as? [String: Any]
        else { print("  діагностика: не розібрано"); return }
        let status = plist["Status"] as? String ?? "?"
        let reg = (plist["Diagnostics"] as? [String: Any])?["IORegistry"] as? [String: Any] ?? [:]
        print("  \(request) → \(status), ключів: \(reg.count)")
        for k in ["CycleCount", "DesignCapacity", "AppleRawMaxCapacity", "NominalChargeCapacity", "MaxCapacity",
                  "CurrentCapacity", "Temperature", "BatteryHealth", "Serial"] where reg[k] != nil {
            print("    \(k) = \(k == "Serial" ? "REDACTED" : String(describing: reg[k]!))")
        }
        if CommandLine.arguments.contains("--keys") {
            for (k, v) in reg.sorted(by: { $0.key < $1.key }) where !k.lowercased().contains("serial") {
                if let d = v as? [String: Any] {
                    print("    \(k): {" + d.keys.sorted().filter { !$0.lowercased().contains("serial") }.map { "\($0)=\(d[$0]!)" }.joined(separator: ", ").prefix(900) + "}")
                } else if !(v is Data) {
                    print("    \(k) = \(v)")
                }
            }
        }
        if let i = CommandLine.arguments.firstIndex(of: "--save"), i + 1 < CommandLine.arguments.count, !reg.isEmpty {
            // Зразок для тестів: без серійників, службових легенд і бінарних блобів.
            var clean = reg.filter { !$0.key.lowercased().contains("serial") && !$0.key.hasPrefix("IOReport") && !($0.value is Data) }
            clean["AppleRawAdapterDetails"] = nil
            clean["IOGeneralInterest"] = nil
            let out = try! PropertyListSerialization.data(fromPropertyList: clean, format: .xml, options: 0)
            try! out.write(to: URL(fileURLWithPath: CommandLine.arguments[i + 1]))
            print("    збережено → \(CommandLine.arguments[i + 1])")
        }
        if !reg.isEmpty { return }
    }
}

let callback: NotificationCallback = { info, _ in
    guard let info else { return }
    let dev = info.load(as: Device.self)
    let msg = info.load(fromByteOffset: MemoryLayout<UnsafeRawPointer>.size, as: UInt32.self)
    guard msg == 1 else { return } // 1 = пристрій підключено
    print("Пристрій: інтерфейс \(interfaceType(dev) == 1 ? "USB" : "Wi-Fi")")
    guard connect(dev) == 0 else { print("  AMDeviceConnect не вдався"); return }
    defer { _ = disconnect(dev) }
    print("  paired: \(isPaired(dev)), validate: \(validatePairing(dev))")
    guard startSession(dev) == 0 else { print("  сесія не стартувала (iPhone не довіряє цьому Mac?)"); return }
    print("  Модель: \(value(dev, nil, "ProductType") ?? "?"), iOS \(value(dev, nil, "ProductVersion") ?? "?")")
    print("  Заряд: \(value(dev, "com.apple.mobile.battery", "BatteryCurrentCapacity") ?? "—")%, "
        + "заряджається: \(value(dev, "com.apple.mobile.battery", "BatteryIsCharging") ?? "—")")
    // Службу діагностики можна запускати лише всередині відкритої сесії.
    batteryHealth(dev)
    _ = stopSession(dev)
}

var notification: UnsafeMutableRawPointer?
print("subscribe: \(subscribe(callback, 0, 0, nil, &notification)); чекаю пристрої 15 с…")
RunLoop.main.run(until: Date().addingTimeInterval(15))
print("Готово.")
