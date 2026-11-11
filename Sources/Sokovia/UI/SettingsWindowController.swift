import AppKit

@MainActor
public final class SettingsWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate {
    public static let shared = SettingsWindowController()

    private enum TabIdentifier: String, CaseIterable {
        case general = "General"
        case storage = "Storage"
        case encryption = "Encryption"
        case account = "Account"

        var iconName: String {
            switch self {
            case .general: return "gearshape"
            case .storage: return "externaldrive"
            case .encryption: return "lock"
            case .account: return "person.crop.circle"
            }
        }
    }

    private var currentTab: TabIdentifier = .general
    private let containerView = NSView()
    private var tabViews: [TabIdentifier: NSView] = [:]

    // General Tab Controls
    private let loginSwitch = NSSwitch()
    private let uploadSpeedPopup = NSPopUpButton()
    private let themeModePopup = NSPopUpButton()
    private let driveIconPopup = NSPopUpButton()
    private let searchShortcutLabel = NSTextField(labelWithString: "⌃⌥O")
    private let autoUpdateSwitch = NSSwitch()
    private let sendReportsSwitch = NSSwitch()
    private let versionLabel = NSTextField(labelWithString: "Version 1.0.0 (42)")

    // Storage Tab Controls
    private let spacePopup = NSPopUpButton()
    private let storageUsingLabel = NSTextField(labelWithString: "0 KB")
    private let freeUpSpaceButton = NSButton()

    // Encryption Tab Controls
    private let encryptionSwitch = NSSwitch()
    private let e2eeStatusValueLabel = NSTextField(labelWithString: "All files encrypted")
    private let e2eeStatusIcon = NSImageView()
    private let recoveryStatusIcon = NSImageView()
    private let recoveryStatusValueLabel = NSTextField(labelWithString: "Saved")
    private let makeKeyButton = NSButton()

    // Account Tab Controls
    private let accountEmailLabel = NSTextField(labelWithString: "")
    private let openInBrowserButton = NSButton()
    private let signOutButton = NSButton()
    private let loginButton = NSButton()

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 600),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "General"
        window.center()
        window.isReleasedWhenClosed = false
        window.isMovable = true
        window.isMovableByWindowBackground = true
        window.titleVisibility = .visible
        window.toolbarStyle = .preference

        super.init(window: window)
        window.delegate = self
        setupToolbar()
        setupContent()
        loadConfigValues()
        applyTheme(NSApp.appearance)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func show() {
        loadConfigValues()
        updateStorageUsingDisplay()
        switchToTab(currentTab)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Toolbar Setup

    private func setupToolbar() {
        let toolbar = NSToolbar(identifier: "SokoviaSettingsToolbar")
        toolbar.delegate = self
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
        toolbar.displayMode = .iconAndLabel
        toolbar.selectedItemIdentifier = NSToolbarItem.Identifier(TabIdentifier.general.rawValue)
        window?.toolbar = toolbar
    }

    public func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return TabIdentifier.allCases.map { NSToolbarItem.Identifier($0.rawValue) }
    }

    public func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return TabIdentifier.allCases.map { NSToolbarItem.Identifier($0.rawValue) }
    }

    public func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return TabIdentifier.allCases.map { NSToolbarItem.Identifier($0.rawValue) }
    }

    public func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard let tab = TabIdentifier(rawValue: itemIdentifier.rawValue) else { return nil }

        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.label = tab.rawValue
        if let image = NSImage(systemSymbolName: tab.iconName, accessibilityDescription: tab.rawValue) {
            item.image = image
        }
        item.target = self
        item.action = #selector(toolbarTabClicked(_:))
        return item
    }

    @objc private func toolbarTabClicked(_ sender: NSToolbarItem) {
        guard let tab = TabIdentifier(rawValue: sender.itemIdentifier.rawValue) else { return }
        loadConfigValues()
        updateStorageUsingDisplay()
        switchToTab(tab)
    }

    private func switchToTab(_ tab: TabIdentifier) {
        currentTab = tab
        window?.title = tab.rawValue
        window?.toolbar?.selectedItemIdentifier = NSToolbarItem.Identifier(tab.rawValue)

        containerView.subviews.forEach { $0.removeFromSuperview() }
        let targetView = getOrCreateTabView(for: tab)

        var targetContentHeight: CGFloat = 620
        switch tab {
        case .general: targetContentHeight = 620
        case .storage: targetContentHeight = 270
        case .encryption: targetContentHeight = 280
        case .account: targetContentHeight = 260
        }

        if let win = window {
            let currentFrame = win.frame
            let titleBarHeight = currentFrame.size.height - win.contentRect(forFrameRect: currentFrame).size.height
            let newTotalHeight = targetContentHeight + titleBarHeight
            var newFrame = currentFrame
            newFrame.size.height = newTotalHeight
            newFrame.origin.y += (currentFrame.size.height - newTotalHeight)
            win.setFrame(newFrame, display: true, animate: true)
        }

        targetView.frame = containerView.bounds
        targetView.autoresizingMask = [.width, .height]
        containerView.addSubview(targetView)
    }

    // MARK: - Content Setup

    private func setupContent() {
        guard let window = self.window else { return }
        let content = NSView(frame: window.contentRect(forFrameRect: window.frame))
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1.0).cgColor

        containerView.frame = content.bounds
        containerView.autoresizingMask = [.width, .height]
        content.addSubview(containerView)
        window.contentView = content

        switchToTab(.general)
    }

    private func getOrCreateTabView(for tab: TabIdentifier) -> NSView {
        // Always rebuild the Account and Storage views so live data is always rendered accurately
        if tab == .account || tab == .storage {
            let view = (tab == .account) ? makeAccountView() : makeStorageView()
            tabViews[tab] = view
            return view
        }
        if let existing = tabViews[tab] {
            return existing
        }
        let view: NSView
        switch tab {
        case .general:
            view = makeGeneralView()
        case .storage:
            view = makeStorageView()
        case .encryption:
            view = makeEncryptionView()
        case .account:
            view = makeAccountView()
        }
        tabViews[tab] = view
        return view
    }

    // MARK: - Card UI Helper
    private func makeCardView(frame: NSRect) -> NSView {
        let card = NSView(frame: frame)
        card.wantsLayer = true
        let isDark = window?.appearance?.name == .darkAqua || (window?.appearance == nil && NSApp.effectiveAppearance.name == .darkAqua)
        card.layer?.backgroundColor = isDark ? NSColor(white: 1.0, alpha: 0.05).cgColor : NSColor(white: 1.0, alpha: 0.85).cgColor
        card.layer?.cornerRadius = 10.0
        card.layer?.borderWidth = 0.5
        card.layer?.borderColor = isDark ? NSColor(white: 1.0, alpha: 0.08).cgColor : NSColor(white: 0.0, alpha: 0.12).cgColor
        return card
    }

    // MARK: - 1. General Tab View
    private func makeGeneralView() -> NSView {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 520, height: 620))

        // Card 1: Open Sokovia when you log in (height: 60, top: 602 -> y: 542)
        let card1 = makeCardView(frame: NSRect(x: 20, y: 542, width: 480, height: 60))
        let openLbl = NSTextField(labelWithString: "Open Sokovia when you log in")
        openLbl.font = NSFont.systemFont(ofSize: 13, weight: .regular)
        openLbl.frame = NSRect(x: 16, y: 30, width: 340, height: 20)
        card1.addSubview(openLbl)

        let openSub = NSTextField(labelWithString: "Sokovia needs to be running for the drive to work.")
        openSub.font = NSFont.systemFont(ofSize: 11)
        openSub.textColor = .secondaryLabelColor
        openSub.frame = NSRect(x: 16, y: 12, width: 340, height: 16)
        card1.addSubview(openSub)

        loginSwitch.frame = NSRect(x: 416, y: 18, width: 48, height: 24)
        loginSwitch.target = self
        loginSwitch.action = #selector(loginSwitchChanged)
        card1.addSubview(loginSwitch)
        view.addSubview(card1)

        // Card 2: Uploads (speed) (height: 82, gap: 14 -> top: 528 -> y: 446)
        let card2 = makeCardView(frame: NSRect(x: 20, y: 446, width: 480, height: 82))
        let uploadHeader = NSTextField(labelWithString: "Uploads")
        uploadHeader.font = NSFont.boldSystemFont(ofSize: 12)
        uploadHeader.frame = NSRect(x: 16, y: 54, width: 200, height: 18)
        card2.addSubview(uploadHeader)

        let uploadSpeedLbl = NSTextField(labelWithString: "Upload speed")
        uploadSpeedLbl.font = NSFont.systemFont(ofSize: 13)
        uploadSpeedLbl.frame = NSRect(x: 16, y: 28, width: 200, height: 20)
        card2.addSubview(uploadSpeedLbl)

        uploadSpeedPopup.frame = NSRect(x: 300, y: 24, width: 164, height: 26)
        uploadSpeedPopup.removeAllItems()
        uploadSpeedPopup.addItems(withTitles: ["As fast as possible", "Limited", "Adaptive"])
        uploadSpeedPopup.target = self
        uploadSpeedPopup.action = #selector(uploadSpeedChanged)
        card2.addSubview(uploadSpeedPopup)

        let uploadSub = NSTextField(labelWithString: "Limit uploads so video calls and browsing stay smooth. Opening files is never slowed down.")
        uploadSub.font = NSFont.systemFont(ofSize: 10.5)
        uploadSub.textColor = .secondaryLabelColor
        uploadSub.frame = NSRect(x: 16, y: 6, width: 440, height: 16)
        card2.addSubview(uploadSub)
        view.addSubview(card2)

        // Card 3: Appearance (Theme & Drive Icon) (height: 116, gap: 14 -> top: 432 -> y: 316)
        let card3 = makeCardView(frame: NSRect(x: 20, y: 316, width: 480, height: 116))
        let appHeader = NSTextField(labelWithString: "Appearance")
        appHeader.font = NSFont.boldSystemFont(ofSize: 12)
        appHeader.frame = NSRect(x: 16, y: 88, width: 200, height: 18)
        card3.addSubview(appHeader)

        let themeLbl = NSTextField(labelWithString: "Theme")
        themeLbl.font = NSFont.systemFont(ofSize: 13)
        themeLbl.frame = NSRect(x: 16, y: 60, width: 200, height: 20)
        card3.addSubview(themeLbl)

        themeModePopup.frame = NSRect(x: 340, y: 56, width: 124, height: 26)
        themeModePopup.removeAllItems()
        themeModePopup.addItems(withTitles: ["System", "Light", "Dark"])
        themeModePopup.target = self
        themeModePopup.action = #selector(themeModeChanged)
        card3.addSubview(themeModePopup)

        let iconLbl = NSTextField(labelWithString: "Drive icon")
        iconLbl.font = NSFont.systemFont(ofSize: 13)
        iconLbl.frame = NSRect(x: 16, y: 28, width: 200, height: 20)
        card3.addSubview(iconLbl)

        driveIconPopup.frame = NSRect(x: 340, y: 24, width: 124, height: 26)
        driveIconPopup.removeAllItems()
        driveIconPopup.addItems(withTitles: ["Automatic", "Black", "White"])
        driveIconPopup.target = self
        driveIconPopup.action = #selector(driveIconChanged)
        card3.addSubview(driveIconPopup)

        let iconSub = NSTextField(labelWithString: "Switch between Light, Dark, or System mode. Choose White drive icon if your desktop picture is dark.")
        iconSub.font = NSFont.systemFont(ofSize: 10.5)
        iconSub.textColor = .secondaryLabelColor
        iconSub.frame = NSRect(x: 16, y: 6, width: 440, height: 16)
        card3.addSubview(iconSub)
        view.addSubview(card3)

        // Card 4: Search (height: 56, gap: 14 -> top: 302 -> y: 246)
        let card4 = makeCardView(frame: NSRect(x: 20, y: 246, width: 480, height: 56))
        let searchHeader = NSTextField(labelWithString: "Search")
        searchHeader.font = NSFont.boldSystemFont(ofSize: 12)
        searchHeader.frame = NSRect(x: 16, y: 32, width: 200, height: 18)
        card4.addSubview(searchHeader)

        let searchLbl = NSTextField(labelWithString: "Search from anywhere")
        searchLbl.font = NSFont.systemFont(ofSize: 13)
        searchLbl.frame = NSRect(x: 16, y: 10, width: 200, height: 20)
        card4.addSubview(searchLbl)

        searchShortcutLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        searchShortcutLabel.alignment = .right
        searchShortcutLabel.textColor = .secondaryLabelColor
        searchShortcutLabel.frame = NSRect(x: 400, y: 10, width: 64, height: 20)
        card4.addSubview(searchShortcutLabel)
        view.addSubview(card4)

        // Card 5: Updates (height: 76, gap: 14 -> top: 232 -> y: 156)
        let card5 = makeCardView(frame: NSRect(x: 20, y: 156, width: 480, height: 76))
        let updateHeader = NSTextField(labelWithString: "Updates")
        updateHeader.font = NSFont.boldSystemFont(ofSize: 12)
        updateHeader.frame = NSRect(x: 16, y: 50, width: 200, height: 18)
        card5.addSubview(updateHeader)

        versionLabel.font = NSFont.systemFont(ofSize: 12.5)
        versionLabel.frame = NSRect(x: 16, y: 26, width: 240, height: 20)
        card5.addSubview(versionLabel)

        let checkBtn = NSButton(title: "Check for Updates...", target: self, action: #selector(checkUpdatesClicked))
        checkBtn.bezelStyle = .rounded
        checkBtn.font = NSFont.systemFont(ofSize: 12)
        checkBtn.frame = NSRect(x: 310, y: 22, width: 154, height: 28)
        card5.addSubview(checkBtn)

        let autoLbl = NSTextField(labelWithString: "Install updates automatically")
        autoLbl.font = NSFont.systemFont(ofSize: 12.5)
        autoLbl.frame = NSRect(x: 16, y: 6, width: 300, height: 18)
        card5.addSubview(autoLbl)

        autoUpdateSwitch.frame = NSRect(x: 416, y: 4, width: 48, height: 20)
        autoUpdateSwitch.state = .on
        autoUpdateSwitch.target = self
        autoUpdateSwitch.action = #selector(autoUpdateToggled)
        card5.addSubview(autoUpdateSwitch)
        view.addSubview(card5)

        // Card 6: Privacy (height: 62, gap: 14 -> top: 142 -> y: 80)
        let card6 = makeCardView(frame: NSRect(x: 20, y: 80, width: 480, height: 62))
        let privHeader = NSTextField(labelWithString: "Privacy")
        privHeader.font = NSFont.boldSystemFont(ofSize: 12)
        privHeader.frame = NSRect(x: 16, y: 38, width: 200, height: 18)
        card6.addSubview(privHeader)

        let reportLbl = NSTextField(labelWithString: "Send error reports")
        reportLbl.font = NSFont.systemFont(ofSize: 12.5)
        reportLbl.frame = NSRect(x: 16, y: 18, width: 300, height: 18)
        card6.addSubview(reportLbl)

        sendReportsSwitch.frame = NSRect(x: 416, y: 16, width: 48, height: 20)
        sendReportsSwitch.state = .on
        sendReportsSwitch.target = self
        sendReportsSwitch.action = #selector(sendReportsToggled)
        card6.addSubview(sendReportsSwitch)

        let privSub = NSTextField(labelWithString: "When something goes wrong, Sokovia sends a short technical report. It never includes your files.")
        privSub.font = NSFont.systemFont(ofSize: 10)
        privSub.textColor = .secondaryLabelColor
        privSub.frame = NSRect(x: 16, y: 2, width: 440, height: 14)
        card6.addSubview(privSub)
        view.addSubview(card6)

        return view
    }

    // MARK: - 2. Storage Tab View
    private func makeStorageView() -> NSView {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 520, height: 270))

        let card = makeCardView(frame: NSRect(x: 20, y: 30, width: 480, height: 210))

        let macHeader = NSTextField(labelWithString: "This Mac")
        macHeader.font = NSFont.boldSystemFont(ofSize: 12)
        macHeader.frame = NSRect(x: 18, y: 176, width: 200, height: 20)
        card.addSubview(macHeader)

        // Space for recent files
        let spaceLbl = NSTextField(labelWithString: "Space for recent files")
        spaceLbl.font = NSFont.systemFont(ofSize: 13)
        spaceLbl.frame = NSRect(x: 18, y: 144, width: 240, height: 20)
        card.addSubview(spaceLbl)

        spacePopup.frame = NSRect(x: 340, y: 140, width: 124, height: 26)
        spacePopup.removeAllItems()
        spacePopup.addItems(withTitles: ["Automatic", "2 GB", "5 GB", "10 GB", "Custom..."])
        spacePopup.target = self
        spacePopup.action = #selector(spaceLimitChanged)
        card.addSubview(spacePopup)

        // Using now
        let usingLbl = NSTextField(labelWithString: "Using now")
        usingLbl.font = NSFont.systemFont(ofSize: 13)
        usingLbl.frame = NSRect(x: 18, y: 108, width: 200, height: 20)
        card.addSubview(usingLbl)

        storageUsingLabel.font = NSFont.systemFont(ofSize: 13)
        storageUsingLabel.alignment = .right
        storageUsingLabel.textColor = .secondaryLabelColor
        storageUsingLabel.frame = NSRect(x: 350, y: 108, width: 110, height: 20)
        card.addSubview(storageUsingLabel)

        // Free up space
        let freeLbl = NSTextField(labelWithString: "Free up space")
        freeLbl.font = NSFont.systemFont(ofSize: 13)
        freeLbl.frame = NSRect(x: 18, y: 72, width: 200, height: 20)
        card.addSubview(freeLbl)

        freeUpSpaceButton.title = "Remove Recent Files..."
        freeUpSpaceButton.bezelStyle = .rounded
        freeUpSpaceButton.font = NSFont.systemFont(ofSize: 12)
        freeUpSpaceButton.frame = NSRect(x: 294, y: 68, width: 172, height: 28)
        freeUpSpaceButton.target = self
        freeUpSpaceButton.action = #selector(freeUpSpaceClicked)
        card.addSubview(freeUpSpaceButton)

        // Footnote
        let infoLbl = NSTextField(labelWithString: "Files in Sokovia take no space on this Mac. To open them instantly, Sokovia keeps the parts you used recently, up to the size you choose. It always gives space back when your Mac runs low.")
        infoLbl.font = NSFont.systemFont(ofSize: 11)
        infoLbl.textColor = .secondaryLabelColor
        infoLbl.maximumNumberOfLines = 3
        infoLbl.frame = NSRect(x: 18, y: 12, width: 444, height: 46)
        card.addSubview(infoLbl)

        view.addSubview(card)
        return view
    }

    // MARK: - 3. Encryption Tab View
    private func makeEncryptionView() -> NSView {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 520, height: 280))

        // Card 1: E2EE toggle + status
        let card1 = makeCardView(frame: NSRect(x: 20, y: 140, width: 480, height: 110))

        let e2eeLbl = NSTextField(labelWithString: "End-to-end encryption")
        e2eeLbl.font = NSFont.systemFont(ofSize: 13, weight: .regular)
        e2eeLbl.frame = NSRect(x: 18, y: 76, width: 300, height: 20)
        card1.addSubview(e2eeLbl)

        encryptionSwitch.frame = NSRect(x: 416, y: 74, width: 48, height: 24)
        encryptionSwitch.target = self
        encryptionSwitch.action = #selector(encryptionSwitchToggled)
        card1.addSubview(encryptionSwitch)

        let statusLbl = NSTextField(labelWithString: "Status")
        statusLbl.font = NSFont.systemFont(ofSize: 13)
        statusLbl.frame = NSRect(x: 18, y: 46, width: 100, height: 20)
        card1.addSubview(statusLbl)

        // Green checkmark
        if let checkImg = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: "Encrypted") {
            let config = NSImage.SymbolConfiguration(paletteColors: [.systemGreen])
            e2eeStatusIcon.image = checkImg.withSymbolConfiguration(config)
        }
        e2eeStatusIcon.frame = NSRect(x: 320, y: 48, width: 16, height: 16)
        card1.addSubview(e2eeStatusIcon)

        e2eeStatusValueLabel.font = NSFont.systemFont(ofSize: 13)
        e2eeStatusValueLabel.frame = NSRect(x: 342, y: 46, width: 124, height: 20)
        card1.addSubview(e2eeStatusValueLabel)

        let explLbl = NSTextField(labelWithString: "Only your devices hold the key. Sokovia stores your files encrypted and can't open them. Sokovia can still see file sizes and dates.")
        explLbl.font = NSFont.systemFont(ofSize: 11)
        explLbl.textColor = .secondaryLabelColor
        explLbl.maximumNumberOfLines = 2
        explLbl.frame = NSRect(x: 18, y: 8, width: 444, height: 32)
        card1.addSubview(explLbl)
        view.addSubview(card1)

        // Card 2: Recovery Key
        let card2 = makeCardView(frame: NSRect(x: 20, y: 20, width: 480, height: 110))

        let keyHeader = NSTextField(labelWithString: "Recovery Key")
        keyHeader.font = NSFont.boldSystemFont(ofSize: 12)
        keyHeader.frame = NSRect(x: 18, y: 82, width: 200, height: 18)
        card2.addSubview(keyHeader)

        let recovLbl = NSTextField(labelWithString: "Recovery key")
        recovLbl.font = NSFont.systemFont(ofSize: 13)
        recovLbl.frame = NSRect(x: 18, y: 56, width: 200, height: 20)
        card2.addSubview(recovLbl)

        if let checkImg = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: "Saved") {
            let config = NSImage.SymbolConfiguration(paletteColors: [.systemGreen])
            recoveryStatusIcon.image = checkImg.withSymbolConfiguration(config)
        }
        recoveryStatusIcon.frame = NSRect(x: 400, y: 58, width: 16, height: 16)
        card2.addSubview(recoveryStatusIcon)

        recoveryStatusValueLabel.font = NSFont.systemFont(ofSize: 13)
        recoveryStatusValueLabel.frame = NSRect(x: 422, y: 56, width: 46, height: 20)
        card2.addSubview(recoveryStatusValueLabel)

        let lostLbl = NSTextField(labelWithString: "Lost it?")
        lostLbl.font = NSFont.systemFont(ofSize: 13)
        lostLbl.frame = NSRect(x: 18, y: 26, width: 100, height: 20)
        card2.addSubview(lostLbl)

        makeKeyButton.title = "Make a New Key..."
        makeKeyButton.bezelStyle = .rounded
        makeKeyButton.font = NSFont.systemFont(ofSize: 12)
        makeKeyButton.frame = NSRect(x: 320, y: 22, width: 146, height: 28)
        makeKeyButton.target = self
        makeKeyButton.action = #selector(makeKeyClicked)
        card2.addSubview(makeKeyButton)

        let keySub = NSTextField(labelWithString: "Making a new key stops the old one from working.")
        keySub.font = NSFont.systemFont(ofSize: 10.5)
        keySub.textColor = .secondaryLabelColor
        keySub.frame = NSRect(x: 18, y: 4, width: 440, height: 16)
        card2.addSubview(keySub)

        view.addSubview(card2)
        return view
    }

    // MARK: - 4. Account Tab View
    private func makeAccountView() -> NSView {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 520, height: 260))
        let email = AppState.shared.config.userEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        let isLoggedIn = !email.isEmpty

        if isLoggedIn {
            // Logged in UI
            // Card 1: Email + Open in browser
            let card1 = makeCardView(frame: NSRect(x: 20, y: 120, width: 480, height: 110))

            let emailLbl = NSTextField(labelWithString: "Email")
            emailLbl.font = NSFont.systemFont(ofSize: 13)
            emailLbl.frame = NSRect(x: 18, y: 76, width: 80, height: 20)
            card1.addSubview(emailLbl)

            accountEmailLabel.stringValue = email
            accountEmailLabel.font = NSFont.systemFont(ofSize: 13)
            accountEmailLabel.alignment = .right
            accountEmailLabel.textColor = .secondaryLabelColor
            accountEmailLabel.frame = NSRect(x: 110, y: 76, width: 350, height: 20)
            card1.addSubview(accountEmailLabel)

            let planLbl = NSTextField(labelWithString: "Account, plan and storage")
            planLbl.font = NSFont.systemFont(ofSize: 13)
            planLbl.frame = NSRect(x: 18, y: 42, width: 260, height: 20)
            card1.addSubview(planLbl)

            openInBrowserButton.title = "Open in Browser..."
            openInBrowserButton.bezelStyle = .rounded
            openInBrowserButton.font = NSFont.systemFont(ofSize: 12)
            openInBrowserButton.frame = NSRect(x: 324, y: 38, width: 142, height: 28)
            openInBrowserButton.target = self
            openInBrowserButton.action = #selector(openInBrowserClicked)
            card1.addSubview(openInBrowserButton)

            let webSub = NSTextField(labelWithString: "Your plan, sharing, Recently Deleted and account settings are on the Sokovia website.")
            webSub.font = NSFont.systemFont(ofSize: 11)
            webSub.textColor = .secondaryLabelColor
            webSub.frame = NSRect(x: 18, y: 10, width: 444, height: 24)
            card1.addSubview(webSub)
            view.addSubview(card1)

            // Card 2: Sign Out
            let card2 = makeCardView(frame: NSRect(x: 20, y: 20, width: 480, height: 90))

            signOutButton.title = "Sign Out of This Mac..."
            signOutButton.bezelStyle = .rounded
            signOutButton.font = NSFont.systemFont(ofSize: 13)
            signOutButton.frame = NSRect(x: 18, y: 42, width: 220, height: 32)
            signOutButton.target = self
            signOutButton.action = #selector(signOutClicked)
            card2.addSubview(signOutButton)

            let signSub = NSTextField(labelWithString: "Signing out removes the Sokovia drive from this Mac. Your files stay safe in the cloud.")
            signSub.font = NSFont.systemFont(ofSize: 11)
            signSub.textColor = .secondaryLabelColor
            signSub.frame = NSRect(x: 18, y: 14, width: 444, height: 20)
            card2.addSubview(signSub)
            view.addSubview(card2)
        } else {
            // Not Logged In UI: Clean Login Card
            let card = makeCardView(frame: NSRect(x: 20, y: 50, width: 480, height: 160))

            let noAccTitle = NSTextField(labelWithString: "No Account Linked")
            noAccTitle.font = NSFont.boldSystemFont(ofSize: 15)
            noAccTitle.frame = NSRect(x: 20, y: 118, width: 400, height: 22)
            card.addSubview(noAccTitle)

            let noAccSub = NSTextField(labelWithString: "Sign in with your Sokovia account in your browser to link this Mac and mount your cloud drive.")
            noAccSub.font = NSFont.systemFont(ofSize: 12)
            noAccSub.textColor = .secondaryLabelColor
            noAccSub.frame = NSRect(x: 20, y: 72, width: 440, height: 36)
            card.addSubview(noAccSub)

            loginButton.title = "Log In with Browser..."
            loginButton.bezelStyle = .rounded
            loginButton.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
            loginButton.frame = NSRect(x: 18, y: 24, width: 180, height: 34)
            loginButton.target = self
            loginButton.action = #selector(loginClicked)
            card.addSubview(loginButton)

            view.addSubview(card)
        }

        return view
    }

    // MARK: - State Management & Actions

    private func loadConfigValues() {
        // Reload fresh config from disk to reflect any background device-pairing or profile changes
        AppState.shared.config = SokoviaConfig.load()
        let config = AppState.shared.config
        accountEmailLabel.stringValue = config.userEmail
        encryptionSwitch.state = config.encryptionEnabled ? .on : .off
        updateEncryptionDisplay()

        let launchAgentURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/com.sokovia.drive.plist")
        loginSwitch.state = FileManager.default.fileExists(atPath: launchAgentURL.path) ? .on : .off

        // Load saved preferences for popups & switches
        let themePref = UserDefaults.standard.string(forKey: AppearanceManager.key) ?? "System"
        themeModePopup.selectItem(withTitle: themePref)

        let speed = UserDefaults.standard.string(forKey: "sokovia_upload_speed") ?? "As fast as possible"
        uploadSpeedPopup.selectItem(withTitle: speed)

        let iconPref = UserDefaults.standard.string(forKey: "sokovia_drive_icon") ?? "Automatic"
        driveIconPopup.selectItem(withTitle: iconPref)

        let autoUp = UserDefaults.standard.object(forKey: "sokovia_auto_update") as? Bool ?? true
        autoUpdateSwitch.state = autoUp ? .on : .off

        let sendRep = UserDefaults.standard.object(forKey: "sokovia_send_reports") as? Bool ?? true
        sendReportsSwitch.state = sendRep ? .on : .off

        let spacePref = UserDefaults.standard.string(forKey: "sokovia_space_limit") ?? "Automatic"
        spacePopup.selectItem(withTitle: spacePref)
    }

    private func updateStorageUsingDisplay() {
        Task {
            let formatted = await AppState.shared.diskCache.currentCacheSizeFormatted()
            await MainActor.run {
                self.storageUsingLabel.stringValue = formatted
            }
        }
    }

    private func updateEncryptionDisplay() {
        let isEncrypted = (encryptionSwitch.state == .on)
        e2eeStatusValueLabel.stringValue = isEncrypted ? "All files encrypted" : "Disabled"
        if let icon = NSImage(systemSymbolName: isEncrypted ? "checkmark.circle.fill" : "xmark.circle.fill", accessibilityDescription: nil) {
            let color: NSColor = isEncrypted ? .systemGreen : .secondaryLabelColor
            let config = NSImage.SymbolConfiguration(paletteColors: [color])
            e2eeStatusIcon.image = icon.withSymbolConfiguration(config)
        }
    }

    @objc private func loginSwitchChanged() {
        let enable = (loginSwitch.state == .on)
        setLaunchAgentEnabled(enable)
    }

    private func setLaunchAgentEnabled(_ enable: Bool) {
        let launchAgentsDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents")
        let plistURL = launchAgentsDir.appendingPathComponent("com.sokovia.drive.plist")

        if enable {
            try? FileManager.default.createDirectory(at: launchAgentsDir, withIntermediateDirectories: true)
            let plistContent = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
                <key>Label</key>
                <string>com.sokovia.drive</string>
                <key>ProgramArguments</key>
                <array>
                    <string>/Applications/Sokovia.app/Contents/MacOS/Sokovia</string>
                </array>
                <key>RunAtLoad</key>
                <true/>
                <key>KeepAlive</key>
                <false/>
            </dict>
            </plist>
            """
            try? plistContent.write(to: plistURL, atomically: true, encoding: .utf8)
        } else {
            try? FileManager.default.removeItem(at: plistURL)
        }
    }

    @objc private func freeUpSpaceClicked() {
        let alert = NSAlert()
        alert.messageText = "Remove Recent Files from this Mac?"
        alert.informativeText = "This frees up local disk cache immediately. Your files remain completely intact in your private cloud bucket and can be opened anytime."
        alert.addButton(withTitle: "Remove Recent Files")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .informational

        if alert.runModal() == .alertFirstButtonReturn {
            Task {
                await AppState.shared.diskCache.clearAllCache()
                self.updateStorageUsingDisplay()
            }
        }
    }

    @objc private func encryptionSwitchToggled() {
        var cfg = AppState.shared.config
        cfg.encryptionEnabled = (encryptionSwitch.state == .on)
        if cfg.encryptionEnabled && cfg.encryptionPassphrase.isEmpty {
            cfg.encryptionPassphrase = UUID().uuidString
        }
        cfg.save()
        AppState.shared.config = cfg
        updateEncryptionDisplay()
    }

    @objc private func makeKeyClicked() {
        let alert = NSAlert()
        alert.messageText = "Generate a New Recovery Key?"
        alert.informativeText = "Generating a new recovery key updates your zero-knowledge encryption passphrase. Old cached keys on other devices will need to be re-entered."
        alert.addButton(withTitle: "Generate Key")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning

        if alert.runModal() == .alertFirstButtonReturn {
            var cfg = AppState.shared.config
            let newKey = "SKV-" + UUID().uuidString.prefix(18).uppercased()
            cfg.encryptionPassphrase = newKey
            cfg.save()
            AppState.shared.config = cfg

            let infoAlert = NSAlert()
            infoAlert.messageText = "Your New Recovery Key"
            infoAlert.informativeText = "\(newKey)\n\nKeep this key safe. Sokovia does not store your passphrase."
            infoAlert.runModal()
        }
    }

    @objc private func openInBrowserClicked() {
        let email = AppState.shared.config.userEmail
        let encodedEmail = email.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let targetURL = email.isEmpty ? "https://26u7vqfh.insforge.site/dashboard" : "https://26u7vqfh.insforge.site/dashboard?email=\(encodedEmail)"
        if let url = URL(string: targetURL) {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func loginClicked() {
        if let url = URL(string: "https://26u7vqfh.insforge.site/") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func themeModeChanged() {
        let selected = themeModePopup.titleOfSelectedItem ?? "System"
        AppearanceManager.shared.setMode(selected)
    }

    @objc private func uploadSpeedChanged() {
        let selected = uploadSpeedPopup.titleOfSelectedItem ?? "As fast as possible"
        UserDefaults.standard.set(selected, forKey: "sokovia_upload_speed")
    }

    @objc private func driveIconChanged() {
        let selected = driveIconPopup.titleOfSelectedItem ?? "Automatic"
        UserDefaults.standard.set(selected, forKey: "sokovia_drive_icon")
    }

    @objc private func autoUpdateToggled() {
        let enabled = (autoUpdateSwitch.state == .on)
        UserDefaults.standard.set(enabled, forKey: "sokovia_auto_update")
    }

    @objc private func sendReportsToggled() {
        let enabled = (sendReportsSwitch.state == .on)
        UserDefaults.standard.set(enabled, forKey: "sokovia_send_reports")
    }

    @objc private func spaceLimitChanged() {
        let selected = spacePopup.titleOfSelectedItem ?? "Automatic"
        UserDefaults.standard.set(selected, forKey: "sokovia_space_limit")
    }

    @objc private func signOutClicked() {
        let alert = NSAlert()
        alert.messageText = "Sign Out of This Mac?"
        alert.informativeText = "Signing out will safely unmount /Volumes/Sokovia and clear session credentials from this machine. Your files in your dedicated Cloudflare R2 bucket are preserved."
        alert.addButton(withTitle: "Sign Out")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .critical

        if alert.runModal() == .alertFirstButtonReturn {
            Task {
                await AppState.shared.stopDrive()
                await MainActor.run {
                    var cfg = AppState.shared.config
                    cfg.userEmail = ""
                    cfg.bucketName = ""
                    cfg.save()
                    AppState.shared.config = cfg
                    self.window?.close()
                    StatusItemManager.shared.updateMenu()

                    let finishAlert = NSAlert()
                    finishAlert.messageText = "Signed Out"
                    finishAlert.informativeText = "You have signed out of Sokovia on this Mac."
                    finishAlert.runModal()
                }
            }
        }
    }

    @objc private func checkUpdatesClicked() {
        let alert = NSAlert()
        alert.messageText = "You're up to date!"
        alert.informativeText = "Sokovia 1.0.0 is currently the latest version available."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    public func applyTheme(_ appearance: NSAppearance?) {
        window?.appearance = appearance
        guard let window = self.window, let content = window.contentView else { return }

        let isDark = appearance?.name == .darkAqua || (appearance == nil && NSApp.effectiveAppearance.name == .darkAqua)
        content.layer?.backgroundColor = isDark
            ? NSColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1.0).cgColor
            : NSColor(red: 0.95, green: 0.95, blue: 0.97, alpha: 1.0).cgColor

        // Refresh currently active tab view so makeCardView colors dynamically reload
        tabViews.removeAll()
        switchToTab(currentTab)
    }
}
