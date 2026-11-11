import AppKit

@MainActor
public final class StatusItemManager: NSObject, NSMenuDelegate {
    public static let shared = StatusItemManager()

    private var statusItem: NSStatusItem?
    private let menu = NSMenu()

    public func setup() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "externaldrive", accessibilityDescription: "Sokovia")
            button.imagePosition = .imageOnly
        }
        item.menu = menu
        menu.delegate = self
        self.statusItem = item
        updateMenu()
    }

    public func menuWillOpen(_ menu: NSMenu) {
        AppState.shared.config = SokoviaConfig.load()
        updateMenu()
    }

    public func updateMenu() {
        menu.removeAllItems()
        let state = AppState.shared
        let email = AppState.shared.config.userEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        let isLoggedIn = !email.isEmpty

        if !isLoggedIn {
            // When NO account is linked, show only Log In and Quit
            let loginItem = NSMenuItem(
                title: "Log In...",
                action: #selector(loginClicked),
                keyEquivalent: ""
            )
            loginItem.image = NSImage(systemSymbolName: "arrow.right.circle", accessibilityDescription: "Log In")
            loginItem.target = self
            menu.addItem(loginItem)

            menu.addItem(NSMenuItem.separator())

            let quitItem = NSMenuItem(
                title: "Quit Sokovia",
                action: #selector(quitClicked),
                keyEquivalent: "q"
            )
            quitItem.image = NSImage(systemSymbolName: "power", accessibilityDescription: "Quit")
            quitItem.target = self
            menu.addItem(quitItem)

            // Status Item Icon in Top Bar: unlinked / offline state
            if let button = self.statusItem?.button {
                button.image = NSImage(systemSymbolName: "externaldrive.badge.xmark", accessibilityDescription: "Sokovia: Not Logged In")
            }
            return
        }

        // When logged in, show full options:
        // 1. Search Sokovia (^⌥O)
        let searchItem = NSMenuItem(
            title: "Search Sokovia",
            action: #selector(searchClicked),
            keyEquivalent: "o"
        )
        searchItem.keyEquivalentModifierMask = [.control, .option]
        searchItem.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: "Search")
        searchItem.target = self
        menu.addItem(searchItem)

        // 2. Open in Finder (⌘O)
        let finderItem = NSMenuItem(
            title: "Open in Finder",
            action: #selector(openFinderClicked),
            keyEquivalent: "o"
        )
        finderItem.keyEquivalentModifierMask = [.command]
        finderItem.image = NSImage(systemSymbolName: "folder", accessibilityDescription: "Open in Finder")
        finderItem.target = self
        finderItem.isEnabled = true
        menu.addItem(finderItem)

        menu.addItem(NSMenuItem.separator())

        // 3. Your Account (↗)
        let accountItem = NSMenuItem(
            title: "Your Account",
            action: #selector(accountClicked),
            keyEquivalent: ""
        )
        accountItem.image = NSImage(systemSymbolName: "person.crop.circle", accessibilityDescription: "Your Account")
        accountItem.target = self
        menu.addItem(accountItem)

        // 4. Send Feedback
        let feedbackItem = NSMenuItem(
            title: "Send Feedback",
            action: #selector(feedbackClicked),
            keyEquivalent: ""
        )
        feedbackItem.image = NSImage(systemSymbolName: "bubble.left.and.bubble.right", accessibilityDescription: "Feedback")
        feedbackItem.target = self
        menu.addItem(feedbackItem)

        menu.addItem(NSMenuItem.separator())

        // 5. Settings... (⌘,)
        let settingsItem = NSMenuItem(
            title: "Settings...",
            action: #selector(settingsClicked),
            keyEquivalent: ","
        )
        settingsItem.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "Settings")
        settingsItem.target = self
        menu.addItem(settingsItem)

        // 6. Quit Sokovia (⌘Q)
        let quitItem = NSMenuItem(
            title: "Quit Sokovia",
            action: #selector(quitClicked),
            keyEquivalent: "q"
        )
        quitItem.image = NSImage(systemSymbolName: "power", accessibilityDescription: "Quit")
        quitItem.target = self
        menu.addItem(quitItem)

        // Status Item Icon in Top Bar
        if let button = self.statusItem?.button {
            let symbolName = state.isMounted ? "externaldrive.badge.checkmark" : (state.isConnecting ? "arrow.triangle.2.circlepath.circle" : "externaldrive")
            button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Sokovia")
        }
    }

    @objc private func searchClicked() {
        Task {
            if !AppState.shared.isMounted {
                await AppState.shared.startDrive()
                await MainActor.run { self.updateMenu() }
            }
            AppState.shared.openInFinder()
        }
    }

    @objc private func openFinderClicked() {
        Task {
            if !AppState.shared.isMounted {
                await AppState.shared.startDrive()
                await MainActor.run { self.updateMenu() }
            }
            AppState.shared.openInFinder()
        }
    }

    @objc private func accountClicked() {
        let email = AppState.shared.config.userEmail
        let encodedEmail = email.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let targetURL = "https://26u7vqfh.insforge.site/dashboard?email=\(encodedEmail)"
        if let url = URL(string: targetURL) {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func loginClicked() {
        if let url = URL(string: "https://26u7vqfh.insforge.site/") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func feedbackClicked() {
        if let url = URL(string: "mailto:support@sokovia.dev?subject=Sokovia%20Feedback") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func settingsClicked() {
        SettingsWindowController.shared.show()
    }

    @objc private func quitClicked() {
        Task {
            await AppState.shared.stopDrive()
            NSApp.terminate(nil)
        }
    }
}
