import BatteryHealthCore
import Foundation

// Тимчасова точка входу для задачі 6: `BatteryHealth --dump` друкує розібрані дані як JSON.
if CommandLine.arguments.contains("--dump") {
    struct Dump: Encodable {
        var mac: MacBattery?
        var peripherals: [Peripheral]
    }
    Task {
        let dump = Dump(mac: MacBatterySource.read(), peripherals: await PeripheralSource.read())
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        print(String(decoding: try enc.encode(dump), as: UTF8.self))
        exit(0)
    }
    // Головна черга має крутитися: читання геймпадів виконується на головному акторі.
    dispatchMain()
}
