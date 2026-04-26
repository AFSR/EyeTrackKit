//
//  EyeTrackInfo.swift
//
//
//  Created by Yuki Yamato on 2020/10/01.
//

import Foundation
import ARKit
import SceneKit

public struct EyeTrackInfo {
    public static let csvColumns: [String] = [
        "timestamp", "isTracked",
        "faceRotation-x", "faceRotation-y", "faceRotation-z", "faceRotation-w",
        "facePosition-x", "facePosition-y", "facePosition-z",
        "deviceRotation-x", "deviceRotation-y", "deviceRotation-z", "deviceRotation-w",
        "devicePosition-x", "devicePosition-y", "devicePosition-z",
        "rightEyePosition-x", "rightEyePosition-y", "rightEyePosition-z",
        "leftEyePosition-x", "leftEyePosition-y", "leftEyePosition-z",
        "rightEyeLookAtPosition-x", "rightEyeLookAtPosition-y", "rightEyeLookAtPosition-z",
        "leftEyeLookAtPosition-x", "leftEyeLookAtPosition-y", "leftEyeLookAtPosition-z",
        "rightEyeLookAtPoint-x", "rightEyeLookAtPoint-y",
        "leftEyeLookAtPoint-x", "leftEyeLookAtPoint-y",
        "centerEyeLookAtPoint-x", "centerEyeLookAtPoint-y",
        "rightEyeBlink", "leftEyeBlink",
        "rightEyeDistance", "leftEyeDistance"
    ]

    @available(*, deprecated, renamed: "csvColumns")
    public static var CSV_COLUMNS: [String] { csvColumns }

    public let timestamp: Date
    public let isTracked: Bool

    public let faceRotation: SCNVector4
    public let facePosition: SCNVector3

    public let devicePosition: SCNVector3
    public let deviceRotation: SCNVector4

    public let rightEyePosition: SCNVector3
    public let leftEyePosition: SCNVector3

    public let rightEyeLookAtPosition: SCNVector3
    public let leftEyeLookAtPosition: SCNVector3

    public let rightEyeLookAtPoint: CGPoint
    public let leftEyeLookAtPoint: CGPoint
    public let centerEyeLookAtPoint: CGPoint

    public let rightEyeBlink: Float
    public let leftEyeBlink: Float

    public let rightEyeDistance: Float
    public let leftEyeDistance: Float

    /// Tracking quality (0...1). Combines `ARFaceAnchor.isTracked` with the
    /// agreement between the multiple gaze estimators.
    public let trackingConfidence: Float

    // Backwards-compatible aliases for the typo-fixed properties.
    @available(*, deprecated, renamed: "faceRotation")
    public var faceRotaion: SCNVector4 { faceRotation }
    @available(*, deprecated, renamed: "rightEyePosition")
    public var rightEyePotision: SCNVector3 { rightEyePosition }
    @available(*, deprecated, renamed: "leftEyePosition")
    public var leftEyePotision: SCNVector3 { leftEyePosition }

    public init(face: Face,
                device: Device,
                lookAtPoint: CGPoint,
                isTracked: Bool,
                trackingConfidence: Float = 1.0) {
        self.timestamp = Date()
        self.isTracked = isTracked
        self.trackingConfidence = trackingConfidence

        self.faceRotation = face.node.worldOrientation
        self.facePosition = face.node.worldPosition
        self.deviceRotation = device.node.worldOrientation
        self.devicePosition = device.node.worldPosition
        self.rightEyePosition = face.rightEye.node.worldPosition
        self.leftEyePosition = face.leftEye.node.worldPosition

        self.rightEyeLookAtPosition = face.rightEye.target.worldPosition
        self.leftEyeLookAtPosition = face.leftEye.target.worldPosition

        self.rightEyeLookAtPoint = face.rightEye.lookAtPoint
        self.leftEyeLookAtPoint = face.leftEye.lookAtPoint
        self.centerEyeLookAtPoint = lookAtPoint

        self.rightEyeBlink = face.rightEye.blink
        self.leftEyeBlink = face.leftEye.blink

        self.rightEyeDistance = face.rightEye.getDistanceToDevice()
        self.leftEyeDistance = face.leftEye.getDistanceToDevice()
    }

    public var toCSV: [String] {
        var row = [String]()
        row.reserveCapacity(EyeTrackInfo.csvColumns.count)
        row.append(EyeTrackInfo.timestampFormatter.string(from: timestamp))
        row.append(String(isTracked))
        row.append(contentsOf: [
            String(faceRotation.x), String(faceRotation.y), String(faceRotation.z), String(faceRotation.w),
            String(facePosition.x), String(facePosition.y), String(facePosition.z),
            String(deviceRotation.x), String(deviceRotation.y), String(deviceRotation.z), String(deviceRotation.w),
            String(devicePosition.x), String(devicePosition.y), String(devicePosition.z),
            String(rightEyePosition.x), String(rightEyePosition.y), String(rightEyePosition.z),
            String(leftEyePosition.x), String(leftEyePosition.y), String(leftEyePosition.z),
            String(rightEyeLookAtPosition.x), String(rightEyeLookAtPosition.y), String(rightEyeLookAtPosition.z),
            String(leftEyeLookAtPosition.x), String(leftEyeLookAtPosition.y), String(leftEyeLookAtPosition.z),
        ])
        row.append(String(format: "%.8F", Float(rightEyeLookAtPoint.x)))
        row.append(String(format: "%.8F", Float(rightEyeLookAtPoint.y)))
        row.append(String(format: "%.8F", Float(leftEyeLookAtPoint.x)))
        row.append(String(format: "%.8F", Float(leftEyeLookAtPoint.y)))
        row.append(String(format: "%.8F", Float(centerEyeLookAtPoint.x)))
        row.append(String(format: "%.8F", Float(centerEyeLookAtPoint.y)))
        row.append(contentsOf: [
            String(rightEyeBlink), String(leftEyeBlink),
            String(rightEyeDistance), String(leftEyeDistance),
        ])
        return row
    }

    public func dateToString(date: Date) -> String {
        EyeTrackInfo.timestampFormatter.string(from: date)
    }

    /// Shared formatter — DateFormatter is expensive to allocate, the previous
    /// implementation created one per `EyeTrackInfo`, i.e. once per frame.
    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMddHHmmssSSSSS"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()
}

