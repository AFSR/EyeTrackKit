//
//  FixationDetector.swift
//
//
//  Identification by Dispersion Threshold (I-DT). A standard, low-cost
//  fixation/saccade classifier. See Salvucci & Goldberg, "Identifying
//  fixations and saccades in eye-tracking protocols" (ETRA 2000).
//
//  Maintains a sliding window of recent gaze points. While the window's
//  spatial dispersion stays below `dispersionThreshold` and its temporal
//  span exceeds `minimumFixationDuration`, the user is in a fixation. When
//  dispersion grows beyond the threshold, we emit the closing fixation and
//  the next sample starts a saccade.
//

import Foundation
import CoreGraphics

public final class FixationDetector {
    public struct Configuration {
        /// Maximum spatial dispersion (max-min on each axis, summed) for a
        /// window of points to still count as a fixation, in screen points.
        public var dispersionThreshold: CGFloat
        /// Minimum duration before a stable window is reported as a fixation.
        public var minimumFixationDuration: TimeInterval
        /// Discard buffered points older than this so the detector adapts to
        /// the actual frame rate.
        public var maxBufferDuration: TimeInterval

        public init(dispersionThreshold: CGFloat = 35,
                    minimumFixationDuration: TimeInterval = 0.1,
                    maxBufferDuration: TimeInterval = 1.0) {
            self.dispersionThreshold = dispersionThreshold
            self.minimumFixationDuration = minimumFixationDuration
            self.maxBufferDuration = maxBufferDuration
        }

        public static let `default` = Configuration()
    }

    public var configuration: Configuration

    private struct Sample {
        let point: CGPoint
        let time: Date
        let confidence: Float
    }

    private var window: [Sample] = []
    private var inFixation = false
    private var fixationStart: Date?
    private var fixationCentroid: CGPoint = .zero
    private var lastFixationPoint: CGPoint?

    public init(configuration: Configuration = .default) {
        self.configuration = configuration
    }

    public func reset() {
        window.removeAll(keepingCapacity: true)
        inFixation = false
        fixationStart = nil
        lastFixationPoint = nil
    }

    /// Feeds a new gaze sample. Returns 0 or 1 events triggered by this
    /// sample (a fixation closing, optionally followed by a saccade — the
    /// caller may receive both in successive calls).
    public func ingest(point: CGPoint, time: Date, confidence: Float) -> [TrackingEvent] {
        var events: [TrackingEvent] = []
        window.append(Sample(point: point, time: time, confidence: confidence))

        // Drop samples outside the buffer window.
        let cutoff = time.addingTimeInterval(-configuration.maxBufferDuration)
        while let first = window.first, first.time < cutoff {
            window.removeFirst()
        }

        let dispersion = currentDispersion()
        let span = window.last!.time.timeIntervalSince(window.first!.time)

        if dispersion <= configuration.dispersionThreshold,
           span >= configuration.minimumFixationDuration {
            // We are in a fixation.
            if !inFixation {
                inFixation = true
                fixationStart = window.first?.time ?? time
            }
            fixationCentroid = centroid()
        } else if inFixation {
            // Fixation just ended.
            let endTime = window.last?.time ?? time
            let start = fixationStart ?? endTime
            let duration = endTime.timeIntervalSince(start)
            let avgConfidence = window.map { $0.confidence }.reduce(0, +) / Float(max(1, window.count))
            events.append(.fixation(at: fixationCentroid,
                                    duration: duration,
                                    confidence: avgConfidence))
            if let last = lastFixationPoint {
                events.append(.saccade(from: last, to: fixationCentroid, duration: 0))
            }
            lastFixationPoint = fixationCentroid
            inFixation = false
            fixationStart = nil
            // Reset the window so the next fixation accumulates fresh.
            window.removeAll(keepingCapacity: true)
            window.append(Sample(point: point, time: time, confidence: confidence))
        }
        return events
    }

    private func currentDispersion() -> CGFloat {
        guard !window.isEmpty else { return 0 }
        var minX: CGFloat = .greatestFiniteMagnitude
        var maxX: CGFloat = -.greatestFiniteMagnitude
        var minY: CGFloat = .greatestFiniteMagnitude
        var maxY: CGFloat = -.greatestFiniteMagnitude
        for s in window {
            minX = min(minX, s.point.x); maxX = max(maxX, s.point.x)
            minY = min(minY, s.point.y); maxY = max(maxY, s.point.y)
        }
        return (maxX - minX) + (maxY - minY)
    }

    private func centroid() -> CGPoint {
        guard !window.isEmpty else { return .zero }
        var sx: CGFloat = 0
        var sy: CGFloat = 0
        for s in window { sx += s.point.x; sy += s.point.y }
        return CGPoint(x: sx / CGFloat(window.count), y: sy / CGFloat(window.count))
    }
}
