//
//  EyeTrack.swift
//
//
//  Created by Yuki Yamato on 2020/10/01.
//

import Foundation
import SwiftUI
import UIKit
import SceneKit
import ARKit
import os

public final class EyeTrack: ObservableObject {
    // MARK: - Published gaze state

    /// Smoothed, calibration-aware gaze position relative to the screen
    /// centre. Applied calibration profile (if any) is reflected here.
    @Published public private(set) var lookAtPosition: CGPoint = .zero

    /// Smoothed, calibration-aware gaze position in the configured
    /// `coordinateSpace`. Top-left origin in `.screenPoints`, 0...1 in
    /// `.normalized`.
    @Published public private(set) var lookAtPoint: CGPoint = .zero

    /// Smoothed gaze position *before* applying the calibration transform.
    /// Used by `Calibrator` to fit the transform from raw measurements.
    @Published public private(set) var uncalibratedLookAtPoint: CGPoint = .zero

    @Published public var device: Device
    @Published public var face: Face
    @Published public private(set) var info: EyeTrackInfo?
    @Published public var isShowRayHint: Bool

    /// Tracking quality of the current frame in 0...1.
    @Published public private(set) var trackingConfidence: Float = 0

    /// Currently applied calibration profile, if any. Setting this updates
    /// `lookAtPoint` immediately on the next frame.
    @Published public var calibrationProfile: CalibrationProfile?

    @Published public private(set) var faceState: FaceState = .lost

    // MARK: - Configuration

    public var blinkThreshold: Float
    public var smoothingRange: Int
    public var coordinateSpace: CoordinateSpace
    public var gazeEstimator: GazeEstimator
    public var fixationDetector: FixationDetector

    // MARK: - Event streams

    /// Per-frame gaze events (multicast). Each `gazeEvents.stream` call
    /// produces an independent `AsyncStream`.
    public let gazeEvents = EventDispatcher<GazeEvent>()

    /// Higher-level semantic events (blink, fixation, saccade, face lost…).
    public let events = EventDispatcher<TrackingEvent>()

    // MARK: - Internal state

    private var ringBuffer: RingBuffer<CGPoint>
    private var runningSum: CGPoint = .zero
    private weak var sceneView: ARSCNView?

    // Blink edge detection (rising-edge per side).
    private var leftBlinkActive = false
    private var rightBlinkActive = false

    public var onUpdate: (EyeTrackInfo?) -> Void = { _ in }
    public var onUpdateFrame: (CVPixelBuffer?) -> Void = { _ in }

    private let logger = Logger(subsystem: "dev.ukitomato.EyeTrackKit", category: "EyeTrack")

    // MARK: - Init

    public init(device: Device,
                smoothingRange: Int = 1,
                blinkThreshold: Float = 1.0,
                isShowRayHint: Bool = false,
                coordinateSpace: CoordinateSpace = .screenPoints,
                gazeEstimator: GazeEstimator = GazeEstimator(),
                fixationDetector: FixationDetector = FixationDetector()) {
        self.device = device
        self.face = Face(isShowRayHint: isShowRayHint)
        self.smoothingRange = max(1, smoothingRange)
        self.blinkThreshold = blinkThreshold
        self.isShowRayHint = isShowRayHint
        self.coordinateSpace = coordinateSpace
        self.gazeEstimator = gazeEstimator
        self.fixationDetector = fixationDetector
        self.ringBuffer = RingBuffer<CGPoint>(capacity: max(1, smoothingRange))
    }

    // MARK: - Public API

    public func registerSceneView(sceneView: ARSCNView) {
        self.sceneView = sceneView
        sceneView.scene.rootNode.addChildNode(face.node)
        sceneView.scene.rootNode.addChildNode(device.node)
    }

    public func showRayHint() {
        logger.debug("show raycast hint")
        isShowRayHint = true
        face.rightEye.showHint()
        face.leftEye.showHint()
    }

    public func hideRayHint() {
        logger.debug("hide raycast hint")
        isShowRayHint = false
        face.rightEye.hideHint()
        face.leftEye.hideHint()
    }

    public func resetFilters() {
        ringBuffer.reset()
        runningSum = .zero
        gazeEstimator.reset()
        fixationDetector.reset()
    }

    public func update(anchor: ARFaceAnchor) {
        face.update(anchor: anchor)
        emitFaceStateEvents(isTracked: anchor.isTracked)
        emitBlinkEvents()

        let bothClosed = face.leftEye.blink > blinkThreshold
                         && face.rightEye.blink > blinkThreshold
        if !bothClosed {
            updateLookAtPosition(isTracked: anchor.isTracked)
        }

        info = EyeTrackInfo(face: face,
                            device: device,
                            lookAtPoint: lookAtPoint,
                            isTracked: anchor.isTracked,
                            trackingConfidence: trackingConfidence)
        onUpdate(info)
    }

    public func updateFrame(pixelBuffer: CVPixelBuffer) {
        onUpdateFrame(pixelBuffer)
    }

    /// Emitted when a session interruption begins/ends (e.g. app backgrounded
    /// while tracking). Hosts should call these from the corresponding
    /// `ARSessionObserver` callbacks.
    public func sessionInterrupted() {
        events.send(.sessionInterrupted)
        resetFilters()
    }

    public func sessionResumed() {
        events.send(.sessionResumed)
    }

    // MARK: - Internals

    private func updateLookAtPosition(isTracked: Bool) {
        let sample = gazeEstimator.estimate(face: face, device: device, isTracked: isTracked)
        trackingConfidence = sample.confidence

        // Maintain a running sum over the ring buffer for an O(1) moving
        // average of the (uncalibrated) gaze.
        let evicted = ringBuffer.append(sample.point)
        runningSum.x += sample.point.x - (evicted?.x ?? 0)
        runningSum.y += sample.point.y - (evicted?.y ?? 0)
        let count = CGFloat(ringBuffer.count)

        let smoothed = CGPoint(x: runningSum.x / count, y: runningSum.y / count)
        lookAtPosition = smoothed

        // Convert to top-left-origin screen point.
        let screenPoint = CGPoint(
            x: smoothed.x + device.screenPointSize.width / 2,
            y: smoothed.y + device.screenPointSize.height / 2
        )
        uncalibratedLookAtPoint = screenPoint

        // Apply calibration if present, then convert to the configured space.
        let calibrated = calibrationProfile?.apply(to: screenPoint) ?? screenPoint
        lookAtPoint = convert(point: calibrated, to: coordinateSpace)

        emitGazeEvent(point: lookAtPoint, confidence: sample.confidence,
                       isCalibrated: calibrationProfile != nil)
        runFixationDetector(point: calibrated, confidence: sample.confidence)
    }

    private func convert(point: CGPoint, to space: CoordinateSpace) -> CGPoint {
        switch space {
        case .screenPoints:
            return point
        case .normalized:
            let w = device.screenPointSize.width
            let h = device.screenPointSize.height
            guard w > 0, h > 0 else { return point }
            return CGPoint(x: point.x / w, y: point.y / h)
        }
    }

    private func emitGazeEvent(point: CGPoint, confidence: Float, isCalibrated: Bool) {
        let event = GazeEvent(
            timestamp: Date(),
            point: point,
            coordinateSpace: coordinateSpace,
            confidence: confidence,
            isCalibrated: isCalibrated,
            faceState: faceState
        )
        gazeEvents.send(event)
    }

    private func emitFaceStateEvents(isTracked: Bool) {
        let newState: FaceState = isTracked ? .tracked : .lost
        if newState != faceState {
            faceState = newState
            events.send(newState == .tracked ? .faceFound : .faceLost)
        }
    }

    private func emitBlinkEvents() {
        let leftClosed = face.leftEye.blink > blinkThreshold
        let rightClosed = face.rightEye.blink > blinkThreshold

        // Rising-edge detection: emit only when the blink starts.
        if leftClosed && rightClosed && !(leftBlinkActive && rightBlinkActive) {
            events.send(.blink(.both))
        } else if leftClosed && !leftBlinkActive && !rightClosed {
            events.send(.blink(.left))
        } else if rightClosed && !rightBlinkActive && !leftClosed {
            events.send(.blink(.right))
        }
        leftBlinkActive = leftClosed
        rightBlinkActive = rightClosed
    }

    private func runFixationDetector(point: CGPoint, confidence: Float) {
        // The fixation detector works in screen-points space regardless of
        // the public `coordinateSpace`, so the dispersion threshold has a
        // device-independent meaning.
        let detectorEvents = fixationDetector.ingest(
            point: point,
            time: Date(),
            confidence: confidence
        )
        for ev in detectorEvents {
            events.send(ev)
        }
    }
}
