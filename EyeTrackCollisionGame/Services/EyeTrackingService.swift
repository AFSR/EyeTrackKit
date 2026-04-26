//
//  EyeTrackingService.swift
//
//  Wraps `EyeTrackController` from EyeTrackKit with app-level concerns:
//  authorization, device auto-detection, calibration profile lifecycle,
//  and a single shared instance the SwiftUI view tree consumes via
//  `@EnvironmentObject`.
//

import Foundation
import SwiftUI
import UIKit
import EyeTrackKit

@MainActor
final class EyeTrackingService: ObservableObject {
    enum AuthorizationState: Equatable {
        case unknown
        case authorized
        case denied(reason: String)
        case unsupported
    }

    @Published private(set) var authorizationState: AuthorizationState = .unknown
    @Published private(set) var isCalibrated: Bool = false

    let controller: EyeTrackController

    private let calibrationFileName = "current.json"

    init() {
        let device = EyeTrackingService.detectDevice()
        var configuration = EyeTrackKit.Configuration.default
        configuration.smoothingRange = 5
        configuration.blinkThreshold = 0.55
        configuration.coordinateSpace = .screenPoints
        configuration.autoPauseInBackground = true
        configuration.gaze.measurementNoise = 1.2e-1
        configuration.fixation.dispersionThreshold = 45

        self.controller = EyeTrackController(
            configuration: configuration,
            device: device,
            isHidden: true
        )

        loadStoredCalibrationIfAvailable()
    }

    // MARK: - Authorization

    func requestAuthorization() async {
        guard EyeTrackKit.isSupported else {
            authorizationState = .unsupported
            return
        }
        do {
            _ = try await EyeTrackKit.requestAuthorization()
            authorizationState = .authorized
        } catch let EyeTrackKit.AuthorizationError.cameraDenied {
            authorizationState = .denied(reason: "Camera access required.")
        } catch {
            authorizationState = .denied(reason: error.localizedDescription)
        }
    }

    // MARK: - Calibration

    func applyCalibration(_ profile: CalibrationProfile) {
        controller.calibrationProfile = profile
        isCalibrated = true
    }

    func saveCurrentCalibration() throws -> URL? {
        guard let profile = controller.calibrationProfile else { return nil }
        let url = currentCalibrationURL()
        try CalibrationStore.shared.save(profile, to: url)
        isCalibrated = true
        return url
    }

    func clearCalibration() {
        controller.clearCalibration()
        isCalibrated = false
        try? FileManager.default.removeItem(at: currentCalibrationURL())
    }

    private func loadStoredCalibrationIfAvailable() {
        let url = currentCalibrationURL()
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let profile = try CalibrationStore.shared.load(from: url)
            controller.calibrationProfile = profile
            isCalibrated = true
        } catch {
            // Stale or incompatible profile — clear it.
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func currentCalibrationURL() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent(calibrationFileName)
    }

    // MARK: - Device detection

    /// Picks the closest matching `DeviceType` based on the current screen
    /// size in points. Falls back to a recent iPhone Pro spec.
    private static func detectDevice() -> Device {
        let bounds = UIScreen.main.bounds
        let w = bounds.width, h = bounds.height
        let portrait = h >= w
        let pointSize = portrait ? CGSize(width: w, height: h) : CGSize(width: h, height: w)

        switch (Int(pointSize.width), Int(pointSize.height)) {
        case (414, 896): return Device(type: .iPhone11)
        case (375, 812): return Device(type: .iPhone11Pro)
        case (390, 844): return Device(type: .iPhone13)
        case (393, 852): return Device(type: .iPhone15Pro) // also iPhone 14 Pro
        case (402, 874): return Device(type: .iPhone16Pro)
        case (834, 1194): return portrait ? Device(type: .iPad) : Device(type: .iPadLandscape)
        case (1024, 1366): return Device(type: .iPadPro12_9)
        default:
            return Device(type: .iPhone15Pro)
        }
    }
}
