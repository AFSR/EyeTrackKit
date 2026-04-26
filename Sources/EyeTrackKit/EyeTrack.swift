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
    // Smoothed gaze position relative to the screen centre.
    @Published public private(set) var lookAtPosition: CGPoint = .zero
    // Smoothed gaze position relative to the top-left of the screen.
    @Published public private(set) var lookAtPoint: CGPoint = .zero

    @Published public var device: Device
    @Published public var face: Face
    @Published public private(set) var info: EyeTrackInfo?
    @Published public var isShowRayHint: Bool

    /// Tracking quality of the current frame in 0...1.
    @Published public private(set) var trackingConfidence: Float = 0

    public var blinkThreshold: Float
    public var smoothingRange: Int

    public var gazeEstimator: GazeEstimator
    private var ringBuffer: RingBuffer<CGPoint>
    private var runningSum: CGPoint = .zero

    private weak var sceneView: ARSCNView?

    public var onUpdate: (EyeTrackInfo?) -> Void = { _ in }
    public var onUpdateFrame: (CVPixelBuffer?) -> Void = { _ in }

    private let logger = Logger(subsystem: "dev.ukitomato.EyeTrackKit", category: "EyeTrack")

    public init(device: Device,
                smoothingRange: Int = 1,
                blinkThreshold: Float = 1.0,
                isShowRayHint: Bool = false,
                gazeEstimator: GazeEstimator = GazeEstimator()) {
        self.device = device
        self.face = Face(isShowRayHint: isShowRayHint)
        self.smoothingRange = max(1, smoothingRange)
        self.blinkThreshold = blinkThreshold
        self.isShowRayHint = isShowRayHint
        self.gazeEstimator = gazeEstimator
        self.ringBuffer = RingBuffer<CGPoint>(capacity: max(1, smoothingRange))
    }

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

    /// Resets the smoothing buffer and the Kalman filters. Call this when
    /// switching users or after a tracking interruption.
    public func resetFilters() {
        ringBuffer.reset()
        runningSum = .zero
        gazeEstimator.reset()
    }

    public func update(anchor: ARFaceAnchor) {
        face.update(anchor: anchor)

        let isClosed = face.leftEye.blink > blinkThreshold
                       && face.rightEye.blink > blinkThreshold
        if !isClosed {
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

    private func updateLookAtPosition(isTracked: Bool) {
        let sample = gazeEstimator.estimate(face: face, device: device, isTracked: isTracked)
        trackingConfidence = sample.confidence

        // Maintain a running sum over the ring buffer for an O(1) moving average.
        let evicted = ringBuffer.append(sample.point)
        runningSum.x += sample.point.x - (evicted?.x ?? 0)
        runningSum.y += sample.point.y - (evicted?.y ?? 0)
        let count = CGFloat(ringBuffer.count)

        let smoothed = CGPoint(x: runningSum.x / count, y: runningSum.y / count)
        lookAtPosition = smoothed
        lookAtPoint = CGPoint(
            x: smoothed.x + device.screenPointSize.width / 2,
            y: smoothed.y + device.screenPointSize.height / 2
        )
    }
}
