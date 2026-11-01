import BatteryHealthCore
import Foundation

// Тимчасова точка входу для задачі 6: `BatteryHealth --dump` друкує розібрані дані як JSON.
if CommandLine.arguments.contains("--dump") {
    struct Dump: Encodable {
        var mac: MacBattery?
        var peripherals: [Peripheral]
    }
    IPhoneSource.shared.start()
    Task {
        // MobileDevice повідомляє про вже підключені iPhone у перші секунди після підписки.
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        let phones = await IPhoneSource.shared.read()
        let dump = Dump(mac: MacBatterySource.read(), peripherals: PeripheralParser.merge(await PeripheralSource.read(), phones))
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        print(String(decoding: try enc.encode(dump), as: UTF8.self))
        exit(0)
    }
    // Потрібен саме run loop (не лише головна черга): через нього приходять події MobileDevice.
    RunLoop.main.run()
}
