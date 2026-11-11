import AppKit

@MainActor
public final class AppearanceManager {
    public static let shared = AppearanceManager()

    public static let key = "sokovia_theme_mode" // "System", "Light", "Dark"

    public var currentMode: String {
        return UserDefaults.standard.string(forKey: AppearanceManager.key) ?? "System"
    }

    public func setMode(_ mode: String) {
        UserDefaults.standard.set(mode, forKey: AppearanceManager.key)
        applyTheme()
    }

    public func applyTheme() {
        let mode = currentMode
        let appearance: NSAppearance?
        switch mode {
        case "Light":
            appearance = NSAppearance(named: .aqua)
        case "Dark":
            appearance = NSAppearance(named: .darkAqua)
        default: // "System"
            appearance = nil
        }

        NSApp.appearance = appearance
        SettingsWindowController.shared.applyTheme(appearance)
        DevicePairingWindowController.shared.applyTheme(appearance)
    }
}
