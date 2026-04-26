//
//  EyeTrackKitConfiguration.swift
//
//
//  Single Codable struct that bundles every tunable parameter. Apps can
//  ship a `default-config.json` resource and load it at startup, or let
//  users tweak parameters and persist them. The granular sub-configs
//  (`GazeEstimatorConfig`, `EyeTrackRecorder.Configuration`,
//  `FixationDetector.Configuration`) remain individually accessible.
//

import Foundation
import CoreGraphics

extension EyeTrackKit {
    public struct Configuration: Codable, Equatable {
        public var deviceTypeRaw: String
        public var smoothingRange: Int
        public var blinkThreshold: Float
        public var coordinateSpace: CoordinateSpace
        public var autoPauseInBackground: Bool

        public var gaze: GazeConfig
        public var fixation: FixationConfig
        public var recorder: RecorderConfig

        public init(
            deviceType: DeviceType = .iPhone15Pro,
            smoothingRange: Int = 5,
            blinkThreshold: Float = 0.5,
            coordinateSpace: CoordinateSpace = .screenPoints,
            autoPauseInBackground: Bool = true,
            gaze: GazeConfig = .init(),
            fixation: FixationConfig = .init(),
            recorder: RecorderConfig = .init()
        ) {
            self.deviceTypeRaw = deviceType.rawValue
            self.smoothingRange = smoothingRange
            self.blinkThreshold = blinkThreshold
            self.coordinateSpace = coordinateSpace
            self.autoPauseInBackground = autoPauseInBackground
            self.gaze = gaze
            self.fixation = fixation
            self.recorder = recorder
        }

        public var deviceType: DeviceType {
            DeviceType(rawValue: deviceTypeRaw) ?? .iPhone15Pro
        }

        public static let `default` = Configuration()

        // MARK: - Sub-configs (mirrors of the runtime Configuration types,
        // kept Codable here so the whole bundle is JSON-serializable).

        public struct GazeConfig: Codable, Equatable {
            public var processNoise: Double
            public var measurementNoise: Double
            public var outlierThreshold: CGFloat
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

            public var runtime: GazeEstimatorConfig {
                GazeEstimatorConfig(
                    processNoise: processNoise,
                    measurementNoise: measurementNoise,
                    outlierThreshold: outlierThreshold,
                    raycastWeight: raycastWeight,
                    nativeLookAtWeight: nativeLookAtWeight,
                    blendShapeWeight: blendShapeWeight
                )
            }
        }

        public struct FixationConfig: Codable, Equatable {
            public var dispersionThreshold: CGFloat
            public var minimumFixationDuration: TimeInterval
            public var maxBufferDuration: TimeInterval

            public init(dispersionThreshold: CGFloat = 35,
                        minimumFixationDuration: TimeInterval = 0.1,
                        maxBufferDuration: TimeInterval = 1.0) {
                self.dispersionThreshold = dispersionThreshold
                self.minimumFixationDuration = minimumFixationDuration
                self.maxBufferDuration = maxBufferDuration
            }

            public var runtime: FixationDetector.Configuration {
                FixationDetector.Configuration(
                    dispersionThreshold: dispersionThreshold,
                    minimumFixationDuration: minimumFixationDuration,
                    maxBufferDuration: maxBufferDuration
                )
            }
        }

        public struct RecorderConfig: Codable, Equatable {
            public enum CodecRaw: String, Codable { case h264, hevc }

            public var codec: CodecRaw
            public var videoBitRate: Int
            public var maxKeyFrameInterval: Int
            public var writeSidecarCSV: Bool

            public init(codec: CodecRaw = .hevc,
                        videoBitRate: Int = 6_000_000,
                        maxKeyFrameInterval: Int = 60,
                        writeSidecarCSV: Bool = false) {
                self.codec = codec
                self.videoBitRate = videoBitRate
                self.maxKeyFrameInterval = maxKeyFrameInterval
                self.writeSidecarCSV = writeSidecarCSV
            }

            public var runtime: EyeTrackRecorder.Configuration {
                EyeTrackRecorder.Configuration(
                    codec: codec == .hevc ? .hevc : .h264,
                    videoBitRate: videoBitRate,
                    maxKeyFrameInterval: maxKeyFrameInterval
                )
            }
        }

        // MARK: - I/O

        public func write(to url: URL) throws {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(self)
            try data.write(to: url, options: [.atomic])
        }

        public static func read(from url: URL) throws -> Configuration {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(Configuration.self, from: data)
        }
    }
}
