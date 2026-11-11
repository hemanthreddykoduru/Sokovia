import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        AppearanceManager.shared.applyTheme()
        StatusItemManager.shared.setup()

        Task { @MainActor in
            let state = AppState.shared
            DevicePairingWindowController.shared.startPolling()
            if state.config.isConfigured {
                await state.startDrive()
                StatusItemManager.shared.updateMenu()
            } else {
                // First launch: show settings window to input R2 keys
                SettingsWindowController.shared.show()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            await AppState.shared.stopDrive()
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 2.0)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()

