//
//  Device.swift
//
//
//  Created by Yuki Yamato on 2020/10/01.
//

import Foundation
import UIKit
import SceneKit
import ARKit

public enum DeviceType: String, CaseIterable {
    case iPad = "iPad"
    case iPadLandscape = "iPad Landscape"
    case iPadPro11 = "iPad Pro 11"
    case iPadPro12_9 = "iPad Pro 12.9"
    case iPhone11 = "iPhone11"
    case iPhone11Pro = "iPhone11Pro"
    case iPhone13 = "iPhone 13"
    case iPhone14Pro = "iPhone 14 Pro"
    case iPhone15Pro = "iPhone 15 Pro"
    case iPhone16Pro = "iPhone 16 Pro"
}

/// Holds the physical and logical screen dimensions of a target device,
/// used to convert eye-ray hit-tests into screen coordinates.
public final class Device {
    public let type: DeviceType
    public var screenSize: CGSize          // metres
    public var screenPointSize: CGSize     // points
    public var compensation: CGPoint

    public let node: SCNNode
    public let screenNode: SCNNode

    public init(screenSize: CGSize, screenPointSize: CGSize, compensation: CGPoint) {
        self.type = .iPad
        self.screenSize = screenSize
        self.screenPointSize = screenPointSize
        self.compensation = compensation
        self.node = SCNNode()
        self.screenNode = Device.makeScreenNode()
        self.node.addChildNode(self.screenNode)
    }

    public init(type: DeviceType) {
        self.type = type
        let spec = Device.specification(for: type)
        self.screenSize = spec.screenSize
        self.screenPointSize = spec.screenPointSize
        self.compensation = spec.compensation
        self.node = SCNNode()
        self.screenNode = Device.makeScreenNode()
        self.node.addChildNode(self.screenNode)
    }

    private static func makeScreenNode() -> SCNNode {
        let geometry = SCNPlane(width: 1, height: 1)
        geometry.firstMaterial?.isDoubleSided = true
        geometry.firstMaterial?.diffuse.contents = UIColor.green
        let node = SCNNode()
        node.geometry = geometry
        return node
    }

    private struct Spec {
        let screenSize: CGSize
        let screenPointSize: CGSize
        let compensation: CGPoint
    }

    private static func specification(for type: DeviceType) -> Spec {
        switch type {
        case .iPhone11:
            return Spec(screenSize: CGSize(width: 0.0757, height: 0.1509),
                        screenPointSize: CGSize(width: 414, height: 896),
                        compensation: CGPoint(x: 0, y: 414))
        case .iPhone11Pro:
            return Spec(screenSize: CGSize(width: 0.0714, height: 0.1440),
                        screenPointSize: CGSize(width: 375, height: 812),
                        compensation: CGPoint(x: 0, y: 375))
        case .iPhone13:
            return Spec(screenSize: CGSize(width: 0.0719, height: 0.1556),
                        screenPointSize: CGSize(width: 390, height: 844),
                        compensation: CGPoint(x: 0, y: 390))
        case .iPhone14Pro:
            return Spec(screenSize: CGSize(width: 0.0715, height: 0.1556),
                        screenPointSize: CGSize(width: 393, height: 852),
                        compensation: CGPoint(x: 0, y: 393))
        case .iPhone15Pro:
            return Spec(screenSize: CGSize(width: 0.0715, height: 0.1556),
                        screenPointSize: CGSize(width: 393, height: 852),
                        compensation: CGPoint(x: 0, y: 393))
        case .iPhone16Pro:
            return Spec(screenSize: CGSize(width: 0.0742, height: 0.1604),
                        screenPointSize: CGSize(width: 402, height: 874),
                        compensation: CGPoint(x: 0, y: 402))
        case .iPad:
            return Spec(screenSize: CGSize(width: 0.1785, height: 0.2476),
                        screenPointSize: CGSize(width: 834, height: 1194),
                        compensation: CGPoint(x: 0, y: 417))
        case .iPadLandscape:
            return Spec(screenSize: CGSize(width: 0.2476, height: 0.1785),
                        screenPointSize: CGSize(width: 1194, height: 834),
                        compensation: CGPoint(x: 417, y: 0))
        case .iPadPro11:
            return Spec(screenSize: CGSize(width: 0.1785, height: 0.2476),
                        screenPointSize: CGSize(width: 834, height: 1194),
                        compensation: CGPoint(x: 0, y: 417))
        case .iPadPro12_9:
            return Spec(screenSize: CGSize(width: 0.2148, height: 0.2807),
                        screenPointSize: CGSize(width: 1024, height: 1366),
                        compensation: CGPoint(x: 0, y: 512))
        }
    }
}
