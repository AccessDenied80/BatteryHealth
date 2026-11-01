#if DEBUG
import AppKit
import BatteryHealthCore
import SwiftUI

/// Інструменти debug-збірки:
/// - `--dump` — друкує розібрані дані як JSON;
/// - `--snapshot <dir>` — рендерить вікна в PNG (мова: `-AppleLanguages '(uk)'`).
@MainActor
enum DebugTools {
    /// `true`, якщо запущено debug-режим і звичайний старт не потрібен.
    static func handle(model: AppModel, settings: AppSettings) -> Bool {
        let args = CommandLine.arguments
        if args.contains("--dump") {
            Task { @MainActor in
                IPhoneSource.shared.start()
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                await model.refresh(includePhone: true)
                struct Dump: Encodable { var mac: MacBattery?; var peripherals: [Peripheral] }
                let enc = JSONEncoder()
                enc.outputFormatting = [.prettyPrinted, .sortedKeys]
                print(String(decoding: try enc.encode(Dump(mac: model.mac, peripherals: model.peripherals)), as: UTF8.self))
                exit(0)
            }
            return true
        }
        if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
            let dir = URL(fileURLWithPath: args[i + 1], isDirectory: true)
            Task { @MainActor in
                IPhoneSource.shared.start()
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                await model.refresh(includePhone: true)
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                await write(host(BatteryListView().environmentObject(model).environmentObject(settings)), "list", dir)
                if let mac = model.mac {
                    await write(host(DetailView(subject: .mac(mac), report: model.macReport, onBack: {})
                        .frame(width: 400).environmentObject(model)), "detail-mac", dir)
                }
                for (n, p) in model.peripherals.enumerated() {
                    await write(host(DetailView(subject: .peripheral(p), report: model.reports[p.id], onBack: {})
                        .frame(width: 400).environmentObject(model)), "detail-\(n)", dir)
                }
                await write(SettingsWindow.make(settings: settings), "settings", dir)
                exit(0)
            }
            return true
        }
        return false
    }

    private static func host(_ view: some View) -> NSWindow {
        // Вікно поза екраном не малює власного фону, тож додаємо його явно.
        let hosting = NSHostingController(rootView: view.background(Color(nsColor: .windowBackgroundColor)))
        hosting.sizingOptions = [.preferredContentSize]
        return NSWindow(contentViewController: hosting)
    }

    /// Кілька проходів макета: FittedScrollView дізнається висоту вмісту лише після першого.
    private static func write(_ window: NSWindow, _ name: String, _ dir: URL) async {
        guard let view = window.contentView else { return }
        for _ in 0..<3 {
            view.layoutSubtreeIfNeeded()
            if let fitting = window.contentViewController?.view.fittingSize, fitting.height > 1 {
                window.setContentSize(fitting)
            }
            try? await Task.sleep(nanoseconds: 150_000_000)
        }
        view.layoutSubtreeIfNeeded()
        NSLog("BatteryHealth snapshot %@: %@", name, String(describing: view.bounds.size))
        guard view.bounds.width > 0, view.bounds.height > 0,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent("\(name).png"))
    }
}
#endif
