import AppKit

@MainActor
public final class DevicePairingWindowController: NSWindowController, NSWindowDelegate {
    public static let shared = DevicePairingWindowController()

    private let titleLabel = NSTextField(labelWithString: "Allow this device?")
    private let subtitleLabel = NSTextField(labelWithString: "Chrome on Mac")
    private let codeLabel = NSTextField(labelWithString: "--- ---")
    private let promptLabel = NSTextField(labelWithString: "Do these numbers match the ones on that device?")
    private let warningLabel = NSTextField(labelWithString: "It will be able to open all your encrypted files.")
    private let denyButton = NSButton()
    private let allowButton = NSButton()
    private var iconContainerView: NSView?
    private var iconImageView: NSImageView?

    private var currentRequestId: String = ""
    private var isShowing: Bool = false

    private var currentEmail: String = ""

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 380),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Allow Device"
        window.center()
        window.isReleasedWhenClosed = false
        window.isMovable = true
        window.isMovableByWindowBackground = true
        window.level = .floating

        super.init(window: window)
        window.delegate = self
        setupUI()
        applyTheme(NSApp.appearance)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        guard let window = self.window else { return }
        let content = NSView(frame: window.contentRect(forFrameRect: window.frame))
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor(red: 0.13, green: 0.13, blue: 0.14, alpha: 1.0).cgColor
        window.contentView = content

        // App Icon container
        let iconContainer = NSView(frame: NSRect(x: (380 - 64) / 2, y: 280, width: 64, height: 64))
        iconContainer.wantsLayer = true
        iconContainer.layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.08).cgColor
        iconContainer.layer?.cornerRadius = 14
        self.iconContainerView = iconContainer

        let iconView = NSImageView(frame: NSRect(x: 14, y: 14, width: 36, height: 36))
        if let driveIcon = NSImage(systemSymbolName: "lock.shield.fill", accessibilityDescription: "Security") {
            let cfg = NSImage.SymbolConfiguration(paletteColors: [.labelColor])
            iconView.image = driveIcon.withSymbolConfiguration(cfg)
        }
        self.iconImageView = iconView
        iconContainer.addSubview(iconView)
        content.addSubview(iconContainer)

        // Title: Allow this device?
        titleLabel.font = NSFont.boldSystemFont(ofSize: 18)
        titleLabel.alignment = .center
        titleLabel.textColor = .labelColor
        titleLabel.frame = NSRect(x: 20, y: 242, width: 340, height: 26)
        content.addSubview(titleLabel)

        // Subtitle: Chrome on Mac
        subtitleLabel.font = NSFont.systemFont(ofSize: 12.5)
        subtitleLabel.alignment = .center
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.frame = NSRect(x: 20, y: 220, width: 340, height: 18)
        content.addSubview(subtitleLabel)

        // Large 6-digit Code: 988 932
        codeLabel.font = NSFont.monospacedSystemFont(ofSize: 36, weight: .bold)
        codeLabel.alignment = .center
        codeLabel.textColor = .labelColor
        codeLabel.frame = NSRect(x: 20, y: 160, width: 340, height: 46)
        content.addSubview(codeLabel)

        // Prompt
        promptLabel.font = NSFont.systemFont(ofSize: 12)
        promptLabel.alignment = .center
        promptLabel.textColor = .secondaryLabelColor
        promptLabel.frame = NSRect(x: 20, y: 130, width: 340, height: 18)
        content.addSubview(promptLabel)

        // Warning
        warningLabel.font = NSFont.systemFont(ofSize: 11)
        warningLabel.alignment = .center
        warningLabel.textColor = .tertiaryLabelColor
        warningLabel.frame = NSRect(x: 20, y: 95, width: 340, height: 18)
        content.addSubview(warningLabel)

        // Buttons
        // Don't Allow button
        denyButton.title = "Don't Allow"
        denyButton.bezelStyle = .rounded
        denyButton.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        denyButton.frame = NSRect(x: 32, y: 34, width: 150, height: 36)
        denyButton.target = self
        denyButton.action = #selector(denyClicked)
        content.addSubview(denyButton)

        // Allow button (Helumi style red/coral or prominent)
        allowButton.title = "Allow"
        allowButton.bezelStyle = .rounded
        allowButton.font = NSFont.systemFont(ofSize: 13, weight: .bold)
        allowButton.frame = NSRect(x: 198, y: 34, width: 150, height: 36)
        allowButton.target = self
        allowButton.action = #selector(allowClicked)
        allowButton.wantsLayer = true
        content.addSubview(allowButton)
    }

    public func presentRequest(id: String, code: String, deviceInfo: String, userEmail: String = "") {
        self.currentRequestId = id
        self.currentEmail = userEmail
        self.codeLabel.stringValue = code
        self.subtitleLabel.stringValue = deviceInfo.isEmpty ? "Chrome on Mac" : deviceInfo
        self.isShowing = true

        window?.center()
        window?.orderFrontRegardless()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func allowClicked() {
        guard !currentRequestId.isEmpty else {
            window?.close()
            return
        }

        let passphrase = AppState.shared.config.encryptionPassphrase
        let reqId = self.currentRequestId
        let email = self.currentEmail
        self.window?.close()
        self.isShowing = false

        Task {
            // 1. Send approval back to InsForge edge function
            guard let url = URL(string: "https://26u7vqfh.function2.insforge.app/device-pairing?action=respond") else { return }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let payload: [String: Any] = [
                "id": reqId,
                "status": "approved",
                "encryptionKey": passphrase
            ]
            req.httpBody = try? JSONSerialization.data(withJSONObject: payload)
            _ = try? await URLSession.shared.data(for: req)

            // 2. Automatically sync userEmail & provision bucket if needed
            if !email.isEmpty {
                AppState.shared.config.userEmail = email
                do {
                    let (bucket, userId) = try await SokoviaConfig.provisionUserBucket(email: email)
                    AppState.shared.config.bucketName = bucket
                    AppState.shared.config.userId = userId
                    AppState.shared.config.save()
                    await AppState.shared.startDrive()
                    await MainActor.run {
                        StatusItemManager.shared.updateMenu()
                    }
                } catch {
                    print("Error auto-provisioning bucket: \(error)")
                }
            } else if AppState.shared.config.isConfigured {
                await AppState.shared.startDrive()
                await MainActor.run {
                    StatusItemManager.shared.updateMenu()
                }
            }
        }
    }

    @objc private func denyClicked() {
        let reqId = self.currentRequestId
        self.window?.close()
        self.isShowing = false

        Task {
            guard let url = URL(string: "https://26u7vqfh.function2.insforge.app/device-pairing?action=respond") else { return }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let payload: [String: Any] = [
                "id": reqId,
                "status": "rejected"
            ]
            req.httpBody = try? JSONSerialization.data(withJSONObject: payload)
            _ = try? await URLSession.shared.data(for: req)
        }
    }

    // MARK: - Background Polling for Mac app
    private var pollTimer: Timer?

    public func startPolling() {
        stopPolling()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.checkForPendingRequests()
            }
        }
    }

    public func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func checkForPendingRequests() async {
        guard !isShowing else { return }
        let email = AppState.shared.config.userEmail

        var urlString = "https://26u7vqfh.function2.insforge.app/device-pairing?action=pending"
        if !email.isEmpty, let encodedEmail = email.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            urlString += "&email=\(encodedEmail)"
        }

        guard let url = URL(string: urlString) else { return }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let requests = json["requests"] as? [[String: Any]],
                  let first = requests.first,
                  let id = first["id"] as? String,
                  let code = first["code"] as? String else {
                return
            }
            let deviceInfo = (first["device_info"] as? String) ?? "Chrome on Mac"
            let reqEmail = (first["user_email"] as? String) ?? email
            self.presentRequest(id: id, code: code, deviceInfo: deviceInfo, userEmail: reqEmail)
        } catch {}
    }

    public func applyTheme(_ appearance: NSAppearance?) {
        window?.appearance = appearance
        guard let window = self.window, let content = window.contentView else { return }

        let isDark = appearance?.name == .darkAqua || (appearance == nil && NSApp.effectiveAppearance.name == .darkAqua)
        content.layer?.backgroundColor = isDark
            ? NSColor(red: 0.13, green: 0.13, blue: 0.14, alpha: 1.0).cgColor
            : NSColor(red: 0.96, green: 0.96, blue: 0.97, alpha: 1.0).cgColor

        iconContainerView?.layer?.backgroundColor = isDark
            ? NSColor(white: 1.0, alpha: 0.08).cgColor
            : NSColor(white: 0.0, alpha: 0.06).cgColor

        if let driveIcon = NSImage(systemSymbolName: "lock.shield.fill", accessibilityDescription: "Security") {
            let color: NSColor = isDark ? .white : .black
            let cfg = NSImage.SymbolConfiguration(paletteColors: [color])
            iconImageView?.image = driveIcon.withSymbolConfiguration(cfg)
        }
    }
}

