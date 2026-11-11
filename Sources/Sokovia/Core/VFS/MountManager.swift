import Foundation
import AppKit

public final class MountManager: @unchecked Sendable {
    public static let shared = MountManager()
    private init() {}

    public func getMountedVolumePath() -> String? {
        let task = Process()
        task.launchPath = "/sbin/mount"
        let pipe = Pipe()
        task.standardOutput = pipe
        try? task.run()
        task.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        for line in output.components(separatedBy: "\n") {
            if line.contains("127.0.0.1") || line.contains("localhost") || line.contains("Sokovia") {
                let parts = line.components(separatedBy: " on ")
                if parts.count >= 2 {
                    let mountPart = parts[1].components(separatedBy: " (")[0]
                    return mountPart.trimmingCharacters(in: .whitespaces)
                }
            }
        }
        return nil
    }

    public func isMounted(mountPath: String = "/Volumes/Sokovia") -> Bool {
        return getMountedVolumePath() != nil
    }

    public func mount(port: UInt16, mountPath: String = "/Volumes/Sokovia") throws {
        // Unmount any previous instance first
        if isMounted(mountPath: mountPath) {
            try? unmount(mountPath: mountPath)
            Thread.sleep(forTimeInterval: 0.5)
        }

        // Use macOS native Finder WebDAV mounter with /Sokovia mount point
        let hostName = "sokovia"

        let script = "tell application \"Finder\" to mount volume \"http://\(hostName):\(port)/Sokovia\""
        let proc = Process()
        proc.launchPath = "/usr/bin/osascript"
        proc.arguments = ["-e", script]
        try? proc.run()
        proc.waitUntilExit()

        // Wait up to 5 seconds for mount to appear
        for _ in 0..<10 {
            Thread.sleep(forTimeInterval: 0.5)
            if let actual = getMountedVolumePath() {
                // Apply custom volume icon if available
                let iconSource = "/Applications/Sokovia.app/Contents/Resources/AppIcon.icns"
                let targetIcon = "\(actual)/.VolumeIcon.icns"
                if FileManager.default.fileExists(atPath: iconSource) && !FileManager.default.fileExists(atPath: targetIcon) {
                    try? FileManager.default.copyItem(atPath: iconSource, toPath: targetIcon)
                    let task = Process()
                    task.launchPath = "/usr/bin/SetFile"
                    task.arguments = ["-a", "C", actual]
                    try? task.run()
                    task.waitUntilExit()
                }

                // Create a convenient symlink on the user desktop
                let desktopSymlink = (NSHomeDirectory() as NSString).appendingPathComponent("Desktop/Sokovia-Drive")
                try? FileManager.default.removeItem(atPath: desktopSymlink)
                try? FileManager.default.createSymbolicLink(atPath: desktopSymlink, withDestinationPath: actual)
                return
            }
        }
    }

    public func unmount(mountPath: String = "/Volumes/Sokovia") throws {
        if let actual = getMountedVolumePath() {
            let task = Process()
            task.launchPath = "/usr/sbin/diskutil"
            task.arguments = ["unmount", "force", actual]
            try? task.run()
            task.waitUntilExit()
        }

        // Also clean up any lingering 127.0.0.1 mounts
        let task2 = Process()
        task2.launchPath = "/usr/sbin/diskutil"
        task2.arguments = ["unmount", "force", "/Volumes/127.0.0.1"]
        try? task2.run()
        task2.waitUntilExit()

        let desktopSymlink = (NSHomeDirectory() as NSString).appendingPathComponent("Desktop/Sokovia-Drive")
        try? FileManager.default.removeItem(atPath: desktopSymlink)
    }

    public func openInFinder(mountPath: String = "/Volumes/Sokovia") {
        let target = getMountedVolumePath() ?? mountPath
        let url = URL(fileURLWithPath: target)
        NSWorkspace.shared.open(url)
    }
}
