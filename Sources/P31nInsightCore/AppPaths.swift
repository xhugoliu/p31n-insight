import Foundation

public enum AppPaths {
    public static var applicationSupportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("P31n Insight", isDirectory: true)
    }

    public static var databaseURL: URL {
        applicationSupportDirectory.appendingPathComponent("p31n-insight.sqlite3")
    }

    public static var exportsDirectory: URL {
        applicationSupportDirectory.appendingPathComponent("Exports", isDirectory: true)
    }

    public static func ensureDirectories() throws {
        try FileManager.default.createDirectory(at: applicationSupportDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: exportsDirectory, withIntermediateDirectories: true)
    }
}
