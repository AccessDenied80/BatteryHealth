# Spikes

## iphone-battery.swift — батарея iPhone без прав root (2026-11-01)

`swift spikes/iphone-battery.swift [--keys] [--save file.plist]`

Результат на iPhone SE 2 (iPhone12,8, iOS 27.0.1), підключеному кабелем і водночас видимому по Wi-Fi:

- `MobileDevice.framework` (приватний) завантажується через `dlopen`, `AMDeviceNotificationSubscribe` бачить
  iPhone **двічі** — через USB і через Wi-Fi (дедуплікувати за UDID).
- Після `AMDeviceConnect` + `AMDeviceValidatePairing` + `AMDeviceStartSession`:
  `AMDeviceCopyValue("com.apple.mobile.battery", "BatteryCurrentCapacity" / "BatteryIsCharging")` → заряд 91 %, заряджається.
- `AMDeviceSecureStartService("com.apple.mobile.diagnostics_relay")` працює **лише всередині відкритої сесії**
  (поза нею — помилка `0xE8000007`). Запит `{Request: IORegistry, EntryClass: IOPMPowerSource}` (XML-plist
  з 4-байтовим big-endian префіксом довжини) повертає 45 полів:
  `CycleCount` 1963, `BatteryData.DesignCapacity` 1810, `BatteryData.NominalChargeCapacity` 1456
  (≈ 80 % здоров'я), `CurrentCapacity`, `IsCharging`, `Voltage`, `AdapterDetails.Watts` тощо.
  `MaxCapacity` тут — відсотки (100), не мА·год.
- Прав root не потрібно; iPhone має довіряти цьому Mac.

**Рішення:** iPhone (заряд + здоров'я + цикли) входить у v1. Реальна відповідь (без серійників) —
`Tests/BatteryHealthCoreTests/Fixtures/iphone_ioreg.plist`.
