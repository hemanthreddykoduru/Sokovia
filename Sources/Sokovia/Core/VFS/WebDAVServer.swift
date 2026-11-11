import Foundation
import Network

public final class WebDAVServer: @unchecked Sendable {
    private let port: UInt16
    private let r2Client: R2Client
    private let diskCache: DiskCache
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.sokovia.webdav", attributes: .concurrent)

    public var isRunning: Bool { listener?.state == .ready }

    public init(port: UInt16, r2Client: R2Client, diskCache: DiskCache) {
        self.port = port
        self.r2Client = r2Client
        self.diskCache = diskCache
    }

    public func start() throws {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        let nwPort = NWEndpoint.Port(rawValue: port) ?? NWEndpoint.Port(integerLiteral: 9876)
        
        let newListener = try NWListener(using: params, on: nwPort)
        self.listener = newListener

        newListener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                print("Sokovia WebDAV Server running on 127.0.0.1:\(self.port)")
            case .failed(let err):
                print("Sokovia WebDAV Server failed: \(err)")
            default:
                break
            }
        }

        newListener.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }

        newListener.start(queue: queue)
    }

    public func stop() {
        listener?.cancel()
        listener = nil
    }

    // MARK: - Connection Handling

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        readData(connection: connection, accumulated: Data())
    }

    private func readData(connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, context, isComplete, error in
            guard let self = self else { return }
            var buffer = accumulated
            if let data = data, !data.isEmpty {
                buffer.append(data)
            }

            if let headerEnd = buffer.range(of: Data("\r\n\r\n".utf8)) {
                let headerData = buffer.subdata(in: 0..<headerEnd.lowerBound)
                let bodyData = buffer.subdata(in: headerEnd.upperBound..<buffer.count)

                guard let headerString = String(data: headerData, encoding: .utf8) else {
                    self.sendResponse(connection: connection, status: "400 Bad Request", headers: [:], body: Data())
                    return
                }

                let lines = headerString.components(separatedBy: "\r\n")
                guard let requestLine = lines.first else {
                    self.sendResponse(connection: connection, status: "400 Bad Request", headers: [:], body: Data())
                    return
                }

                let parts = requestLine.components(separatedBy: " ")
                guard parts.count >= 2 else {
                    self.sendResponse(connection: connection, status: "400 Bad Request", headers: [:], body: Data())
                    return
                }

                let method = parts[0].uppercased()
                let rawPath = parts[1]
                let decodedPath = rawPath.removingPercentEncoding ?? rawPath

                var headers: [String: String] = [:]
                for line in lines.dropFirst() {
                    let parts = line.split(separator: ":", maxSplits: 1).map(String.init)
                    if parts.count == 2 {
                        headers[parts[0].trimmingCharacters(in: .whitespaces).lowercased()] = parts[1].trimmingCharacters(in: .whitespaces)
                    }
                }

                let isChunked = headers["transfer-encoding"]?.lowercased().contains("chunked") ?? false
                let contentLength = Int(headers["content-length"] ?? "0") ?? 0

                if isChunked {
                    if let decoded = WebDAVServer.decodeChunkedData(bodyData) {
                        Task {
                            await self.processRequest(connection: connection, method: method, path: decodedPath, headers: headers, body: decoded)
                        }
                    } else {
                        self.readRemainingChunkedBody(connection: connection, method: method, path: decodedPath, headers: headers, accumulatedBody: bodyData)
                    }
                } else if bodyData.count < contentLength {
                    self.readRemainingBody(connection: connection, method: method, path: decodedPath, headers: headers, accumulatedBody: bodyData, expectedLength: contentLength)
                } else {
                    Task {
                        await self.processRequest(connection: connection, method: method, path: decodedPath, headers: headers, body: bodyData)
                    }
                }
            } else if !isComplete && error == nil {
                self.readData(connection: connection, accumulated: buffer)
            } else {
                connection.cancel()
            }
        }
    }

    private func readRemainingChunkedBody(connection: NWConnection, method: String, path: String, headers: [String: String], accumulatedBody: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, context, isComplete, error in
            guard let self = self else { return }
            var body = accumulatedBody
            if let data = data, !data.isEmpty {
                body.append(data)
            }

            if let decoded = WebDAVServer.decodeChunkedData(body) {
                Task {
                    await self.processRequest(connection: connection, method: method, path: path, headers: headers, body: decoded)
                }
            } else if isComplete || error != nil {
                let decoded = WebDAVServer.decodeChunkedData(body) ?? body
                Task {
                    await self.processRequest(connection: connection, method: method, path: path, headers: headers, body: decoded)
                }
            } else {
                self.readRemainingChunkedBody(connection: connection, method: method, path: path, headers: headers, accumulatedBody: body)
            }
        }
    }

    private func readRemainingBody(connection: NWConnection, method: String, path: String, headers: [String: String], accumulatedBody: Data, expectedLength: Int) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, context, isComplete, error in
            guard let self = self else { return }
            var body = accumulatedBody
            if let data = data {
                body.append(data)
            }
            if body.count >= expectedLength {
                Task {
                    await self.processRequest(connection: connection, method: method, path: path, headers: headers, body: body)
                }
            } else if !isComplete && error == nil {
                self.readRemainingBody(connection: connection, method: method, path: path, headers: headers, accumulatedBody: body, expectedLength: expectedLength)
            } else {
                connection.cancel()
            }
        }
    }

    // MARK: - WebDAV Request Processing

    private func processRequest(connection: NWConnection, method: String, path: String, headers: [String: String], body: Data) async {
        let isSokoviaPrefix = path.lowercased().hasPrefix("/sokovia")
        let baseHref = isSokoviaPrefix ? "/Sokovia" : ""
        
        var cleanPath = path
        if isSokoviaPrefix {
            cleanPath = String(cleanPath.dropFirst(8))
        }
        if cleanPath.hasPrefix("/") {
            cleanPath = String(cleanPath.dropFirst())
        }

        switch method {
        case "OPTIONS":
            let respHeaders = [
                "DAV": "1, 2",
                "MS-Author-Via": "DAV",
                "Allow": "OPTIONS, GET, HEAD, PROPFIND, PUT, DELETE, MKCOL, MOVE, COPY, LOCK, UNLOCK"
            ]
            sendResponse(connection: connection, status: "200 OK", headers: respHeaders, body: Data())

        case "PROPFIND":
            await handlePropfind(connection: connection, baseHref: baseHref, cleanPath: cleanPath, headers: headers)

        case "GET":
            await handleGet(connection: connection, cleanPath: cleanPath, headers: headers, isHead: false)

        case "HEAD":
            await handleGet(connection: connection, cleanPath: cleanPath, headers: headers, isHead: true)

        case "PUT":
            await handlePut(connection: connection, cleanPath: cleanPath, body: body)

        case "MKCOL":
            await handleMkcol(connection: connection, cleanPath: cleanPath)

        case "DELETE":
            await handleDelete(connection: connection, cleanPath: cleanPath)

        case "MOVE":
            await handleMove(connection: connection, cleanPath: cleanPath, headers: headers)

        case "LOCK":
            let lockToken = "urn:uuid:\(UUID().uuidString)"
            let xml = """
            <?xml version="1.0" encoding="utf-8" ?>
            <D:prop xmlns:D="DAV:">
                <D:lockdiscovery>
                    <D:activelock>
                        <D:locktype><D:write/></D:locktype>
                        <D:lockscope><D:exclusive/></D:lockscope>
                        <D:depth>Infinity</D:depth>
                        <D:timeout>Second-3600</D:timeout>
                        <D:locktoken><D:href>\(lockToken)</D:href></D:locktoken>
                    </D:activelock>
                </D:lockdiscovery>
            </D:prop>
            """
            sendResponse(connection: connection, status: "200 OK", headers: [
                "Content-Type": "application/xml; charset=utf-8",
                "Lock-Token": "<\(lockToken)>"
            ], body: Data(xml.utf8))

        case "UNLOCK":
            sendResponse(connection: connection, status: "204 No Content", headers: [:], body: Data())

        default:
            sendResponse(connection: connection, status: "501 Not Implemented", headers: [:], body: Data())
        }
    }

    // MARK: - Handlers

    private func handlePropfind(connection: NWConnection, baseHref: String, cleanPath: String, headers: [String: String]) async {
        let depth = headers["depth"] ?? "1"

        if cleanPath.isEmpty {
            // Root collection
            do {
                let (files, folders) = try await r2Client.listObjects(prefix: "")
                await diskCache.setCachedListing(prefix: "", items: files, folders: folders)

                var xml = "<?xml version=\"1.0\" encoding=\"utf-8\" ?>\n<D:multistatus xmlns:D=\"DAV:\">\n"
                let rootHref = baseHref.isEmpty ? "/" : "\(baseHref)/"
                xml += makeResponseXML(href: rootHref, isDirectory: true, size: 0, mtime: Date())

                if depth != "0" {
                    for folder in folders {
                        let folderHref = "\(baseHref)/\(folder)"
                        xml += makeResponseXML(href: folderHref, isDirectory: true, size: 0, mtime: Date())
                    }
                    for file in files {
                        let fileHref = "\(baseHref)/\(file.key)"
                        xml += makeResponseXML(href: fileHref, isDirectory: false, size: file.size, mtime: file.lastModified)
                    }
                }

                xml += "</D:multistatus>"
                sendResponse(connection: connection, status: "207 Multi-Status", headers: [
                    "Content-Type": "application/xml; charset=utf-8"
                ], body: Data(xml.utf8))
            } catch {
                sendResponse(connection: connection, status: "500 Internal Server Error", headers: [:], body: Data())
            }
            return
        }

        // Specific file or subfolder
        let parentDir = (cleanPath as NSString).deletingLastPathComponent
        let parentPrefix = (parentDir == "." || parentDir.isEmpty) ? "" : "\(parentDir)/"

        do {
            let (parentFiles, parentFolders) = try await r2Client.listObjects(prefix: parentPrefix)

            // Check if it is a file
            if let file = parentFiles.first(where: { $0.key == cleanPath }) {
                var xml = "<?xml version=\"1.0\" encoding=\"utf-8\" ?>\n<D:multistatus xmlns:D=\"DAV:\">\n"
                xml += makeResponseXML(href: "\(baseHref)/\(file.key)", isDirectory: false, size: file.size, mtime: file.lastModified)
                xml += "</D:multistatus>"
                sendResponse(connection: connection, status: "207 Multi-Status", headers: [
                    "Content-Type": "application/xml; charset=utf-8"
                ], body: Data(xml.utf8))
                return
            }

            // Check if it is a directory
            let folderPrefix = cleanPath.hasSuffix("/") ? cleanPath : "\(cleanPath)/"
            if parentFolders.contains(folderPrefix) {
                var xml = "<?xml version=\"1.0\" encoding=\"utf-8\" ?>\n<D:multistatus xmlns:D=\"DAV:\">\n"
                xml += makeResponseXML(href: "\(baseHref)/\(folderPrefix)", isDirectory: true, size: 0, mtime: Date())

                if depth != "0" {
                    let (subFiles, subFolders) = try await r2Client.listObjects(prefix: folderPrefix)
                    for folder in subFolders {
                        xml += makeResponseXML(href: "\(baseHref)/\(folder)", isDirectory: true, size: 0, mtime: Date())
                    }
                    for file in subFiles {
                        xml += makeResponseXML(href: "\(baseHref)/\(file.key)", isDirectory: false, size: file.size, mtime: file.lastModified)
                    }
                }

                xml += "</D:multistatus>"
                sendResponse(connection: connection, status: "207 Multi-Status", headers: [
                    "Content-Type": "application/xml; charset=utf-8"
                ], body: Data(xml.utf8))
                return
            }

            // Not found
            sendResponse(connection: connection, status: "404 Not Found", headers: [:], body: Data())
        } catch {
            sendResponse(connection: connection, status: "404 Not Found", headers: [:], body: Data())
        }
    }

    private func makeResponseXML(href: String, isDirectory: Bool, size: Int64, mtime: Date) -> String {
        let isoFormatter = ISO8601DateFormatter()
        let httpDateFormatter = DateFormatter()
        httpDateFormatter.locale = Locale(identifier: "en_US_POSIX")
        httpDateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        httpDateFormatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"

        let cleanHref = href.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? href
        let displayName = (href.trimmingCharacters(in: CharacterSet(charactersIn: "/")) as NSString).lastPathComponent

        let resourceType = isDirectory ? "<D:resourcetype><D:collection/></D:resourcetype>" : "<D:resourcetype/>"

        return """
        <D:response>
            <D:href>\(cleanHref)</D:href>
            <D:propstat>
                <D:prop>
                    <D:displayname>\(displayName.isEmpty ? "Sokovia" : displayName)</D:displayname>
                    \(resourceType)
                    <D:getcontentlength>\(size)</D:getcontentlength>
                    <D:getlastmodified>\(httpDateFormatter.string(from: mtime))</D:getlastmodified>
                    <D:creationdate>\(isoFormatter.string(from: mtime))</D:creationdate>
                </D:prop>
                <D:status>HTTP/1.1 200 OK</D:status>
            </D:propstat>
        </D:response>\n
        """
    }

    private func handleGet(connection: NWConnection, cleanPath: String, headers: [String: String], isHead: Bool) async {
        do {
            let range = headers["range"]

            // Check if full file is in local disk cache and no range requested
            if range == nil, var cachedData = await diskCache.getCachedFile(for: cleanPath) {
                if let decoded = WebDAVServer.decodeChunkedData(cachedData), !decoded.isEmpty {
                    cachedData = decoded
                    await diskCache.saveCachedFile(for: cleanPath, data: decoded)
                }
                let mimeType = r2Client.mimeType(for: cleanPath)
                let respHeaders = [
                    "Content-Type": mimeType,
                    "Content-Length": String(cachedData.count),
                    "Accept-Ranges": "bytes"
                ]
                sendResponse(connection: connection, status: "200 OK", headers: respHeaders, body: isHead ? Data() : cachedData)
                return
            }

            // If range requested and full file is in local disk cache, serve slice immediately
            if let range = range, var cachedData = await diskCache.getCachedFile(for: cleanPath) {
                if let decoded = WebDAVServer.decodeChunkedData(cachedData), !decoded.isEmpty {
                    cachedData = decoded
                    await diskCache.saveCachedFile(for: cleanPath, data: decoded)
                }
                if let (start, end) = WebDAVServer.parseByteRange(range, totalSize: cachedData.count) {
                    let slice = cachedData.subdata(in: start..<(end + 1))
                    let mimeType = r2Client.mimeType(for: cleanPath)
                    let respHeaders = [
                        "Content-Type": mimeType,
                        "Content-Length": String(slice.count),
                        "Content-Range": "bytes \(start)-\(end)/\(cachedData.count)",
                        "Accept-Ranges": "bytes"
                    ]
                    sendResponse(connection: connection, status: "206 Partial Content", headers: respHeaders, body: isHead ? Data() : slice)
                    return
                }
            }

            var (data, fullSize, mimeType, isPartial) = try await r2Client.getObject(key: cleanPath, rangeHeader: range)

            // Auto-heal chunked payloads if detected
            if !isPartial, range == nil, let decoded = WebDAVServer.decodeChunkedData(data), !decoded.isEmpty {
                data = decoded
                fullSize = Int64(decoded.count)
                Task {
                    try? await self.r2Client.putObject(key: cleanPath, data: decoded, contentType: mimeType)
                    await self.diskCache.saveCachedFile(for: cleanPath, data: decoded)
                }
            }

            // Cache full file downloads to local disk cache
            if !isPartial && range == nil {
                await diskCache.saveCachedFile(for: cleanPath, data: data)
            }

            var respHeaders = [
                "Content-Type": mimeType,
                "Content-Length": String(data.count),
                "Accept-Ranges": "bytes"
            ]
            let status = isPartial ? "206 Partial Content" : "200 OK"
            if isPartial, let range = range {
                let cleanRange = range.replacingOccurrences(of: "bytes=", with: "bytes ")
                respHeaders["Content-Range"] = "\(cleanRange)/\(fullSize)"
            }

            sendResponse(connection: connection, status: status, headers: respHeaders, body: isHead ? Data() : data)
        } catch {
            sendResponse(connection: connection, status: "404 Not Found", headers: [:], body: Data())
        }
    }

    private func handlePut(connection: NWConnection, cleanPath: String, body: Data) async {
        do {
            var payload = body
            if let decoded = WebDAVServer.decodeChunkedData(body), !decoded.isEmpty {
                payload = decoded
            }
            try await r2Client.putObject(key: cleanPath, data: payload)
            await diskCache.saveCachedFile(for: cleanPath, data: payload)
            await diskCache.invalidateListing()
            sendResponse(connection: connection, status: "201 Created", headers: [:], body: Data())
        } catch {
            sendResponse(connection: connection, status: "500 Internal Server Error", headers: [:], body: Data())
        }
    }

    // MARK: - Chunked Encoding & Range Helpers

    public static func decodeChunkedData(_ data: Data) -> Data? {
        var output = Data()
        var offset = 0
        let crlf = Data("\r\n".utf8)

        while offset < data.count {
            guard let lineEndRange = data.range(of: crlf, options: [], in: offset..<data.count) else {
                return nil
            }

            let lineData = data.subdata(in: offset..<lineEndRange.lowerBound)
            guard let lineStr = String(data: lineData, encoding: .utf8)?.trimmingCharacters(in: .whitespaces) else {
                return nil
            }

            let sizeStr = lineStr.split(separator: ";").first.map(String.init) ?? lineStr
            guard let chunkSize = Int(sizeStr.trimmingCharacters(in: .whitespaces), radix: 16) else {
                return nil
            }

            if chunkSize == 0 {
                return output
            }

            let chunkDataStart = lineEndRange.upperBound
            let chunkDataEnd = chunkDataStart + chunkSize

            guard chunkDataEnd <= data.count else {
                return nil
            }

            output.append(data.subdata(in: chunkDataStart..<chunkDataEnd))

            let nextOffset = chunkDataEnd
            if nextOffset + 2 <= data.count && data.subdata(in: nextOffset..<nextOffset + 2) == crlf {
                offset = nextOffset + 2
            } else {
                offset = nextOffset
            }
        }

        return output.isEmpty ? nil : output
    }

    public static func parseByteRange(_ header: String, totalSize: Int) -> (start: Int, end: Int)? {
        guard totalSize > 0, header.hasPrefix("bytes=") else { return nil }
        let spec = String(header.dropFirst(6)).trimmingCharacters(in: .whitespaces)
        let parts = spec.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2 else { return nil }

        if parts[0].isEmpty, let suffixLen = Int(parts[1]) {
            let start = max(0, totalSize - suffixLen)
            let end = totalSize - 1
            return (start, end)
        } else if let start = Int(parts[0]) {
            if parts[1].isEmpty {
                let end = totalSize - 1
                guard start <= end else { return nil }
                return (start, end)
            } else if let end = Int(parts[1]) {
                guard start <= end, start < totalSize else { return nil }
                return (start, min(end, totalSize - 1))
            }
        }
        return nil
    }

    private func handleMkcol(connection: NWConnection, cleanPath: String) async {
        do {
            try await r2Client.createDirectory(prefix: cleanPath)
            await diskCache.invalidateListing()
            sendResponse(connection: connection, status: "201 Created", headers: [:], body: Data())
        } catch {
            sendResponse(connection: connection, status: "500 Internal Server Error", headers: [:], body: Data())
        }
    }

    private func handleDelete(connection: NWConnection, cleanPath: String) async {
        do {
            try await r2Client.deleteObject(key: cleanPath)
            await diskCache.invalidateListing()
            sendResponse(connection: connection, status: "204 No Content", headers: [:], body: Data())
        } catch {
            sendResponse(connection: connection, status: "500 Internal Server Error", headers: [:], body: Data())
        }
    }

    private func handleMove(connection: NWConnection, cleanPath: String, headers: [String: String]) async {
        guard let dest = headers["destination"], let destURL = URL(string: dest) else {
            sendResponse(connection: connection, status: "400 Bad Request", headers: [:], body: Data())
            return
        }

        var destKey = destURL.path.removingPercentEncoding ?? destURL.path
        if destKey.lowercased().hasPrefix("/sokovia") {
            destKey = String(destKey.dropFirst(8))
        }
        if destKey.hasPrefix("/") { destKey = String(destKey.dropFirst()) }

        do {
            try await r2Client.copyObject(fromKey: cleanPath, toKey: destKey)
            await diskCache.invalidateListing()
            sendResponse(connection: connection, status: "201 Created", headers: [:], body: Data())
        } catch {
            sendResponse(connection: connection, status: "500 Internal Server Error", headers: [:], body: Data())
        }
    }

    private func sendResponse(connection: NWConnection, status: String, headers: [String: String], body: Data) {
        var resp = "HTTP/1.1 \(status)\r\n"
        var finalHeaders = headers
        if finalHeaders["Content-Length"] == nil {
            finalHeaders["Content-Length"] = String(body.count)
        }
        finalHeaders["Connection"] = "close"

        for (k, v) in finalHeaders {
            resp += "\(k): \(v)\r\n"
        }
        resp += "\r\n"

        var fullData = Data(resp.utf8)
        fullData.append(body)

        connection.send(content: fullData, completion: .contentProcessed({ _ in
            connection.cancel()
        }))
    }
}
