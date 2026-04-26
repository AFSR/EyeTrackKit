//
//  Face.swift
//
//
//  Created by Yuki Yamato on 2020/10/01.
//

import Foundation
import UIKit
import SceneKit
import ARKit

/// Holds the face SceneKit hierarchy and the latest sample of per-eye state.
public final class Face {
    public let node: SCNNode
    public let rightEye: Eye
    public let leftEye: Eye

    public var transform: simd_float4x4 = matrix_identity_float4x4

    /// Apple's native gaze target in face local space, copied from
    /// `ARFaceAnchor.lookAtPoint` on every update. Used by the multi-source
    /// gaze fusion in `GazeEstimator`.
    public var lookAtPointInFace: SIMD3<Float> = .zero

    /// Per-eye blend shape angles (radians, approximated from the 0...1 ARKit
    /// blend shape weights) used for the blend-shape direction estimator.
    public var leftEyeYaw: Float = 0
    public var leftEyePitch: Float = 0
    public var rightEyeYaw: Float = 0
    public var rightEyePitch: Float = 0

    public init(isShowRayHint: Bool = false) {
        self.node = SCNNode()
        self.rightEye = Eye(isShowRayHint: isShowRayHint)
        self.leftEye = Eye(isShowRayHint: isShowRayHint)
        self.node.addChildNode(self.leftEye.node)
        self.node.addChildNode(self.rightEye.node)
    }

    public func update(anchor: ARFaceAnchor) {
        transform = anchor.transform
        leftEye.node.simdTransform = anchor.leftEyeTransform
        rightEye.node.simdTransform = anchor.rightEyeTransform

        let blendShapes = anchor.blendShapes
        leftEye.blink = blendShapes[.eyeBlinkLeft]?.floatValue ?? 0.0
        rightEye.blink = blendShapes[.eyeBlinkRight]?.floatValue ?? 0.0

        // Apple's native eye-gaze hint (since iOS 12).
        lookAtPointInFace = anchor.lookAtPoint

        // Approximate eye angles from blend shapes. Apple does not document
        // the maximum angle, ~30° / 25° is a widely used calibration.
        let maxYaw: Float = .pi / 6   // 30°
        let maxPitch: Float = .pi / 7 // ~25°
        leftEyeYaw = ((blendShapes[.eyeLookOutLeft]?.floatValue ?? 0)
                       - (blendShapes[.eyeLookInLeft]?.floatValue ?? 0)) * maxYaw
        leftEyePitch = ((blendShapes[.eyeLookUpLeft]?.floatValue ?? 0)
                        - (blendShapes[.eyeLookDownLeft]?.floatValue ?? 0)) * maxPitch
        rightEyeYaw = ((blendShapes[.eyeLookInRight]?.floatValue ?? 0)
                       - (blendShapes[.eyeLookOutRight]?.floatValue ?? 0)) * maxYaw
        rightEyePitch = ((blendShapes[.eyeLookUpRight]?.floatValue ?? 0)
                         - (blendShapes[.eyeLookDownRight]?.floatValue ?? 0)) * maxPitch
    }

    /// Average distance from both eyes to the device origin.
    public func getDistanceToDevice() -> Float {
        (leftEye.getDistanceToDevice() + rightEye.getDistanceToDevice()) / 2
    }
}
