//
//  CalibrationStore.swift
//
//
//  File-based persistence for calibration profiles. Apps can use the
//  shared default store or build their own with a custom directory
//  (e.g. an app-group container shared with an extension).
//

import Foundation

public final class CalibrationStore {
    public static let shared: CalibrationStore = {
        let docs = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("EyeTrackKit/Calibration", isDirectory: true)
        return CalibrationStore(directory: dir)
    }()

    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    // MARK: - Save / Load

    /// Encodes a profile to its file URL inside the store directory and
    /// returns that URL.
    @discardableResult
    public func save(_ profile: CalibrationProfile) throws -> URL {
        let url = fileURL(for: profile.id)
        try save(profile, to: url)
        return url
    }

    public func save(_ profile: CalibrationProfile, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        do {
            let data = try encoder.encode(profile)
            try data.write(to: url, options: [.atomic])
        } catch {
            throw CalibrationError.fileIO(underlying: error)
        }
    }

    public func load(id: UUID) throws -> CalibrationProfile {
        try load(from: fileURL(for: id))
    }

    public func load(from url: URL) throws -> CalibrationProfile {
        let data: Data
        do { data = try Data(contentsOf: url) }
        catch { throw CalibrationError.fileIO(underlying: error) }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let profile: CalibrationProfile
        do { profile = try decoder.decode(CalibrationProfile.self, from: data) }
        catch { throw CalibrationError.fileIO(underlying: error) }

        if profile.schemaVersion != CalibrationProfile.currentSchemaVersion {
            throw CalibrationError.schemaUnsupported(
                found: profile.schemaVersion,
                supported: CalibrationProfile.currentSchemaVersion
            )
        }
        return profile
    }

    // MARK: - Listing / Deletion

    public func list() -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []
    }

    /// Loads every valid profile in the store, sorted newest-first by
    /// `updatedAt`. Profiles with incompatible schema versions are skipped.
    public func loadAll() -> [CalibrationProfile] {
        list()
            .compactMap { try? load(from: $0) }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    public func delete(id: UUID) throws {
        let url = fileURL(for: id)
        do { try FileManager.default.removeItem(at: url) }
        catch { throw CalibrationError.fileIO(underlying: error) }
    }

    public func fileURL(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).json")
    }
}
