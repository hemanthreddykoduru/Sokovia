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

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            handleDeepLink(url)
        }
    }

    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "sokovia" else { return }
        // Format: sokovia://auth?email=...&name=...
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        let queryItems = components.queryItems ?? []
        let email = queryItems.first(where: { $0.name == "email" })?.value ?? ""
        let name = queryItems.first(where: { $0.name == "name" })?.value ?? ""

        guard !email.isEmpty else { return }

        Task { @MainActor in
            AppState.shared.config.userEmail = email
            do {
                let (bucket, userId) = try await SokoviaConfig.provisionUserBucket(email: email, displayName: name)
                AppState.shared.config.bucketName = bucket
                AppState.shared.config.userId = userId
                AppState.shared.config.save()
                await AppState.shared.startDrive()
                StatusItemManager.shared.updateMenu()

                // Notify user subtly
                let notification = NSUserNotification()
                notification.title = "Sokovia Connected"
                notification.informativeText = "Connected as \(email)"
                NSUserNotificationCenter.default.deliver(notification)
            } catch {
                print("Failed to setup bucket from deep link: \(error)")
                AppState.shared.config.save()
                StatusItemManager.shared.updateMenu()
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

