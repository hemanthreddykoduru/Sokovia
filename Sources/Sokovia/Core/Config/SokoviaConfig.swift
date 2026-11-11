import Foundation

public struct SokoviaConfig: Codable, Equatable, Sendable {
    public var userEmail: String
    public var userId: String
    public var accountId: String
    public var accessKeyId: String
    public var secretAccessKey: String
    public var bucketName: String
    public var customEndpoint: String
    public var encryptionEnabled: Bool
    public var encryptionPassphrase: String
    public var mountPath: String
    public var localPort: UInt16

    public init(
        userEmail: String = "",
        userId: String = "",
        accountId: String = "",
        accessKeyId: String = "",
        secretAccessKey: String = "",
        bucketName: String = "",
        customEndpoint: String = "",
        encryptionEnabled: Bool = false,
        mountPath: String = "/Volumes/Sokovia",
        localPort: UInt16 = 9876,
        encryptionPassphrase: String = ""
    ) {
        self.userEmail = userEmail
        self.userId = userId
        self.accountId = accountId
        self.accessKeyId = accessKeyId
        self.bucketName = bucketName
        self.customEndpoint = customEndpoint
        self.encryptionEnabled = encryptionEnabled
        self.mountPath = mountPath
        self.localPort = localPort
        self.secretAccessKey = secretAccessKey
        self.encryptionPassphrase = encryptionPassphrase
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.userEmail = (try? container.decode(String.self, forKey: .userEmail)) ?? ""
        self.userId = (try? container.decode(String.self, forKey: .userId)) ?? ""
        self.accountId = (try? container.decode(String.self, forKey: .accountId)) ?? ""
        self.accessKeyId = (try? container.decode(String.self, forKey: .accessKeyId)) ?? ""
        self.secretAccessKey = (try? container.decode(String.self, forKey: .secretAccessKey)) ?? ""
        self.bucketName = (try? container.decode(String.self, forKey: .bucketName)) ?? ""
        self.customEndpoint = (try? container.decode(String.self, forKey: .customEndpoint)) ?? ""
        self.encryptionEnabled = (try? container.decode(Bool.self, forKey: .encryptionEnabled)) ?? false
        self.encryptionPassphrase = (try? container.decode(String.self, forKey: .encryptionPassphrase)) ?? ""
        self.mountPath = (try? container.decode(String.self, forKey: .mountPath)) ?? "/Volumes/Sokovia"
        self.localPort = (try? container.decode(UInt16.self, forKey: .localPort)) ?? 9876
    }

    public var s3EndpointURL: URL? {
        if !customEndpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let trimmed = customEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
            return URL(string: trimmed.hasPrefix("http") ? trimmed : "https://\(trimmed)")
        }
        guard !accountId.isEmpty else { return nil }
        return URL(string: "https://\(accountId).r2.cloudflarestorage.com")
    }

    public var isConfigured: Bool {
        return !accountId.isEmpty && !accessKeyId.isEmpty && !secretAccessKey.isEmpty && !bucketName.isEmpty
    }

    private static var configURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Sokovia", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("config.json")
    }

    public static func load() -> SokoviaConfig {
        var config = SokoviaConfig()
        if let data = try? Data(contentsOf: configURL),
           let decoded = try? JSONDecoder().decode(SokoviaConfig.self, from: data) {
            config = decoded
        }
        // Load secrets from secure macOS Keychain if present
        if let secret = KeychainHelper.load(key: "secretAccessKey"), !secret.isEmpty {
            config.secretAccessKey = secret
        }
        if let pass = KeychainHelper.load(key: "encryptionPassphrase"), !pass.isEmpty {
            config.encryptionPassphrase = pass
        }
        return config
    }

    public func save() {
        // Save sensitive keys to Apple Keychain
        if !secretAccessKey.isEmpty {
            KeychainHelper.save(key: "secretAccessKey", data: secretAccessKey)
        }
        if !encryptionPassphrase.isEmpty {
            KeychainHelper.save(key: "encryptionPassphrase", data: encryptionPassphrase)
        }
        if let data = try? JSONEncoder().encode(self) {
            try? data.write(to: Self.configURL, options: .atomic)
            // Restrict permissions so only the owner can read/write this file (chmod 600)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: Self.configURL.path)
        }
    }

    /// Automatically provisions or fetches an isolated bucket for the given email via InsForge backend
    public static func provisionUserBucket(email: String, displayName: String = "") async throws -> (bucketName: String, userId: String) {
        guard let url = URL(string: "https://26u7vqfh.function2.insforge.app/provision-user-bucket") else {
            throw NSError(domain: "Sokovia", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid InsForge function URL"])
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload = ["email": email, "displayName": displayName]
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let err = String(data: data, encoding: .utf8) ?? "HTTP Error"
            throw NSError(domain: "Sokovia", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to provision bucket: \(err)"])
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let bucket = json["bucket"] as? [String: Any],
              let bucketName = bucket["name"] as? String,
              let user = json["user"] as? [String: Any],
              let userId = user["id"] as? String else {
            throw NSError(domain: "Sokovia", code: 3, userInfo: [NSLocalizedDescriptionKey: "Invalid response from InsForge"])
        }

        return (bucketName, userId)
    }
}
