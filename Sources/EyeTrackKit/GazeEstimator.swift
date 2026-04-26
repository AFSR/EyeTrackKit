//
//  GazeEstimator.swift
//
//
//  Multi-source gaze fusion for EyeTrackKit.
//
//  All three estimators below derive from the TrueDepth camera (the same
//  hardware that powers Face ID): ARKit consumes the IR dot pattern depth
//  internally and exposes the result as `ARFaceAnchor`. We do not get
//  separate access to the dot projector, but we exploit every signal Apple
//  surfaces from it:
//
//    1. Geometric raycast (legacy method): a ray traced from each pupil
//       through the gaze target node, intersected with the virtual screen.
//    2. Apple's `ARFaceAnchor.lookAtPoint`: Apple's own gaze estimate in
//       face-local space, projected to screen.
//    3. Blend-shape eye angles: per-eye yaw/pitch reconstructed from the
//       eyeLookIn/Out/Up/Down blend shapes, projected through the eye
//       transform onto the screen.
//
//  Each estimate is fed into a per-axis Kalman filter, then combined with
//  weights that reflect the per-frame agreement between sources. Outlying
//  estimators are down-weighted so a single jittery source does not pull
//  the result.
//

import Foundation
import ARKit
import SceneKit
import simd

public struct GazeEstimatorConfig {
    /// Process noise of the per-axis Kalman filters. Higher = more reactive,
    /// less smooth.
    public var processNoise: Double
    /// Measurement noise of the per-axis Kalman filters. Higher = more
    /// smoothing, more latency.
    public var measurementNoise: Double
    /// Maximum gaze disagreement (in screen points) before an estimator is
    /// considered an outlier and down-weighted.
    public var outlierThreshold: CGFloat
    /// Per-source weights before agreement-based reweighting.
    public var raycastWeight: Double
    public var nativeLookAtWeight: Double
    public var blendShapeWeight: Double

    public init(processNoise: Double = 5e-3,
                measurementNoise: Double = 8e-2,
                outlierThreshold: CGFloat = 120,
                raycastWeight: Double = 0.5,
                nativeLookAtWeight: Double = 0.35,
                blendShapeWeight: Double = 0.15) {
        self.processNoise = processNoise
        self.measurementNoise = measurementNoise
        self.outlierThreshold = outlierThreshold
        self.raycastWeight = raycastWeight
        self.nativeLookAtWeight = nativeLookAtWeight
        self.blendShapeWeight = blendShapeWeight
    }

    public static let `default` = GazeEstimatorConfig()
}

public struct GazeSample {
    public let point: CGPoint
    public let confidence: Float
}

public final class GazeEstimator {
    public var config: GazeEstimatorConfig {
        didSet { configureFilters() }
    }

    private var filterX: KalmanFilter1D
    private var filterY: KalmanFilter1D

    public init(config: GazeEstimatorConfig = .default) {
        self.config = config
        self.filterX = KalmanFilter1D(processNoise: config.processNoise,
                                      measurementNoise: config.measurementNoise)
        self.filterY = KalmanFilter1D(processNoise: config.processNoise,
                                      measurementNoise: config.measurementNoise)
    }

    public func reset() {
        filterX.reset()
        filterY.reset()
        configureFilters()
    }

    private func configureFilters() {
        filterX.processNoise = config.processNoise
        filterX.measurementNoise = config.measurementNoise
        filterY.processNoise = config.processNoise
        filterY.measurementNoise = config.measurementNoise
    }

    /// Fuses all three gaze sources for the current frame and returns the
    /// filtered screen-space gaze point with a quality estimate in 0...1.
    public func estimate(face: Face, device: Device, isTracked: Bool) -> GazeSample {
        let raycast = raycastEstimate(face: face, device: device)
        let native = nativeLookAtEstimate(face: face, device: device)
        let blend = blendShapeEstimate(face: face, device: device)

        let estimates = [raycast, native, blend]
        let weights = computeWeights(for: estimates)
        let fused = weightedAverage(points: estimates, weights: weights)

        let smoothed = CGPoint(
            x: CGFloat(filterX.update(Double(fused.x))),
            y: CGFloat(filterY.update(Double(fused.y)))
        )

        let agreement = sourceAgreement(estimates: estimates)
        let confidence = isTracked ? agreement : agreement * 0.5
        return GazeSample(point: smoothed, confidence: confidence)
    }

    // MARK: - Sources

    /// Geometric raycast through each pupil — preserves the original behaviour
    /// of EyeTrackKit. The two per-eye points are averaged (with the y axis
    /// flipped to match UIKit's coordinate system).
    private func raycastEstimate(face: Face, device: Device) -> CGPoint {
        let r = face.rightEye.hittingAt(device: device)
        let l = face.leftEye.hittingAt(device: device)
        return CGPoint(x: (r.x + l.x) / 2, y: -(r.y + l.y) / 2)
    }

    /// Projects `ARFaceAnchor.lookAtPoint` (face local space) through the
    /// face transform onto the virtual screen plane.
    private func nativeLookAtEstimate(face: Face, device: Device) -> CGPoint {
        let lookAtFace = SIMD4<Float>(face.lookAtPointInFace, 1)
        let lookAtWorld4 = face.transform * lookAtFace
        let lookAtWorld = SCNVector3(lookAtWorld4.x, lookAtWorld4.y, lookAtWorld4.z)

        let eyeOriginWorld = midpoint(face.leftEye.node.worldPosition,
                                      face.rightEye.node.worldPosition)
        return projectRayToScreen(from: eyeOriginWorld, to: lookAtWorld, device: device)
    }

    /// Builds a gaze ray from each eye using the blend-shape yaw/pitch angles
    /// and intersects it with the screen plane.
    private func blendShapeEstimate(face: Face, device: Device) -> CGPoint {
        let r = blendShapeRay(eye: face.rightEye, yaw: face.rightEyeYaw,
                              pitch: face.rightEyePitch, device: device)
        let l = blendShapeRay(eye: face.leftEye, yaw: face.leftEyeYaw,
                              pitch: face.leftEyePitch, device: device)
        return CGPoint(x: (r.x + l.x) / 2, y: (r.y + l.y) / 2)
    }

    private func blendShapeRay(eye: Eye, yaw: Float, pitch: Float, device: Device) -> CGPoint {
        // Forward direction in eye-local space, rotated by yaw / pitch.
        let cy = cos(yaw), sy = sin(yaw)
        let cp = cos(pitch), sp = sin(pitch)
        let dirLocal = SIMD3<Float>(sy * cp, sp, -cy * cp)

        let eyeTransform = eye.node.simdWorldTransform
        let dirWorld = simd_normalize((eyeTransform * SIMD4<Float>(dirLocal, 0)).xyz)
        let originWorld = SIMD3<Float>(eyeTransform.columns.3.x,
                                       eyeTransform.columns.3.y,
                                       eyeTransform.columns.3.z)
        let target = originWorld + dirWorld * 2.0

        return projectRayToScreen(
            from: SCNVector3(originWorld.x, originWorld.y, originWorld.z),
            to: SCNVector3(target.x, target.y, target.z),
            device: device
        )
    }

    private func projectRayToScreen(from: SCNVector3, to: SCNVector3, device: Device) -> CGPoint {
        let results = device.node.hitTestWithSegment(from: to, to: from, options: nil)
        guard let hit = results.last else { return .zero }
        let local = hit.localCoordinates
        let halfW = device.screenSize.width / 2
        let halfH = device.screenSize.height / 2
        let x = CGFloat(local.x) / halfW * device.screenPointSize.width + device.compensation.x
        let y = CGFloat(local.y) / halfH * device.screenPointSize.height + device.compensation.y
        return CGPoint(x: x, y: -y)
    }

    // MARK: - Fusion

    private func computeWeights(for estimates: [CGPoint]) -> [Double] {
        let base = [config.raycastWeight, config.nativeLookAtWeight, config.blendShapeWeight]
        // Median-based outlier rejection: down-weight estimates that are far
        // from the median of the others.
        let xs = estimates.map { $0.x }.sorted()
        let ys = estimates.map { $0.y }.sorted()
        let medianX = xs[xs.count / 2]
        let medianY = ys[ys.count / 2]

        var weights = base
        for i in 0..<estimates.count {
            let dx = estimates[i].x - medianX
            let dy = estimates[i].y - medianY
            let dist = (dx * dx + dy * dy).squareRoot()
            if dist > config.outlierThreshold {
                let attenuation = Double(config.outlierThreshold / dist)
                weights[i] *= attenuation
            }
        }
        let sum = weights.reduce(0, +)
        guard sum > 0 else { return base }
        return weights.map { $0 / sum }
    }

    private func weightedAverage(points: [CGPoint], weights: [Double]) -> CGPoint {
        var x: Double = 0
        var y: Double = 0
        for i in 0..<points.count {
            x += Double(points[i].x) * weights[i]
            y += Double(points[i].y) * weights[i]
        }
        return CGPoint(x: x, y: y)
    }

    /// Returns 1.0 when all estimates agree perfectly, decaying toward 0 as
    /// disagreement grows beyond the outlier threshold.
    private func sourceAgreement(estimates: [CGPoint]) -> Float {
        guard estimates.count > 1 else { return 1 }
        var maxDist: CGFloat = 0
        for i in 0..<estimates.count {
            for j in (i + 1)..<estimates.count {
                let dx = estimates[i].x - estimates[j].x
                let dy = estimates[i].y - estimates[j].y
                maxDist = max(maxDist, (dx * dx + dy * dy).squareRoot())
            }
        }
        let normalized = min(1, Float(maxDist / config.outlierThreshold))
        return 1 - normalized
    }

    private func midpoint(_ a: SCNVector3, _ b: SCNVector3) -> SCNVector3 {
        SCNVector3((a.x + b.x) / 2, (a.y + b.y) / 2, (a.z + b.z) / 2)
    }
}

private extension SIMD4 where Scalar == Float {
    var xyz: SIMD3<Float> { SIMD3(x, y, z) }
}
