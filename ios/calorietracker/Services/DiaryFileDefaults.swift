import Foundation
import os

/// `UserDefaults` that keeps the food diary in a file instead of the defaults plist.
///
/// iOS refuses to store 4 MiB or more in one app's defaults, and every `FoodEntry`
/// ever logged lives in the single `foodEntries` blob, so a long diary would hit the
/// cap and stop saving. This subclass sends that key to
/// `Application Support/Diary/foodEntries.json` and passes every other key through,
/// so `FoodStore`, `PersistedBlobGuard` and iCloud backup and restore keep working
/// unchanged against a `UserDefaults`.
///
/// * First read moves an existing defaults blob into the file, verifies the copy,
///   and only then removes the old key.
/// * A blob that shows up in defaults later (an iCloud restore, an older build)
///   is newer than the file: it replaces the file, and the old file is kept aside.
/// * A file with no marker in defaults means the defaults domain was wiped (UI test
///   reset); the file is kept aside and the diary reads as empty.
/// * A file that exists but cannot be read is never overwritten.
nonisolated final class DiaryFileDefaults: UserDefaults, @unchecked Sendable {
    static let diaryKey = "foodEntries"
    /// Set in the defaults plist whenever the file holds the diary.
    static let markerKey = "fork.foodEntriesInFile"

    static let shared: DiaryFileDefaults = DiaryFileDefaults(directory: defaultDirectory())!

    let fileURL: URL
    private let archiveDirectory: URL
    /// Recursive: `UserDefaults` implements some calls by calling others (removing a key
    /// sets it to nil), and those land back in these overrides on the same thread.
    private let lock = NSRecursiveLock()
    /// Non-zero while this class calls `super`; overrides reached from inside the
    /// base class then pass straight through instead of acting on the file.
    private var passthroughDepth = 0
    private let logger = Logger(subsystem: "ai.fud.calorietracker", category: "DiaryFile")
    /// Bytes as last read from or written to the file; nil when not loaded yet.
    private var cached: Data?
    private var isLoaded = false
    /// True while the file exists but could not be read; writes are refused.
    private var isUnreadable = false

    static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Diary", isDirectory: true)
    }

    /// `suiteName` nil is the app's standard domain.
    init?(suiteName: String? = nil, directory: URL) {
        fileURL = directory.appendingPathComponent("\(Self.diaryKey).json")
        archiveDirectory = directory.appendingPathComponent("Archive", isDirectory: true)
        super.init(suiteName: suiteName)
    }

    // MARK: - UserDefaults overrides

    override func object(forKey defaultName: String) -> Any? {
        guard defaultName == Self.diaryKey else { return super.object(forKey: defaultName) }
        lock.lock(); defer { lock.unlock() }
        guard passthroughDepth == 0 else { return super.object(forKey: defaultName) }
        if let other = adoptDefaultsBlob() { return other }
        return cached
    }

    override func data(forKey defaultName: String) -> Data? {
        guard defaultName == Self.diaryKey else { return super.data(forKey: defaultName) }
        return object(forKey: defaultName) as? Data
    }

    override func set(_ value: Any?, forKey defaultName: String) {
        guard defaultName == Self.diaryKey else { return super.set(value, forKey: defaultName) }
        lock.lock(); defer { lock.unlock() }
        guard passthroughDepth == 0 else { return super.set(value, forKey: defaultName) }
        guard let value else { return removeDiary() }
        guard let data = value as? Data else {
            // Not a diary blob. Leave it in defaults so the blob guard sees and quarantines it.
            passthrough { super.set(value, forKey: defaultName) }
            return
        }
        _ = adoptDefaultsBlob()
        guard !isUnreadable else {
            logger.fault("Refusing to overwrite an unreadable diary file")
            return
        }
        if writeFile(data) {
            passthrough { super.removeObject(forKey: Self.diaryKey) }
        }
    }

    override func removeObject(forKey defaultName: String) {
        guard defaultName == Self.diaryKey else { return super.removeObject(forKey: defaultName) }
        lock.lock(); defer { lock.unlock() }
        guard passthroughDepth == 0 else { return super.removeObject(forKey: defaultName) }
        _ = adoptDefaultsBlob()
        removeDiary()
    }

    override func dictionaryRepresentation() -> [String: Any] {
        lock.lock(); defer { lock.unlock() }
        var values = passthrough { super.dictionaryRepresentation() }
        values.removeValue(forKey: Self.markerKey)
        if let diary = object(forKey: Self.diaryKey) {
            values[Self.diaryKey] = diary
        }
        return values
    }

    // MARK: - File handling (callers hold `lock`)

    /// Loads the file on first use and moves any blob found in defaults into it.
    /// Returns a non-`Data` defaults value untouched so the caller can surface it.
    private func adoptDefaultsBlob() -> Any? {
        if !isLoaded { loadFile() }
        guard let blob = passthrough({ super.object(forKey: Self.diaryKey) }) else { return nil }
        guard let data = blob as? Data else { return blob }
        if isUnreadable {
            logger.fault("Diary blob found in defaults while the diary file is unreadable; leaving both in place")
            return data
        }
        if cached != nil { archiveFile(reason: "replaced") }
        if writeFile(data), readBack() == data {
            passthrough { super.removeObject(forKey: Self.diaryKey) }
            logger.notice("Moved the diary blob (\(data.count) bytes) from defaults into the diary file")
        } else {
            logger.fault("Could not move the diary blob into the file; keeping it in defaults")
            return data
        }
        return nil
    }

    private func loadFile() {
        isLoaded = true
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            cached = nil
            return
        }
        guard passthrough({ super.bool(forKey: Self.markerKey) }) else {
            // The file outlived the defaults domain it belonged to.
            archiveFile(reason: "orphaned")
            cached = nil
            return
        }
        if let data = readBack() {
            cached = data
            isUnreadable = false
        } else {
            logger.fault("Diary file exists but cannot be read; writes are blocked")
            cached = nil
            isUnreadable = true
            isLoaded = false // try again next time
        }
    }

    private func passthrough<T>(_ body: () -> T) -> T {
        passthroughDepth += 1
        defer { passthroughDepth -= 1 }
        return body()
    }

    private func readBack() -> Data? {
        try? Data(contentsOf: fileURL)
    }

    @discardableResult
    private func writeFile(_ data: Data) -> Bool {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            cached = data
            isLoaded = true
            passthrough { super.set(true, forKey: Self.markerKey) }
            return true
        } catch {
            logger.fault("Diary file write failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private func removeDiary() {
        guard !isUnreadable else {
            logger.fault("Refusing to remove an unreadable diary file")
            return
        }
        try? FileManager.default.removeItem(at: fileURL)
        passthrough {
            super.removeObject(forKey: Self.diaryKey)
            super.removeObject(forKey: Self.markerKey)
        }
        cached = nil
        isLoaded = true
    }

    /// Moves the current file aside, never deleting it.
    private func archiveFile(reason: String) {
        let manager = FileManager.default
        guard manager.fileExists(atPath: fileURL.path) else { return }
        do {
            try manager.createDirectory(at: archiveDirectory, withIntermediateDirectories: true)
            let stamp = Int(Date.now.timeIntervalSince1970 * 1000)
            var target = archiveDirectory.appendingPathComponent("\(Self.diaryKey).\(reason)-\(stamp).json")
            var attempt = 0
            while manager.fileExists(atPath: target.path) {
                attempt += 1
                target = archiveDirectory.appendingPathComponent("\(Self.diaryKey).\(reason)-\(stamp)-\(attempt).json")
            }
            try manager.moveItem(at: fileURL, to: target)
            logger.notice("Kept the \(reason, privacy: .public) diary file as \(target.lastPathComponent, privacy: .public)")
        } catch {
            logger.fault("Could not archive the diary file: \(error.localizedDescription, privacy: .public)")
        }
    }
}

extension UserDefaults {
    /// The standard defaults with the food diary stored in a file.
    nonisolated static var diary: UserDefaults { DiaryFileDefaults.shared }
}
