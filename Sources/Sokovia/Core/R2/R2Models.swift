import Foundation

public struct S3ObjectItem: @unchecked Sendable, Identifiable {
    public var id: String { key }
    public let key: String
    public let size: Int64
    public let lastModified: Date
    public let etag: String
    public let isDirectory: Bool

    public var fileName: String {
        let trimmed = isDirectory ? String(key.dropLast()) : key
        return (trimmed as NSString).lastPathComponent
    }

    public init(key: String, size: Int64, lastModified: Date, etag: String, isDirectory: Bool) {
        self.key = key
        self.size = size
        self.lastModified = lastModified
        self.etag = etag
        self.isDirectory = isDirectory
    }
}

public final class S3ListObjectsParser: NSObject, XMLParserDelegate, @unchecked Sendable {
    public private(set) var objects: [S3ObjectItem] = []
    public private(set) var commonPrefixes: [String] = []
    public private(set) var isTruncated: Bool = false
    public private(set) var nextContinuationToken: String?

    private var currentElement: String = ""
    private var currentText: String = ""
    
    // In Contents
    private var insideContents: Bool = false
    private var insideCommonPrefixes: Bool = false
    
    private var currentKey: String = ""
    private var currentSize: Int64 = 0
    private var currentLastModified: Date = Date()
    private var currentETag: String = ""

    private let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    
    private let iso8601Standard: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    public func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        currentElement = elementName
        currentText = ""
        
        if elementName == "Contents" {
            insideContents = true
            currentKey = ""
            currentSize = 0
            currentLastModified = Date()
            currentETag = ""
        } else if elementName == "CommonPrefixes" {
            insideCommonPrefixes = true
        }
    }

    public func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    public func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let trimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)

        if insideContents {
            switch elementName {
            case "Key":
                currentKey = trimmed
            case "Size":
                currentSize = Int64(trimmed) ?? 0
            case "LastModified":
                if let date = iso8601Formatter.date(from: trimmed) ?? iso8601Standard.date(from: trimmed) {
                    currentLastModified = date
                }
            case "ETag":
                currentETag = trimmed.replacingOccurrences(of: "\"", with: "")
            case "Contents":
                insideContents = false
                let isDir = currentKey.hasSuffix("/")
                objects.append(S3ObjectItem(
                    key: currentKey,
                    size: currentSize,
                    lastModified: currentLastModified,
                    etag: currentETag,
                    isDirectory: isDir
                ))
            default:
                break
            }
        } else if insideCommonPrefixes {
            if elementName == "Prefix" {
                commonPrefixes.append(trimmed)
            } else if elementName == "CommonPrefixes" {
                insideCommonPrefixes = false
            }
        } else {
            if elementName == "IsTruncated" {
                isTruncated = trimmed.lowercased() == "true"
            } else if elementName == "NextContinuationToken" {
                nextContinuationToken = trimmed
            }
        }
    }
}
