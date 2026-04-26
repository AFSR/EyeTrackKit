//
//  EyeTrackController.swift
//
//
//  Created by Yuki Yamato on 2020/10/01.
//

import Foundation
import SwiftUI
import Combine
import UIKit
import ARKit
import SceneKit
import os

public final class EyeTrackController: ObservableObject {
    public struct Params {
        public var device: Device
        public var smoothingRange: Int
        public var blinkThreshold: Float
        public var isHidden: Bool
        public var coordinateSpace: CoordinateSpace
        public var autoPauseInBackground: Bool

        public init(device: Device,
                    smoothingRange: Int,
                    blinkThreshold: Float,
                    isHidden: Bool = true,
                    coordinateSpace: CoordinateSpace = .screenPoints,
                    autoPauseInBackground: Bool = true) {
            self.device = device
            self.smoothingRange = smoothingRange
            self.blinkThreshold = blinkThreshold
            self.isHidden = isHidden
            self.coordinateSpace = coordinateSpace
            self.autoPauseInBackground = autoPauseInBackground
        }

        var description: [String: String] {
            ["device": "\(device.type.rawValue)",
             "smoothing_range": "\(smoothingRange)",
             "blink_threshold": "\(blinkThreshold)",
             "is_hidden": "\(isHidden)",
             "coordinate_space": coordinateSpace.rawValue,
             "auto_pause_bg": "\(autoPauseInBackground)"]
        }
    }

    @Published public var eyeTrack: EyeTrack
    @Published public var isHidden: Bool

    private var cachedView: EyeTrackView?
    private var cancellable: AnyCancellable?
    private var lifecycleObservers: [NSObjectProtocol] = []
    private var wasRunningBeforeBackground: Bool = false
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

    /// Convenience pass-throughs to the underlying `EyeTrack` event dispatchers.
    public var gazeEvents: EventDispatcher<GazeEvent> { eyeTrack.gazeEvents }
    public var events: EventDispatcher<TrackingEvent> { eyeTrack.events }

    public var calibrationProfile: CalibrationProfile? {
        get { eyeTrack.calibrationProfile }
        set { eyeTrack.calibrationProfile = newValue }
    }

    public var view: EyeTrackView {
        if let cached = cachedView { return cached }
        let v = EyeTrackView(isHidden: isHidden, eyeTrack: eyeTrack)
        cachedView = v
        return v
    }

    // MARK: - Init

    public init(device: Device,
                smoothingRange: Int,
                blinkThreshold: Float,
                isHidden: Bool? = true,
                coordinateSpace: CoordinateSpace = .screenPoints,
                autoPauseInBackground: Bool = true) {
        self.params = Params(device: device,
                             smoothingRange: smoothingRange,
                             blinkThreshold: blinkThreshold,
                             isHidden: isHidden ?? true,
                             coordinateSpace: coordinateSpace,
                             autoPauseInBackground: autoPauseInBackground)
        self.eyeTrack = EyeTrack(device: params.device,
                                 smoothingRange: params.smoothingRange,
                                 blinkThreshold: params.blinkThreshold,
                                 coordinateSpace: params.coordinateSpace)
        self.isHidden = params.isHidden
        bindEyeTrack()
        if params.autoPauseInBackground { setupLifecycleObservers() }
        logger.debug("EyeTrackKit was initialized | \(self.params.description)")
    }

    /// Initialize from a unified configuration bundle. The `device` argument
    /// overrides `configuration.deviceType` if provided (the configuration's
    /// device type is informational and used as a fallback).
    public convenience init(configuration: EyeTrackKit.Configuration,
                            device: Device? = nil,
                            isHidden: Bool = true) {
        let resolved = device ?? Device(type: configuration.deviceType)
        self.init(device: resolved,
                  smoothingRange: configuration.smoothingRange,
                  blinkThreshold: configuration.blinkThreshold,
                  isHidden: isHidden,
                  coordinateSpace: configuration.coordinateSpace,
                  autoPauseInBackground: configuration.autoPauseInBackground)
        self.eyeTrack.gazeEstimator.config = configuration.gaze.runtime
        self.eyeTrack.fixationDetector.configuration = configuration.fixation.runtime
    }

    deinit {
        for observer in lifecycleObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func bindEyeTrack() {
        cancellable = eyeTrack.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    // MARK: - Lifecycle

    public func start() {
        logger.debug("start eye tracking")
        cachedView?.start()
    }

    public func pause() {
        logger.debug("stop eye tracking")
        cachedView?.pause()
    }

    public func hide() { cachedView?.hide() }
    public func show() { cachedView?.show() }

    public func showRayHint() { eyeTrack.showRayHint() }
    public func hideRayHint() { eyeTrack.hideRayHint() }

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

    public func reinit(device: Device? = nil,
                       smoothingRange: Int? = nil,
                       blinkThreshold: Float? = nil,
                       isHidden: Bool? = nil,
                       coordinateSpace: CoordinateSpace? = nil) {
        let deviceChanged = device != nil && device!.type != params.device.type
        if let device { params.device = device }
        if let smoothingRange { params.smoothingRange = smoothingRange }
        if let blinkThreshold { params.blinkThreshold = blinkThreshold }
        if let isHidden { params.isHidden = isHidden }
        if let coordinateSpace { params.coordinateSpace = coordinateSpace }
        self.isHidden = params.isHidden

        if deviceChanged {
            reset(params: params)
        } else {
            eyeTrack.smoothingRange = params.smoothingRange
            eyeTrack.blinkThreshold = params.blinkThreshold
            eyeTrack.coordinateSpace = params.coordinateSpace
            eyeTrack.resetFilters()
        }
    }

    public func reset(params: Params) {
        self.params = params
        let oldProfile = eyeTrack.calibrationProfile
        eyeTrack = EyeTrack(device: params.device,
                            smoothingRange: params.smoothingRange,
                            blinkThreshold: params.blinkThreshold,
                            coordinateSpace: params.coordinateSpace)
        eyeTrack.calibrationProfile = oldProfile
        isHidden = params.isHidden
        bindEyeTrack()
        cachedView = nil
        logger.debug("EyeTrackKit was reset | \(params.description)")
    }

    // MARK: - Calibration

    /// Convenience to load and apply a calibration profile from disk.
    @discardableResult
    public func loadCalibrationProfile(from url: URL) throws -> CalibrationProfile {
        let profile = try CalibrationStore.shared.load(from: url)
        if profile.deviceTypeRaw != eyeTrack.device.type.rawValue {
            // Don't fail — we still apply, but warn the host so it can
            // surface a recalibration prompt.
            logger.warning("Loaded calibration is for \(profile.deviceTypeRaw, privacy: .public) but device is \(self.eyeTrack.device.type.rawValue, privacy: .public)")
        }
        eyeTrack.calibrationProfile = profile
        return profile
    }

    @discardableResult
    public func saveCurrentCalibrationProfile() throws -> URL? {
        guard let profile = eyeTrack.calibrationProfile else { return nil }
        return try CalibrationStore.shared.save(profile)
    }

    public func clearCalibration() {
        eyeTrack.calibrationProfile = nil
    }

    // MARK: - Lifecycle observers (auto pause/resume)

    private func setupLifecycleObservers() {
        let nc = NotificationCenter.default
        lifecycleObservers.append(
            nc.addObserver(forName: UIApplication.didEnterBackgroundNotification,
                           object: nil, queue: .main) { [weak self] _ in
                guard let self else { return }
                self.wasRunningBeforeBackground = self.cachedView != nil
                self.pause()
            }
        )
        lifecycleObservers.append(
            nc.addObserver(forName: UIApplication.willEnterForegroundNotification,
                           object: nil, queue: .main) { [weak self] _ in
                guard let self, self.wasRunningBeforeBackground else { return }
                self.start()
                self.eyeTrack.sessionResumed()
            }
        )
    }
}
