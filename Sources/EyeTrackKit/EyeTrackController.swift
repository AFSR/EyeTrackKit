//
//  EyeTrackController.swift
//
//
//  Created by Yuki Yamato on 2020/10/01.
//

import Foundation
import SwiftUI
import Combine
import ARKit
import SceneKit
import os

public final class EyeTrackController: ObservableObject {
    public struct Params {
        public var device: Device
        public var smoothingRange: Int
        public var blinkThreshold: Float
        public var isHidden: Bool

        public init(device: Device,
                    smoothingRange: Int,
                    blinkThreshold: Float,
                    isHidden: Bool = true) {
            self.device = device
            self.smoothingRange = smoothingRange
            self.blinkThreshold = blinkThreshold
            self.isHidden = isHidden
        }

        var description: [String: String] {
            ["device": "\(device.type.rawValue)",
             "smoothing_range": "\(smoothingRange)",
             "blink_threshold": "\(blinkThreshold)",
             "is_hidden": "\(isHidden)"]
        }
    }

    @Published public var eyeTrack: EyeTrack
    @Published public var isHidden: Bool

    private var cachedView: EyeTrackView?
    private var cancellable: AnyCancellable?
    private var params: Params

    private let logger = Logger(subsystem: "dev.ukitomato.EyeTrackKit", category: "EyeTrackController")

    public var onUpdate: (EyeTrackInfo?) -> Void {
        get { eyeTrack.onUpdate }
        set { eyeTrack.onUpdate = newValue }
    }

    public var onUpdateFrame: (CVPixelBuffer?) -> Void {
        get { eyeTrack.onUpdateFrame }
        set { eyeTrack.onUpdateFrame = newValue }
    }

    public var view: EyeTrackView {
        if let cached = cachedView { return cached }
        let v = EyeTrackView(isHidden: isHidden, eyeTrack: eyeTrack)
        cachedView = v
        return v
    }

    public init(device: Device,
                smoothingRange: Int,
                blinkThreshold: Float,
                isHidden: Bool? = true) {
        self.params = Params(device: device,
                             smoothingRange: smoothingRange,
                             blinkThreshold: blinkThreshold,
                             isHidden: isHidden ?? true)
        self.eyeTrack = EyeTrack(device: params.device,
                                 smoothingRange: params.smoothingRange,
                                 blinkThreshold: params.blinkThreshold)
        self.isHidden = params.isHidden
        bindEyeTrack()
        logger.debug("EyeTrackKit was initialized | \(self.params.description)")
    }

    private func bindEyeTrack() {
        cancellable = eyeTrack.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    public func start() {
        logger.debug("start eye tracking")
        cachedView?.start()
    }

    public func pause() {
        logger.debug("stop eye tracking")
        cachedView?.pause()
    }

    public func hide() {
        cachedView?.hide()
    }

    public func show() {
        cachedView?.show()
    }

    public func showRayHint() {
        eyeTrack.showRayHint()
    }

    public func hideRayHint() {
        eyeTrack.hideRayHint()
    }

    public func startRecord() {
        logger.debug("start to record scene video")
        view.startRecord()
    }

    public func stopRecord(finished: @escaping (URL) -> Void = { _ in },
                           isExport: Bool = false) {
        view.stopRecord(finished: finished, isExport: isExport)
        logger.debug("stop to record scene video")
    }

    public var currentInfo: EyeTrackInfo? { eyeTrack.info }

    /// Updates parameters in place where possible, recreating the underlying
    /// `EyeTrack` only when the device changes (since SceneKit nodes are tied
    /// to the device).
    public func reinit(device: Device? = nil,
                       smoothingRange: Int? = nil,
                       blinkThreshold: Float? = nil,
                       isHidden: Bool? = nil) {
        let deviceChanged = device != nil && device!.type != params.device.type
        if let device { params.device = device }
        if let smoothingRange { params.smoothingRange = smoothingRange }
        if let blinkThreshold { params.blinkThreshold = blinkThreshold }
        if let isHidden { params.isHidden = isHidden }
        self.isHidden = params.isHidden

        if deviceChanged {
            reset(params: params)
        } else {
            eyeTrack.smoothingRange = params.smoothingRange
            eyeTrack.blinkThreshold = params.blinkThreshold
            eyeTrack.resetFilters()
        }
    }

    public func reset(params: Params) {
        self.params = params
        eyeTrack = EyeTrack(device: params.device,
                            smoothingRange: params.smoothingRange,
                            blinkThreshold: params.blinkThreshold)
        isHidden = params.isHidden
        bindEyeTrack()
        cachedView = nil
        logger.debug("EyeTrackKit was reset | \(params.description)")
    }
}
