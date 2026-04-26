//
//  Calibrator.swift
//
//
//  Drives a per-user calibration session: present N targets, collect raw
//  gaze samples per target, fit an affine transform, package a profile.
//
//  Typical use from a host app:
//
//      let calibrator = Calibrator(
//          eyeTrack: controller.eyeTrack,
//          targets: Calibrator.standardTargets(.nineGrid, in: screenSize)
//      )
//      calibrator.start()
//      // UI shows targets one-by-one driven by `currentTarget`
//      // App calls calibrator.advance() once each target has been fixated
//      let profile = try calibrator.finish()
//      try CalibrationStore.shared.save(profile)
//

import Foundation
import Combine
import CoreGraphics

public final class Calibrator: ObservableObject {
    public enum Layout {
        case fivePoint
        case nineGrid
        case sixteenGrid

        public var pointCount: Int {
            switch self {
            case .fivePoint: return 5
            case .nineGrid: return 9
            case .sixteenGrid: return 16
            }
        }
    }

    public struct Configuration {
        /// Number of raw samples to collect per target before advancing.
        public var samplesPerTarget: Int
        /// Initial discard window after a target is shown, to let the user
        /// saccade onto it before we trust the samples.
        public var settleDelay: TimeInterval
        /// Minimum gaze confidence (0...1) below which a sample is discarded.
        public var minimumConfidence: Float

        public init(samplesPerTarget: Int = 30,
                    settleDelay: TimeInterval = 0.4,
                    minimumConfidence: Float = 0.3) {
            self.samplesPerTarget = samplesPerTarget
            self.settleDelay = settleDelay
            self.minimumConfidence = minimumConfidence
        }

        public static let `default` = Configuration()
    }

    public enum State: Equatable {
        case idle
        case running(targetIndex: Int)
        case finished
        case cancelled
    }

    @Published public private(set) var state: State = .idle
    @Published public private(set) var collectedCount: Int = 0

    public let configuration: Configuration
    public let targets: [CalibrationTarget]

    private weak var eyeTrack: EyeTrack?
    private var samples: [CalibrationSample] = []
    private var currentTargetStartedAt: Date?
    private var cancellable: AnyCancellable?
    private let userId: String?
    private let displayName: String?

    public init(eyeTrack: EyeTrack,
                targets: [CalibrationTarget],
                configuration: Configuration = .default,
                userId: String? = nil,
                displayName: String? = nil) {
        self.eyeTrack = eyeTrack
        self.targets = targets
        self.configuration = configuration
        self.userId = userId
        self.displayName = displayName
    }

    // MARK: - Lifecycle

    public func start() {
        guard case .idle = state, !targets.isEmpty else { return }
        samples.removeAll()
        collectedCount = 0
        state = .running(targetIndex: 0)
        currentTargetStartedAt = Date()
        subscribeToGaze()
    }

    /// Advance to the next target. Call this when the host UI judges the
    /// user has had enough time on the current target (often `samplesPerTarget`
    /// has been collected, see `collectedCount`).
    public func advance() {
        guard case .running(let idx) = state else { return }
        let next = idx + 1
        if next >= targets.count {
            state = .finished
            cancellable?.cancel()
            cancellable = nil
        } else {
            state = .running(targetIndex: next)
            currentTargetStartedAt = Date()
            collectedCount = 0
        }
    }

    public func cancel() {
        cancellable?.cancel()
        cancellable = nil
        state = .cancelled
    }

    /// Fits an affine transform from the collected samples and packages a
    /// `CalibrationProfile`. Throws if not enough samples were collected.
    public func finish() throws -> CalibrationProfile {
        guard let eyeTrack else {
            throw CalibrationError.insufficientSamples(have: 0, need: 3)
        }
        guard samples.count >= 3 else {
            throw CalibrationError.insufficientSamples(have: samples.count, need: 3)
        }

        let pairs: [(raw: CGPoint, target: CGPoint)] = samples.compactMap { sample in
            guard let target = targets.first(where: { $0.id == sample.targetId })
            else { return nil }
            return (sample.rawGaze, target.point)
        }

        guard let fit = AffineTransform2D.fit(from: pairs) else {
            throw CalibrationError.fitFailed
        }

        return CalibrationProfile(
            userId: userId,
            displayName: displayName,
            deviceTypeRaw: eyeTrack.device.type.rawValue,
            screenPointSize: eyeTrack.device.screenPointSize,
            targets: targets,
            samples: samples,
            transform: fit.transform,
            residuals: fit.residuals
        )
    }

    /// Returns a standard layout of calibration points for a given screen
    /// size, with a 10% inset from the edges so the user does not have to
    /// look beyond the visible area.
    public static func standardTargets(_ layout: Layout,
                                       in screenSize: CGSize,
                                       inset: CGFloat = 0.1) -> [CalibrationTarget] {
        let xs: [CGFloat]
        let ys: [CGFloat]
        switch layout {
        case .fivePoint:
            // Center + 4 corners
            return [
                CGPoint(x: screenSize.width * inset, y: screenSize.height * inset),
                CGPoint(x: screenSize.width * (1 - inset), y: screenSize.height * inset),
                CGPoint(x: screenSize.width * 0.5, y: screenSize.height * 0.5),
                CGPoint(x: screenSize.width * inset, y: screenSize.height * (1 - inset)),
                CGPoint(x: screenSize.width * (1 - inset), y: screenSize.height * (1 - inset)),
            ].map { CalibrationTarget(point: $0) }
        case .nineGrid:
            xs = [inset, 0.5, 1 - inset]
            ys = [inset, 0.5, 1 - inset]
        case .sixteenGrid:
            xs = [inset, 0.333, 0.666, 1 - inset]
            ys = [inset, 0.333, 0.666, 1 - inset]
        }
        var points: [CalibrationTarget] = []
        for y in ys {
            for x in xs {
                points.append(CalibrationTarget(
                    point: CGPoint(x: screenSize.width * x, y: screenSize.height * y)
                ))
            }
        }
        return points
    }

    // MARK: - Sample collection

    private func subscribeToGaze() {
        guard let eyeTrack else { return }
        // Hook into the gaze event stream rather than `objectWillChange`,
        // which fires multiple times per frame. We sample uncalibrated gaze
        // on every published event so the fitted transform is built from
        // raw measurements (calibration cannot stack on itself).
        cancellable = eyeTrack.gazeEvents.publisher.sink { [weak self] _ in
            self?.collectIfApplicable()
        }
    }

    private func collectIfApplicable() {
        guard let eyeTrack,
              case .running(let targetIndex) = state,
              targetIndex < targets.count,
              let started = currentTargetStartedAt else { return }

        if Date().timeIntervalSince(started) < configuration.settleDelay { return }
        if eyeTrack.trackingConfidence < configuration.minimumConfidence { return }
        if collectedCount >= configuration.samplesPerTarget { return }

        let target = targets[targetIndex]
        // Use the *uncalibrated* smoothed point so stacked calibration is
        // impossible. EyeTrack exposes this as `uncalibratedLookAtPoint`.
        let raw = eyeTrack.uncalibratedLookAtPoint
        let sample = CalibrationSample(
            targetId: target.id,
            rawGaze: raw,
            timestamp: Date(),
            confidence: eyeTrack.trackingConfidence
        )
        samples.append(sample)
        collectedCount += 1
    }
}
