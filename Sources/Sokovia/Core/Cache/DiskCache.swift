import Foundation

public actor DiskCache {
    private let cacheDirectory: URL
    private var memoryMetadataCache: [String: (items: [S3ObjectItem], folders: [String], expiry: Date)] = [:]
    private let metadataTTL: TimeInterval = 10.0 // 10 seconds metadata cache

    public init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        self.cacheDirectory = caches.appendingPathComponent("Sokovia/FileCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Metadata Cache

    public func getCachedListing(prefix: String) -> (items: [S3ObjectItem], folders: [String])? {
        if let cached = memoryMetadataCache[prefix], cached.expiry > Date() {
            return (cached.items, cached.folders)
        }
        return nil
    }

    public func setCachedListing(prefix: String, items: [S3ObjectItem], folders: [String]) {
        memoryMetadataCache[prefix] = (items, folders, Date().addingTimeInterval(metadataTTL))
    }

    public func invalidateListing(prefix: String? = nil) {
        if let p = prefix {
            memoryMetadataCache.removeValue(forKey: p)
        } else {
            memoryMetadataCache.removeAll()
        }
    }

    // MARK: - Disk File Cache

    private func localURL(for key: String) -> URL {
        let safeName = key.replacingOccurrences(of: "/", with: "_")
        return cacheDirectory.appendingPathComponent(safeName)
    }

    public func getCachedFile(for key: String) -> Data? {
        let url = localURL(for: key)
        return try? Data(contentsOf: url)
    }

    public func saveCachedFile(for key: String, data: Data) {
        let url = localURL(for: key)
        try? data.write(to: url, options: .atomic)
    }

    public func removeCachedFile(for key: String) {
        let url = localURL(for: key)
        try? FileManager.default.removeItem(at: url)
    }

    public func currentCacheSizeFormatted() -> String {
        guard let files = try? FileManager.default.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: [.fileSizeKey]) else {
            return "0 KB"
        }
        var totalBytes: Int64 = 0
        for file in files {
            if let resources = try? file.resourceValues(forKeys: [.fileSizeKey]), let size = resources.fileSize {
                totalBytes += Int64(size)
            }
        }
        if totalBytes < 1024 {
            return "\(totalBytes) B"
        } else if totalBytes < 1024 * 1024 {
            return String(format: "%.1f KB", Double(totalBytes) / 1024.0)
        } else if totalBytes < 1024 * 1024 * 1024 {
            return String(format: "%.1f MB", Double(totalBytes) / (1024.0 * 1024.0))
        } else {
            return String(format: "%.2f GB", Double(totalBytes) / (1024.0 * 1024.0 * 1024.0))
        }
    }

    public func clearAllCache() {
        memoryMetadataCache.removeAll()
        if let files = try? FileManager.default.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil) {
            for file in files {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }
}

