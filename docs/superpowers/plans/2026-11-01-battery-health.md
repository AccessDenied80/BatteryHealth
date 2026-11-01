# BatteryHealth Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Menu-bar macOS app showing Mac battery health (full IOKit data), charge of Bluetooth peripherals/AirPods/game controllers and (if the spike succeeds) iPhone, with history and once-per-event notifications — no extra privileges.

**Architecture:** SwiftPM package: `BatteryHealthCore` (pure, tested: models, parsers for IOKit dictionaries / IOPS dictionaries / system_profiler JSON / HID dictionaries, health evaluator, alert engine, history store) + `BatteryHealth` (SwiftUI MenuBarExtra app: data sources that call IOKit / IOPS / `system_profiler` / GameController / MobileDevice, model, notifications, UI). Mirrors DiskHealth (`~/Work/MacOs/ssd`) — copy its scripts and UI patterns.

**Tech Stack:** Swift 6.2 (CLT only), SwiftUI, Swift Charts, IOKit + IOKit.ps, GameController, UserNotifications, ServiceManagement, swift-testing; private `MobileDevice.framework` via `dlopen` (iPhone only).

**Spec:** `docs/superpowers/specs/2026-11-01-battery-health-design.md`

## Global Constraints

- macOS 13+, `swift-tools-version:6.0`, universal (arm64 + x86_64) release build.
- App `BatteryHealth`, bundle id `io.github.accessdenied80.BatteryHealth`, `LSUIElement = true`, MIT, author `AccessDenied80 <AccessDenied80@gmail.com>`.
- No root, no privileged helper, no SMC writes.
- English keys + `uk.lproj/Localizable.strings`; core strings via `String(localized:)`; tests assert English.
- Defaults: Mac health warning < 80 %; Mac battery hot ≥ 45 °C; low charge ≤ 15 %, re-arm after > 25 %; iPhone health warning < 80 %. Poll Mac + peripherals every 5 min (Mac also on IOPS change), iPhone every 30 min.
- History: `~/Library/Application Support/BatteryHealth/history.json`, 365 days, one sample per device per hour at most.
- Fixtures must contain no real serial numbers (`REDACTED`).
- Tests only via `scripts/test.sh` (copied from DiskHealth: `-F/-rpath` CLT Frameworks + `-disable-cross-import-overlays`).
- `.gitignore` must be force-added (`git add -f`) — the user's global ignore excludes it.

## Review Focus

- Mac without a battery (desktop) or `BatteryInstalled = false` → no "This Mac" card, no crash, no alerts. Test in Task 2.
- `Temperature` is in hundredths of °C (2985 → 29.85 °C); `AppleRawMaxCapacity` may be missing on old Macs → fall back to `MaxCapacity` only if > 100 (mAh), else health = nil. Test in Task 2.
- system_profiler battery values are strings `"85%"`; missing/garbage values → nil, device still listed only if any level is known. Test in Task 3.
- Same peripheral reported by both HID and system_profiler → one entry (match by address normalised `00-00-…` ↔ `00:00:…`), HID value wins. Test in Task 3.
- Low-charge alert must not repeat while charge hovers at 14–16 %. Test in Task 4.

---

### Task 1: Skeleton

**Files:** `Package.swift`, `.gitignore` (`.build/ build/ vendor/ *.app .DS_Store .superpowers/ .swiftpm/`), `scripts/test.sh` (copy from `~/Work/MacOs/ssd/scripts/test.sh`), `Sources/BatteryHealthCore/Placeholder.swift`, `Sources/BatteryHealth/main.swift`, `Tests/BatteryHealthCoreTests/{SmokeTests,TestHelpers}.swift`.
- Targets: `BatteryHealthCore`, executable `BatteryHealth` (deps core), `BatteryHealthCoreTests` (resources `.copy("Fixtures")`).
- `TestHelpers`: `func fixtureData(_ name: String, _ ext: String) throws -> Data`, `func fixturePlist(_ name: String) throws -> Any` (PropertyListSerialization).

- [ ] git init (`main`), local user `AccessDenied80 <AccessDenied80@gmail.com>`; smoke test loads `mac_battery.plist`; `scripts/test.sh` → 1 pass; commit (`git add -f .gitignore`).

### Task 2: Mac battery model + parser

**Files:** `Sources/BatteryHealthCore/MacBattery.swift`, `MacBatteryParser.swift`; test `MacBatteryParserTests.swift`.

**Interfaces (produces):**
```swift
public struct MacBattery: Codable, Hashable, Sendable {
  public var chargePercent: Int?          // IOPS "Current Capacity" (or CurrentCapacity/MaxCapacity if both ≤ 100)
  public var healthPercent: Int?          // round(AppleRawMaxCapacity * 100 / DesignCapacity)
  public var maxCapacityMAh: Int?; public var designCapacityMAh: Int?; public var currentCapacityMAh: Int?
  public var cycleCount: Int?; public var designCycleCount: Int?   // DesignCycleCount9C, else IOPS DesignCycleCount
  public var temperatureC: Double?        // Temperature / 100
  public var voltageV: Double?; public var cellVoltagesMV: [Int]
  public var amperageMA: Int?
  public var isCharging: Bool; public var externalConnected: Bool; public var fullyCharged: Bool
  public var condition: String?           // IOPS BatteryHealthCondition if non-empty, else BatteryHealth ("Good")
  public var serviceRecommended: Bool     // condition contains "Service" || PermanentFailureStatus != 0
  public var adapterName: String?; public var adapterWatts: Int?
  public var deviceName: String?; public var manufacturer: String?
}
public enum MacBatteryParser {
  public static func parse(registry: [String: Any], powerSource: [String: Any]?) -> MacBattery?  // nil if BatteryInstalled != true
}
```
- [ ] Tests (fixtures `mac_battery.plist`, `ps_good.plist`, `ps_service.plist`): `parsesRealBattery` — health 95, max 6585, design 6900, cycles 197, designCycles 1000, temp ≈ 29.85, voltage ≈ 12.047, cells `[3960, 4021, 4063]`, adapter `"87W USB-C Power Adapter"`/86, condition `"Good"`, `serviceRecommended == false`, charge 80 (from ps_good); `serviceRecommendedFromIOPS` (ps_service → true); `permanentFailureFlag` (registry PermanentFailureStatus=1 → true); `noBatteryReturnsNil` (BatteryInstalled=false and empty dict); `missingRawMaxFallsBack` (remove AppleRawMaxCapacity → uses MaxCapacity 6585; with MaxCapacity=100 → health nil).
- [ ] Run → fail; implement; run → pass; commit.

### Task 3: Peripheral model + parsers

**Files:** `Peripheral.swift`, `PeripheralParser.swift`; test `PeripheralParserTests.swift`.

**Interfaces:**
```swift
public enum PeripheralKind: String, Codable, Sendable { case headphones, mouse, keyboard, trackpad, gamepad, phone, other }
public struct BatteryLevel: Codable, Hashable, Sendable { public var label: Label; public var percent: Int
  public enum Label: String, Codable, Sendable { case main, left, right, case_ = "case" } }
public struct Peripheral: Codable, Hashable, Sendable, Identifiable {
  public var id: String            // normalised address "00:00:00:00:00:01", else "name:<name>"
  public var name: String; public var kind: PeripheralKind; public var levels: [BatteryLevel]
  public var source: String        // "hid" | "bluetooth" | "gamecontroller" | "iphone"
  public var lowestPercent: Int? { get }
}
public enum PeripheralParser {
  public static func parseBluetooth(json: Data) throws -> [Peripheral]   // connected only, ≥1 level
  public static func parseHID(_ entries: [[String: Any]]) -> [Peripheral]
  public static func merge(_ lists: [Peripheral]...) -> [Peripheral]     // by id, first list wins
  static func percent(_ s: Any?) -> Int?                                 // "85%" / 85 → 85, else nil
}
```
- [ ] Tests: `bluetoothAirPods` (3 levels left 85/right 90/case 100, kind headphones), `bluetoothMouse` (main 60), `bluetoothSkipsWithoutLevels` (HBQ not listed), `bluetoothSkipsDisconnected` (iPhone not listed), `hidParses` (2 devices, mouse 61, keyboard 12 kind keyboard), `mergeDedupesByAddressHIDWins` (merge(hid, bt) → Magic Mouse once, 61), `percentParsing` (`"85%"`→85, `85`→85, `"n/a"`→nil, nil→nil).
- [ ] fail → implement → pass → commit.

### Task 4: Evaluation + alerts

**Files:** `Thresholds.swift`, `Health.swift`, `AlertEngine.swift`; tests `HealthTests.swift`, `AlertEngineTests.swift`.

**Interfaces:**
```swift
public struct Thresholds: Codable, Equatable, Sendable { public var macHealthWarning = 80; public var hotC = 45
  public var lowCharge = 15; public var lowChargeRearm = 25; public var phoneHealthWarning = 80; public init() {} }
public enum HealthLevel: Int, Codable, Comparable, Sendable { case unknown, ok, warning, critical; static func overall(_:) }
public struct HealthReport: Equatable, Sendable { public var level: HealthLevel; public var reasons: [String] }
public enum HealthEvaluator {
  public static func evaluate(_ b: MacBattery, _ t: Thresholds) -> HealthReport
  public static func evaluate(_ p: Peripheral, _ t: Thresholds) -> HealthReport
}
public struct Alert: Equatable, Sendable { public var key, title, body: String; public var critical: Bool }
public struct AlertState: Codable, Equatable, Sendable { public var active: Set<String> = []; public init() {} }
public enum AlertEngine {
  public static func diff(mac: MacBattery?, peripherals: [Peripheral], thresholds: Thresholds, state: inout AlertState) -> [Alert]
}
```
- Mac: serviceRecommended → critical "Service recommended"; health < macHealthWarning → warning "Battery health 75%"; temp ≥ hotC → warning "Battery temperature 46 °C". Peripheral: lowest ≤ lowCharge → warning "Charge 12%".
- Alert keys: `mac|service`, `mac|health\(threshold)`, `mac|hot`, `\(id)|low`. Low-charge key cleared only when lowest > lowChargeRearm; other keys cleared when condition false. Stale `mac|health*` keys dropped when threshold changes (DiskHealth lesson).
- [ ] Tests: health levels (good fixture → ok; health 75 → warning with reason "Battery health 75%"; service → critical; 46 °C → warning; keyboard 12 % → warning "Charge 12%"); alerts: `lowChargeOnce`, `lowChargeNoRepeatWhileHovering` (14→16→14 → 1 alert), `lowChargeRearmsAfterCharging` (14→30→14 → 2), `serviceOnce`, `healthThresholdChangeDropsStaleKey`, `stateRoundTrip`, English bodies (`"Charge 12%. Time to charge."`, `"Battery health dropped to 75% (threshold 80%)."`).
- [ ] fail → implement → pass → commit.

### Task 5: History store

**Files:** `HistoryStore.swift`; test `HistoryStoreTests.swift`. Copy DiskHealth's store (lock, JSON, 365-day prune) with sample `{date, healthPercent?, cycleCount?, chargePercent?}` keyed by device id (`"mac"`, peripheral id) and **at most one sample per id per hour** (replace the last one if < 1 h old).
- [ ] Tests: append+reload, prune > 365 d, hourly coalescing (two appends 10 min apart → 1 sample with the later values). fail → implement → pass → commit.

### Task 6: Live data sources (app target)

**Files:** `Sources/BatteryHealth/Sources/MacBatterySource.swift`, `PeripheralSource.swift`.
- `MacBatterySource.read() -> MacBattery?`: `IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))` + `IORegistryEntryCreateCFProperties`; IOPS internal battery description; `observe(_ onChange:)` via `IOPSNotificationCreateRunLoopSource`.
- `PeripheralSource.read() async -> [Peripheral]`: HID entries = IOKit services matching any class with property `BatteryPercent` (iterate `IOServiceMatching("IOHIDDevice")` and `AppleDeviceManagementHIDEventService`, read `Product`, `BatteryPercent`, `DeviceAddress`); Bluetooth = run `/usr/sbin/system_profiler SPBluetoothDataType -json` off-main (timeout 20 s); game controllers = `GCController.controllers()` with `battery?.batteryLevel` → kind gamepad, id `gc:<vendorName>`. Return `PeripheralParser.merge(hid, bluetooth, gamepads)`.
- [ ] `swift build` ok; add DEBUG `--dump` flag printing parsed `MacBattery` + peripherals as JSON; run it: Mac battery shows health 95 / cycles 197. Ask the user to connect AirPods/mouse once and re-run `--dump`; if keys differ from `bluetooth.json`, update fixture + parser (ledger a ruling). Commit.

### Task 7: iPhone spike (decision gate)

**Files:** `spikes/iphone-battery.swift` (not part of the package).
- `dlopen("/System/Library/PrivateFrameworks/MobileDevice.framework/MobileDevice")`; resolve `AMDeviceNotificationSubscribe`, `AMDeviceConnect`, `AMDeviceIsPaired`, `AMDeviceValidatePairing`, `AMDeviceStartSession`, `AMDeviceCopyValue`, `AMDeviceStopSession`, `AMDeviceDisconnect`; on device-attached callback read `AMDeviceCopyValue(dev, "com.apple.mobile.battery", "BatteryCurrentCapacity")` and `BatteryIsCharging`, plus `DeviceName`; print and exit after 15 s.
- Then try health: `AMDeviceSecureStartService(dev, "com.apple.mobile.diagnostics_relay", nil, &conn)`, send XML plist `{Request: "IORegistry", EntryClass: "AppleSmartBattery"}` (4-byte big-endian length prefix) via `AMDServiceConnectionSend`, read reply via `AMDServiceConnectionReceive`; print `CycleCount`, `DesignCapacity`, `AppleRawMaxCapacity`/`NominalChargeCapacity`.
- [ ] Ask the user to connect & trust the iPhone; run `swift spikes/iphone-battery.swift`. **Gate:** charge read → Task 8 includes charge; health read → also health. Nothing works → ledger ruling "iPhone out of v1", skip Task 8. Commit spike + result note in `spikes/README.md`.

### Task 8: iPhone source (only if Task 7 passed)

**Files:** `Sources/BatteryHealth/Sources/IPhoneSource.swift`; core `IPhoneBattery` parse helper + test with a fixture of the spike's real reply (serials redacted).
- `IPhoneSource` keeps a MobileDevice subscription, exposes `devices() async -> [Peripheral]` (kind `.phone`, source `"iphone"`, id = UDID hash, level main) and optional health (`MacBattery`-like `PhoneBatteryHealth {healthPercent, cycleCount}` added to `Peripheral` as optional `health: PhoneBatteryHealth?`). Every call guarded: any failure → empty list, never crash.
- Alert `\(id)|phoneHealth\(threshold)` when health < phoneHealthWarning (extend AlertEngine + test).
- [ ] Tests for parser + alert; build; manual check with the iPhone; commit.

### Task 9: App model, settings, notifications, UI, localization

**Files:** `AppModel.swift`, `Settings.swift`, `Notifier.swift` (copy DiskHealth incl. foreground-presenter delegate and `%@` NSLog), `SettingsWindow.swift`, `MenuBarWindow.swift`, `Views/{FittedScrollView,BatteryListView,MacBatteryCardView,PeripheralCardView,DetailView,SettingsView}.swift`, `Format.swift`, `BatteryHealthApp.swift`, `Snapshot.swift` (DEBUG), `Resources/{en,uk}.lproj/Localizable.strings`, `Resources/Info.plist`.
- AppModel: holds `mac`, `peripherals`, reports, `refresh()` (Mac + peripherals + iPhone if enabled), timers (5 min / 30 min), IOPS observer triggers Mac-only refresh, alerts checked after each refresh and on settings change, history append.
- Settings: thresholds above, interval, launch at login, notifications toggle, "Show Mac charge % in menu bar" (default on), "Monitor iPhone" (default on if Task 8 shipped).
- Menu bar label: SF Symbol `battery.100`/`75`/`50`/`25`/`0` by Mac charge (or `bolt` badge when charging), tinted by overall level; optional text `"80%"`. Desktop Mac: symbol `minus.plus.batteryblock`.
- Mac card: charge gauge, health %, cycles x/1000, temperature, charging/adapter line. Peripheral card: SF Symbol per kind (`airpodspro`, `magicmouse`, `keyboard`, `rectangle.and.hand.point.up.left`, `gamecontroller`, `iphone`), levels "L 85% · R 90% · Case 100%". Detail: all Mac fields (only non-nil), cell voltages, charts health + cycles (≥ 2 points), close/back buttons as in DiskHealth.
- [ ] Build; snapshots in en and uk (`--snapshot` via bundled debug binary like DiskHealth); fix layout; commit.

### Task 10: Packaging, icon, docs, verification

**Files:** `scripts/build-app.sh` (copy DiskHealth's: universal per-arch `swift build --triple`, lipo, lproj, LICENSE, `--dmg`; **no smartctl**), `scripts/make-icon.swift` (same style as DiskHealth, battery glyph `battery.100.bolt` + heart/pulse, green→teal gradient), `Resources/AppIcon.icns`, `README.md` (English + Ukrainian, install/Gatekeeper, what each source can/can't read), `LICENSE` (MIT 2026 AccessDenied80).
- [ ] `scripts/build-app.sh --dmg` → universal app + DMG; launch; menu bar shows battery; trigger a test notification by setting health threshold to 99 %; all tests pass; final self-review (whole diff) with fixes TDD; commit.
- [ ] Publishing (`gh repo create AccessDenied80/BatteryHealth --public`, release v1.0.0 with DMG) **only after the user's explicit OK**.
