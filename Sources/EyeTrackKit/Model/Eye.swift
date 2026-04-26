//
//  Eye.swift
//
//
//  Created by Yuki Yamato on 2020/10/01.
//

import Foundation
import UIKit
import SceneKit
import ARKit

/// Holds the per-eye SceneKit nodes and the latest gaze sample.
public final class Eye {
    public var lookAtPosition: CGPoint = .zero
    public var lookAtPoint: CGPoint = .zero
    public var blink: Float = 1.0
    public let node: SCNNode
    public let target: SCNNode

    /// Child node carrying the cone geometry. The original implementation
    /// stored the geometry on a child but updated it via `node.geometry`
    /// (the parent had none), so `showHint`/`hideHint` were silent no-ops.
    private let coneNode: SCNNode

    public private(set) var isShowRayHint: Bool

    public init(isShowRayHint: Bool = false) {
        self.isShowRayHint = isShowRayHint

        let geometry = SCNCone(topRadius: 0.005, bottomRadius: 0, height: 0.1)
        geometry.radialSegmentCount = 3
        geometry.firstMaterial?.diffuse.contents = isShowRayHint ? UIColor.red : UIColor.clear

        let cone = SCNNode()
        cone.geometry = geometry
        cone.eulerAngles.x = -.pi / 2
        cone.position.z = 0.1
        self.coneNode = cone

        let parent = SCNNode()
        parent.addChildNode(cone)
        self.node = parent

        self.target = SCNNode()
        self.target.position.z = 2
        self.node.addChildNode(self.target)
    }

    public func showHint() {
        coneNode.geometry?.firstMaterial?.diffuse.contents = UIColor.red
        isShowRayHint = true
    }

    public func hideHint() {
        coneNode.geometry?.firstMaterial?.diffuse.contents = UIColor.clear
        isShowRayHint = false
    }

    public func getDistanceToDevice() -> Float {
        (node.worldPosition - SCNVector3Zero).length()
    }

    /// Computes the screen-space hit point of the ray going from this eye
    /// through its gaze target, intersected with the virtual device plane.
    ///
    /// The previous implementation iterated over all hit-test results but
    /// only kept the last one, and recomputed `screenSize / 2` and
    /// `screenPointSize / 2` on every iteration. This version pulls the
    /// last result directly and precomputes the half-extents.
    public func hittingAt(device: Device) -> CGPoint {
        let results = device.node.hitTestWithSegment(
            from: target.worldPosition,
            to: node.worldPosition,
            options: nil
        )
        guard let result = results.last else {
            return lookAtPosition
        }

        let halfScreenWidth = device.screenSize.width / 2
        let halfScreenHeight = device.screenSize.height / 2
        let halfPointWidth = device.screenPointSize.width / 2
        let halfPointHeight = device.screenPointSize.height / 2

        let local = result.localCoordinates
        lookAtPosition = CGPoint(
            x: CGFloat(local.x) / halfScreenWidth * device.screenPointSize.width + device.compensation.x,
            y: CGFloat(local.y) / halfScreenHeight * device.screenPointSize.height + device.compensation.y
        )
        lookAtPoint = CGPoint(
            x: lookAtPosition.x + halfPointWidth,
            y: lookAtPosition.y + halfPointHeight
        )
        return lookAtPosition
    }
}
