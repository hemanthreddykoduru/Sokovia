import Foundation
import Combine

@MainActor
public final class AppState: ObservableObject {
    public static let shared = AppState()

    @Published public var config: SokoviaConfig
    @Published public var isMounted: Bool = false
    @Published public var isConnecting: Bool = false
    @Published public var statusMessage: String = "Ready"
    @Published public var lastError: String?

    private var server: WebDAVServer?
    private var r2Client: R2Client?
    public let diskCache = DiskCache()

    private init() {
        let loadedConfig = SokoviaConfig.load()
        self.config = loadedConfig
        self.isMounted = MountManager.shared.isMounted(mountPath: loadedConfig.mountPath)
    }

    public func testConnection(with testConfig: SokoviaConfig) async -> (success: Bool, message: String) {
        let client = R2Client(config: testConfig)
        do {
            return try await client.testConnection()
        } catch {
            return (false, error.localizedDescription)
        }
    }

    public func startDrive() async {
        if config.bucketName.isEmpty && !config.userEmail.isEmpty {
            do {
                let (bucket, userId) = try await SokoviaConfig.provisionUserBucket(email: config.userEmail)
                config.bucketName = bucket
                config.userId = userId
                config.save()
            } catch {
                print("Failed to auto provision user bucket: \(error)")
            }
        }

        guard config.isConfigured else {
            statusMessage = "Configuration incomplete"
            lastError = "Please enter your Cloudflare R2 credentials in Settings."
            return
        }

        isConnecting = true
        statusMessage = "Connecting to R2..."
        lastError = nil

        let client = R2Client(config: config)
        self.r2Client = client

        // Test credentials first
        do {
            let (success, message) = try await client.testConnection()
            guard success else {
                isConnecting = false
                statusMessage = "Connection failed"
                lastError = message
                return
            }
        } catch {
            isConnecting = false
            statusMessage = "Connection failed"
            lastError = error.localizedDescription
            return
        }

        // Start WebDAV local server
        let webdav = WebDAVServer(port: config.localPort, r2Client: client, diskCache: diskCache)
        do {
            try webdav.start()
            self.server = webdav
        } catch {
            isConnecting = false
            statusMessage = "Server error"
            lastError = "Failed to bind to port \(config.localPort): \(error.localizedDescription)"
            return
        }

        // Mount volume
        statusMessage = "Mounting /Volumes/Sokovia..."
        do {
            try MountManager.shared.mount(port: config.localPort, mountPath: config.mountPath)
            self.isMounted = true
            self.statusMessage = "Connected to \(config.bucketName)"
        } catch {
            statusMessage = "Mount failed"
            lastError = "Failed to mount drive: \(error.localizedDescription)"
        }

        isConnecting = false
    }

    public func stopDrive() async {
        statusMessage = "Unmounting..."
        try? MountManager.shared.unmount(mountPath: config.mountPath)
        server?.stop()
        server = nil
        isMounted = false
        statusMessage = "Disconnected"
    }

    public func openInFinder() {
        MountManager.shared.openInFinder(mountPath: config.mountPath)
    }
}

