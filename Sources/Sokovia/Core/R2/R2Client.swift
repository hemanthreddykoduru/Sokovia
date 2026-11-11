import Foundation
import CryptoKit

public actor R2Client {
    private let config: SokoviaConfig
    private let crypto: CryptoManager?
    private let urlSession: URLSession

    private let region = "auto"
    private let service = "s3"

    public init(config: SokoviaConfig) {
        self.config = config
        if config.encryptionEnabled && !config.encryptionPassphrase.isEmpty {
            self.crypto = CryptoManager(passphrase: config.encryptionPassphrase, saltString: config.bucketName)
        } else {
            self.crypto = nil
        }

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 300
        self.urlSession = URLSession(configuration: configuration)
    }

    // MARK: - AWS Signature Version 4 Helpers

    private let iso8601DateStampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyyMMdd"
        return f
    }()

    private let iso8601DateTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return f
    }()

    private func rfc3986Encode(_ string: String) -> String {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.~")
        return string.addingPercentEncoding(withAllowedCharacters: allowed) ?? string
    }

    private func sha256Hex(_ data: Data) -> String {
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func hmacSHA256(key: Data, data: Data) -> Data {
        let hmac = HMAC<SHA256>.authenticationCode(for: data, using: SymmetricKey(data: key))
        return Data(hmac)
    }

    private func getSignatureKey(secretKey: String, dateStamp: String) -> Data {
        let kDate = hmacSHA256(key: Data("AWS4\(secretKey)".utf8), data: Data(dateStamp.utf8))
        let kRegion = hmacSHA256(key: kDate, data: Data(region.utf8))
        let kService = hmacSHA256(key: kRegion, data: Data(service.utf8))
        let kSigning = hmacSHA256(key: kService, data: Data("aws4_request".utf8))
        return kSigning
    }

    private func signRequest(
        method: String,
        url: URL,
        headers: [String: String],
        body: Data?
    ) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body

        let now = Date()
        let amzDate = iso8601DateTimeFormatter.string(from: now)
        let dateStamp = iso8601DateStampFormatter.string(from: now)

        let payloadHash = sha256Hex(body ?? Data())
        
        var allHeaders = headers
        allHeaders["x-amz-date"] = amzDate
        allHeaders["x-amz-content-sha256"] = payloadHash
        if let host = url.host {
            allHeaders["host"] = host
        }

        // Canonical Headers
        let sortedHeaderKeys = allHeaders.keys.map { $0.lowercased() }.sorted()
        let canonicalHeaders = sortedHeaderKeys.map { key in
            "\(key):\(allHeaders.first(where: { $0.key.lowercased() == key })!.value.trimmingCharacters(in: .whitespacesAndNewlines))\n"
        }.joined()
        let signedHeaders = sortedHeaderKeys.joined(separator: ";")

        // Canonical URI (Each path component must be RFC3986 encoded)
        var canonicalURI = url.path
        if canonicalURI.isEmpty {
            canonicalURI = "/"
        } else {
            let unreservedWithSlash = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.~/")
            canonicalURI = canonicalURI.addingPercentEncoding(withAllowedCharacters: unreservedWithSlash) ?? canonicalURI
        }
        
        // Canonical Query String
        var canonicalQueryString = ""
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let queryItems = components.queryItems {
            let sortedItems = queryItems.sorted { $0.name < $1.name }
            canonicalQueryString = sortedItems.map { item in
                let encodedName = rfc3986Encode(item.name)
                let encodedVal = rfc3986Encode(item.value ?? "")
                return "\(encodedName)=\(encodedVal)"
            }.joined(separator: "&")
        }

        // Canonical Request
        let canonicalRequest = "\(method)\n\(canonicalURI)\n\(canonicalQueryString)\n\(canonicalHeaders)\n\(signedHeaders)\n\(payloadHash)"
        let canonicalRequestHash = sha256Hex(Data(canonicalRequest.utf8))

        // String To Sign
        let credentialScope = "\(dateStamp)/\(region)/\(service)/aws4_request"
        let stringToSign = "AWS4-HMAC-SHA256\n\(amzDate)\n\(credentialScope)\n\(canonicalRequestHash)"

        // Signature
        let signingKey = getSignatureKey(secretKey: config.secretAccessKey, dateStamp: dateStamp)
        let signatureData = hmacSHA256(key: signingKey, data: Data(stringToSign.utf8))
        let signature = signatureData.map { String(format: "%02x", $0) }.joined()

        let authHeader = "AWS4-HMAC-SHA256 Credential=\(config.accessKeyId)/\(credentialScope), SignedHeaders=\(signedHeaders), Signature=\(signature)"

        for (k, v) in allHeaders {
            request.setValue(v, forHTTPHeaderField: k)
        }
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")

        return request
    }

    // MARK: - Public S3 Operations

    private var bucketBaseURL: URL? {
        guard let base = config.s3EndpointURL else { return nil }
        return base.appendingPathComponent(config.bucketName)
    }

    /// Verifies credentials by querying the bucket
    public func testConnection() async throws -> (success: Bool, message: String) {
        guard config.isConfigured else {
            return (false, "Missing required Cloudflare R2 credentials.")
        }
        guard let url = bucketBaseURL else {
            return (false, "Invalid endpoint or bucket name.")
        }

        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "list-type", value: "2"),
            URLQueryItem(name: "max-keys", value: "1")
        ]
        
        let request = signRequest(
            method: "GET",
            url: components.url!,
            headers: [:],
            body: nil
        )

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            return (false, "Non-HTTP response.")
        }

        if http.statusCode == 200 {
            return (true, "Successfully connected to R2 bucket '\(config.bucketName)'!")
        } else {
            let errText = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            return (false, "R2 Error (\(http.statusCode)): \(errText)")
        }
    }

    /// Lists directory contents for a specific prefix
    public func listObjects(prefix: String, delimiter: String = "/") async throws -> (files: [S3ObjectItem], folders: [String]) {
        guard let url = bucketBaseURL else {
            throw NSError(domain: "SokoviaR2", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid R2 URL"])
        }

        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        var queryItems = [
            URLQueryItem(name: "list-type", value: "2"),
            URLQueryItem(name: "delimiter", value: delimiter)
        ]
        let cleanPrefix = prefix.hasPrefix("/") ? String(prefix.dropFirst()) : prefix
        if !cleanPrefix.isEmpty {
            queryItems.append(URLQueryItem(name: "prefix", value: cleanPrefix))
        }
        components.queryItems = queryItems

        let request = signRequest(
            method: "GET",
            url: components.url!,
            headers: [:],
            body: nil
        )

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 500
            throw NSError(domain: "SokoviaR2", code: code, userInfo: [NSLocalizedDescriptionKey: "Failed to list objects"])
        }

        let parser = S3ListObjectsParser()
        let xmlParser = XMLParser(data: data)
        xmlParser.delegate = parser
        xmlParser.parse()

        // Filter out the directory prefix itself from file contents if returned
        let files = parser.objects.filter { $0.key != cleanPrefix && !$0.isDirectory }
        let folders = parser.commonPrefixes

        return (files, folders)
    }

    public nonisolated func mimeType(for path: String) -> String {
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "svg": return "image/svg+xml"
        case "pdf": return "application/pdf"
        case "mp4": return "video/mp4"
        case "mov": return "video/quicktime"
        case "mp3": return "audio/mpeg"
        case "wav": return "audio/wav"
        case "zip": return "application/zip"
        case "json": return "application/json"
        case "txt", "md": return "text/plain"
        case "html": return "text/html"
        default: return "application/octet-stream"
        }
    }

    /// Fetches file content, optionally with Range header support for video/audio seeking
    public func getObject(key: String, rangeHeader: String? = nil) async throws -> (data: Data, fullSize: Int64, mimeType: String, isPartial: Bool) {
        guard let base = bucketBaseURL else {
            throw NSError(domain: "SokoviaR2", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid R2 URL"])
        }
        let cleanKey = key.hasPrefix("/") ? String(key.dropFirst()) : key
        let url = base.appendingPathComponent(cleanKey)

        var headers: [String: String] = [:]
        // Range requests only supported if encryption is OFF (as encrypted AES-GCM blocks require entire segment/chunk authentication)
        if let range = rangeHeader, crypto == nil {
            headers["Range"] = range
        }

        let request = signRequest(method: "GET", url: url, headers: headers, body: nil)
        let (rawData, response) = try await urlSession.data(for: request)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 || http.statusCode == 206 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 404
            throw NSError(domain: "SokoviaR2", code: code, userInfo: [NSLocalizedDescriptionKey: "Object not found (\(cleanKey))"])
        }

        let mimeType = http.value(forHTTPHeaderField: "Content-Type") ?? "application/octet-stream"
        var finalData = rawData

        // Decrypt if client-side encryption is active
        if let crypto = self.crypto {
            finalData = try crypto.decrypt(data: rawData)
        }

        var fullSize = Int64(finalData.count)
        if let lengthStr = http.value(forHTTPHeaderField: "Content-Length"), let parsed = Int64(lengthStr) {
            fullSize = parsed
        }

        return (finalData, fullSize, mimeType, http.statusCode == 206)
    }

    /// Uploads an object to R2
    public func putObject(key: String, data: Data, contentType: String = "application/octet-stream") async throws {
        guard let base = bucketBaseURL else {
            throw NSError(domain: "SokoviaR2", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid R2 URL"])
        }
        let cleanKey = key.hasPrefix("/") ? String(key.dropFirst()) : key
        let url = base.appendingPathComponent(cleanKey)

        var uploadData = data
        // Encrypt if client-side encryption is active
        if let crypto = self.crypto {
            uploadData = try crypto.encrypt(data: data)
        }

        var headers: [String: String] = [
            "Content-Type": contentType,
            "Content-Length": String(uploadData.count)
        ]
        if crypto != nil {
            headers["x-amz-meta-encrypted"] = "aes-gcm-256"
        }

        let request = signRequest(method: "PUT", url: url, headers: headers, body: uploadData)
        let (respData, response) = try await urlSession.data(for: request)

        guard let http = response as? HTTPURLResponse, http.statusCode >= 200 && http.statusCode < 300 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 500
            let err = String(data: respData, encoding: .utf8) ?? "HTTP \(code)"
            throw NSError(domain: "SokoviaR2", code: code, userInfo: [NSLocalizedDescriptionKey: "Failed to upload: \(err)"])
        }
    }

    /// Deletes an object from R2
    public func deleteObject(key: String) async throws {
        guard let base = bucketBaseURL else {
            throw NSError(domain: "SokoviaR2", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid R2 URL"])
        }
        let cleanKey = key.hasPrefix("/") ? String(key.dropFirst()) : key
        let url = base.appendingPathComponent(cleanKey)

        let request = signRequest(method: "DELETE", url: url, headers: [:], body: nil)
        let (_, response) = try await urlSession.data(for: request)

        guard let http = response as? HTTPURLResponse, http.statusCode >= 200 && http.statusCode < 300 || http.statusCode == 204 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 500
            throw NSError(domain: "SokoviaR2", code: code, userInfo: [NSLocalizedDescriptionKey: "Failed to delete \(cleanKey)"])
        }
    }

    /// Moves or renames an object
    public func copyObject(fromKey: String, toKey: String) async throws {
        guard let base = bucketBaseURL else {
            throw NSError(domain: "SokoviaR2", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid R2 URL"])
        }
        let cleanFrom = fromKey.hasPrefix("/") ? String(fromKey.dropFirst()) : fromKey
        let cleanTo = toKey.hasPrefix("/") ? String(toKey.dropFirst()) : toKey
        let destURL = base.appendingPathComponent(cleanTo)

        let copySource = "\(config.bucketName)/\(cleanFrom)"
        let headers = [
            "x-amz-copy-source": copySource.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? copySource
        ]

        let request = signRequest(method: "PUT", url: destURL, headers: headers, body: nil)
        let (_, response) = try await urlSession.data(for: request)

        guard let http = response as? HTTPURLResponse, http.statusCode >= 200 && http.statusCode < 300 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 500
            throw NSError(domain: "SokoviaR2", code: code, userInfo: [NSLocalizedDescriptionKey: "Failed to copy object"])
        }

        // Delete original
        try await deleteObject(key: cleanFrom)
    }

    /// Creates an empty directory marker (e.g. "photos/")
    public func createDirectory(prefix: String) async throws {
        var clean = prefix.hasPrefix("/") ? String(prefix.dropFirst()) : prefix
        if !clean.hasSuffix("/") { clean += "/" }
        try await putObject(key: clean, data: Data(), contentType: "application/x-directory")
    }
}

