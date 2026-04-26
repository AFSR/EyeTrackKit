//
//  TrackingEvent.swift
//
//
//  Semantic events emitted by EyeTrack. Apps subscribe via
//  `eyeTrack.eventStream` (AsyncStream) or `eyeTrack.eventPublisher`
//  (Combine).
//

import Foundation
import CoreGraphics

public enum CoordinateSpace: String, Codable, Sendable {
    /// UIKit-style top-left origin, points.
    case screenPoints
    /// 0...1 along each axis. Useful for size-independent UI.
    case normalized
}

public enum FaceState: String, Codable, Sendable {
    case tracked
    case lost
}

public enum BlinkSide: String, Codable, Sendable {
    case left
    case right
    case both
}

/// A point of regard event, emitted on every tracked frame.
public struct GazeEvent: Sendable {
    public let timestamp: Date
    public let point: CGPoint
    public let coordinateSpace: CoordinateSpace
    public let confidence: Float
    public let isCalibrated: Bool
    public let faceState: FaceState

    public init(timestamp: Date,
                point: CGPoint,
                coordinateSpace: CoordinateSpace,
                confidence: Float,
                isCalibrated: Bool,
                faceState: FaceState) {
        self.timestamp = timestamp
        self.point = point
        self.coordinateSpace = coordinateSpace
        self.confidence = confidence
        self.isCalibrated = isCalibrated
        self.faceState = faceState
    }
}

/// Higher-level semantic event stream. `GazeEvent`s arrive on a dedicated
/// stream; this enum carries everything else a UI typically reacts to.
public enum TrackingEvent: Sendable {
    case faceFound
    case faceLost
    case blink(BlinkSide)
    case fixation(at: CGPoint, duration: TimeInterval, confidence: Float)
    case saccade(from: CGPoint, to: CGPoint, duration: TimeInterval)
    /// Estimated drift between the live gaze and the calibration model.
    case calibrationDrift(estimatedError: CGFloat)
    case sessionInterrupted
    case sessionResumed
}
