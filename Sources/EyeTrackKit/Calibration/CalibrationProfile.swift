//
//  CalibrationProfile.swift
//
//
//  Codable, persistable calibration data. The on-disk JSON layout is
//  versioned so future schema changes can fail fast instead of silently
//  loading stale data.
//

import Foundation
import CoreGraphics

/// A target the user is asked to look at during calibration.
public struct CalibrationTarget: Codable, Equatable {
    public let id: UUID
    /// Screen-space target point (top-left origin, points).
    public let point: CGPoint

    public init(id: UUID = UUID(), point: CGPoint) {
        self.id = id
        self.point = point
    }
}

/// One raw gaze sample collected while the user fixated on a target.
public struct CalibrationSample: Codable, Equatable {
    public let targetId: UUID
    /// Raw gaze point as produced by `GazeEstimator` *before* calibration.
    public let rawGaze: CGPoint
    public let timestamp: Date
    public let confidence: Float

    public init(targetId: UUID, rawGaze: CGPoint, timestamp: Date, confidence: Float) {
        self.targetId = targetId
        self.rawGaze = rawGaze
        self.timestamp = timestamp
        self.confidence = confidence
    }
}

public struct CalibrationProfile: Codable, Equatable {
    /// Bumped when the JSON schema changes in a non-backwards-compatible way.
    public static let currentSchemaVersion: Int = 1

    public let id: UUID
    public let schemaVersion: Int
    public let createdAt: Date
    public let updatedAt: Date

    /// Free-form user identifier (email, display name, profile id…). Optional.
    public var userId: String?
    public var displayName: String?

    /// DeviceType raw value at the time of calibration. Used to warn callers
    /// when a profile is loaded on a different device.
    public let deviceTypeRaw: String

    /// Screen size (in points) at calibration time. The transform is only
    /// valid for the same logical size.
    public let screenPointSize: CGSize

    public let targets: [CalibrationTarget]
    public let samples: [CalibrationSample]

    public let transform: AffineTransform2D
    public let residuals: [Double]
    /// Mean Euclidean residual across calibration targets, in screen points.
    public let meanResidual: Double
    /// Maximum residual.
    public let maxResidual: Double

    public init(
        id: UUID = UUID(),
        schemaVersion: Int = CalibrationProfile.currentSchemaVersion,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        userId: String? = nil,
        displayName: String? = nil,
        deviceTypeRaw: String,
        screenPointSize: CGSize,
        targets: [CalibrationTarget],
        samples: [CalibrationSample],
        transform: AffineTransform2D,
        residuals: [Double]
    ) {
        self.id = id
        self.schemaVersion = schemaVersion
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.userId = userId
        self.displayName = displayName
        self.deviceTypeRaw = deviceTypeRaw
        self.screenPointSize = screenPointSize
        self.targets = targets
        self.samples = samples
        self.transform = transform
        self.residuals = residuals
        self.meanResidual = residuals.isEmpty ? 0 : residuals.reduce(0, +) / Double(residuals.count)
        self.maxResidual = residuals.max() ?? 0
    }

    public var deviceType: DeviceType? { DeviceType(rawValue: deviceTypeRaw) }

    /// Applies the calibration transform to a raw gaze point.
    @inlinable
    public func apply(to point: CGPoint) -> CGPoint {
        transform.apply(to: point)
    }
}

public enum CalibrationError: Error, LocalizedError {
    case insufficientSamples(have: Int, need: Int)
    case fitFailed
    case schemaUnsupported(found: Int, supported: Int)
    case deviceMismatch(profile: String, current: String)
    case fileIO(underlying: Error)

    public var errorDescription: String? {
        switch self {
        case .insufficientSamples(let have, let need):
            return "Calibration needs \(need) samples, got \(have)."
        case .fitFailed:
            return "Calibration transform fit failed (collinear samples?)."
        case .schemaUnsupported(let found, let supported):
            return "Calibration file schema v\(found) is not supported (expected v\(supported))."
        case .deviceMismatch(let profile, let current):
            return "Calibration profile is for \(profile) but current device is \(current)."
        case .fileIO(let underlying):
            return "Calibration file I/O error: \(underlying.localizedDescription)"
        }
    }
}
