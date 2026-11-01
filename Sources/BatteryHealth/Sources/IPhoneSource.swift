import BatteryHealthCore
import Foundation

/// Заряд і знос батареї iPhone через приватний MobileDevice.framework (той самий, яким користується Finder).
/// Без прав root; iPhone має довіряти цьому Mac. Деталі протоколу — spikes/README.md.
/// Будь-яка помилка означає «iPhone не показуємо», а не збій застосунку.
final class IPhoneSource: @unchecked Sendable {
    static let shared = IPhoneSource()

    private typealias Device = UnsafeMutableRawPointer
    private typealias NotificationCallback = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void

    private struct API {
        let subscribe: @convention(c) (NotificationCallback, UInt32, UInt32, UnsafeMutableRawPointer?, UnsafeMutablePointer<UnsafeMutableRawPointer?>) -> Int32
        let retain: @convention(c) (Device) -> Device
        let release: @convention(c) (Device) -> Void
        let identifier: @convention(c) (Device) -> Unmanaged<CFString>?
        let interfaceType: @convention(c) (Device) -> Int32
        let connect: @convention(c) (Device) -> Int32
        let validatePairing: @convention(c) (Device) -> Int32
        let startSession: @convention(c) (Device) -> Int32
        let stopSession: @convention(c) (Device) -> Int32
        let disconnect: @convention(c) (Device) -> Int32
        let copyValue: @convention(c) (Device, CFString?, CFString) -> Unmanaged<CFTypeRef>?
        let startService: @convention(c) (Device, CFString, CFDictionary?, UnsafeMutablePointer<UnsafeMutableRawPointer?>) -> Int32
        let send: @convention(c) (UnsafeMutableRawPointer, UnsafeRawPointer, Int) -> Int
        let receive: @convention(c) (UnsafeMutableRawPointer, UnsafeMutableRawPointer, Int) -> Int
        let invalidate: @convention(c) (UnsafeMutableRawPointer) -> Void

        init?() {
            guard let h = dlopen("/System/Library/PrivateFrameworks/MobileDevice.framework/MobileDevice", RTLD_NOW) else { return nil }
            func sym<T>(_ name: String) -> T? { dlsym(h, name).map { unsafeBitCast($0, to: T.self) } }
            guard let subscribe: @convention(c) (NotificationCallback, UInt32, UInt32, UnsafeMutableRawPointer?, UnsafeMutablePointer<UnsafeMutableRawPointer?>) -> Int32 = sym("AMDeviceNotificationSubscribe"),
                  let retain: @convention(c) (Device) -> Device = sym("AMDeviceRetain"),
                  let release: @convention(c) (Device) -> Void = sym("AMDeviceRelease"),
                  let identifier: @convention(c) (Device) -> Unmanaged<CFString>? = sym("AMDeviceCopyDeviceIdentifier"),
                  let interfaceType: @convention(c) (Device) -> Int32 = sym("AMDeviceGetInterfaceType"),
                  let connect: @convention(c) (Device) -> Int32 = sym("AMDeviceConnect"),
                  let validatePairing: @convention(c) (Device) -> Int32 = sym("AMDeviceValidatePairing"),
                  let startSession: @convention(c) (Device) -> Int32 = sym("AMDeviceStartSession"),
                  let stopSession: @convention(c) (Device) -> Int32 = sym("AMDeviceStopSession"),
                  let disconnect: @convention(c) (Device) -> Int32 = sym("AMDeviceDisconnect"),
                  let copyValue: @convention(c) (Device, CFString?, CFString) -> Unmanaged<CFTypeRef>? = sym("AMDeviceCopyValue"),
                  let startService: @convention(c) (Device, CFString, CFDictionary?, UnsafeMutablePointer<UnsafeMutableRawPointer?>) -> Int32 = sym("AMDeviceSecureStartService"),
                  let send: @convention(c) (UnsafeMutableRawPointer, UnsafeRawPointer, Int) -> Int = sym("AMDServiceConnectionSend"),
                  let receive: @convention(c) (UnsafeMutableRawPointer, UnsafeMutableRawPointer, Int) -> Int = sym("AMDServiceConnectionReceive"),
                  let invalidate: @convention(c) (UnsafeMutableRawPointer) -> Void = sym("AMDServiceConnectionInvalidate")
            else { return nil }
            self.subscribe = subscribe; self.retain = retain; self.release = release; self.identifier = identifier
            self.interfaceType = interfaceType; self.connect = connect; self.validatePairing = validatePairing
            self.startSession = startSession; self.stopSession = stopSession; self.disconnect = disconnect
            self.copyValue = copyValue; self.startService = startService; self.send = send; self.receive = receive
            self.invalidate = invalidate
        }
    }

    private let api = API()
    private let queue = DispatchQueue(label: "BatteryHealth.iPhone")
    private let lock = NSLock()
    /// UDID → (пристрій, тип підключення). USB має перевагу над Wi-Fi.
    private var devices: [String: (device: Device, usb: Bool)] = [:]
    private var cache: [String: Peripheral] = [:]
    private var reading = false
    private var notification: UnsafeMutableRawPointer?
    var onChange: (@Sendable () -> Void)?

    var isAvailable: Bool { api != nil }

    /// Підписка на підключення/відключення iPhone. Колбек MobileDevice приходить у головний run loop.
    func start() {
        guard let api, notification == nil else { return }
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        _ = api.subscribe({ info, ctx in
            guard let info, let ctx else { return }
            Unmanaged<IPhoneSource>.fromOpaque(ctx).takeUnretainedValue().handle(info)
        }, 0, 0, ctx, &notification)
    }

    private func handle(_ info: UnsafeMutableRawPointer) {
        guard let api else { return }
        let dev = info.load(as: Device.self)
        let msg = info.load(fromByteOffset: MemoryLayout<UnsafeRawPointer>.size, as: UInt32.self)
        guard let udid = api.identifier(dev)?.takeRetainedValue() as String? else { return }
        let usb = api.interfaceType(dev) == 1
        lock.lock()
        switch msg {
        case 1: // підключено
            if let old = devices[udid] {
                if old.usb && !usb { lock.unlock(); return }
                api.release(old.device)
            }
            devices[udid] = (api.retain(dev), usb)
        case 2: // відключено
            if let old = devices[udid], old.usb == usb {
                api.release(old.device)
                devices[udid] = nil
                cache[udid] = nil
            }
        default:
            break
        }
        lock.unlock()
        onChange?()
    }

    /// Свіжі дані, якщо iPhone відповів; якщо попереднє читання ще триває — останні відомі.
    func read() async -> [Peripheral] {
        guard let api else { return [] }
        let (snapshot, cached) = beginRead()
        if let cached { return cached }

        return await withCheckedContinuation { cont in
            queue.async {
                var fresh: [String: Peripheral] = [:]
                for (udid, entry) in snapshot {
                    if let p = Self.query(api, entry.device, udid: udid) { fresh[udid] = p }
                }
                self.lock.lock()
                // Пристрої, що відключилися під час читання, не повертаємо.
                self.cache = fresh.filter { self.devices[$0.key] != nil }
                self.reading = false
                let result = Array(self.cache.values)
                self.lock.unlock()
                cont.resume(returning: result.sorted { $0.name < $1.name })
            }
        }
    }

    /// Позначає початок читання. Якщо інше читання вже триває — повертає кеш замість нового запиту.
    private func beginRead() -> (devices: [String: (device: Device, usb: Bool)], cached: [Peripheral]?) {
        lock.lock(); defer { lock.unlock() }
        if reading { return (devices, Array(cache.values)) }
        reading = true
        return (devices, nil)
    }

    private static func query(_ api: API, _ dev: Device, udid: String) -> Peripheral? {
        guard api.connect(dev) == 0 else { return nil }
        defer { _ = api.disconnect(dev) }
        guard api.validatePairing(dev) == 0, api.startSession(dev) == 0 else { return nil }
        defer { _ = api.stopSession(dev) }

        func value(_ domain: String?, _ key: String) -> Any? {
            api.copyValue(dev, domain as CFString?, key as CFString)?.takeRetainedValue()
        }
        let name = value(nil, "DeviceName") as? String ?? "iPhone"
        let charge = MacBatteryParser.int(value("com.apple.mobile.battery", "BatteryCurrentCapacity"))
        // Служба діагностики працює лише всередині відкритої сесії.
        let health = diagnostics(api, dev).flatMap(PhoneParser.parseHealth(ioreg:))
        return PhoneParser.peripheral(udid: udid, name: name, chargePercent: charge, health: health)
    }

    private static func diagnostics(_ api: API, _ dev: Device) -> [String: Any]? {
        var conn: UnsafeMutableRawPointer?
        guard api.startService(dev, "com.apple.mobile.diagnostics_relay" as CFString, nil, &conn) == 0, let conn else { return nil }
        defer { api.invalidate(conn) }

        let request: [String: Any] = ["Request": "IORegistry", "EntryClass": "IOPMPowerSource"]
        guard let body = try? PropertyListSerialization.data(fromPropertyList: request, format: .xml, options: 0) else { return nil }
        var length = UInt32(body.count).bigEndian
        guard withUnsafeBytes(of: &length, { api.send(conn, $0.baseAddress!, 4) }) == 4,
              body.withUnsafeBytes({ api.send(conn, $0.baseAddress!, body.count) }) == body.count,
              let header = receive(api, conn, 4)
        else { return nil }
        let size = Int(header.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian })
        guard size > 0, size < 16_000_000, let reply = receive(api, conn, size),
              let plist = try? PropertyListSerialization.propertyList(from: reply, format: nil) as? [String: Any],
              plist["Status"] as? String == "Success"
        else { return nil }
        return (plist["Diagnostics"] as? [String: Any])?["IORegistry"] as? [String: Any]
    }

    private static func receive(_ api: API, _ conn: UnsafeMutableRawPointer, _ count: Int) -> Data? {
        var data = Data(count: count)
        var got = 0
        while got < count {
            let n = data.withUnsafeMutableBytes { api.receive(conn, $0.baseAddress! + got, count - got) }
            if n <= 0 { return nil }
            got += n
        }
        return data
    }
}
