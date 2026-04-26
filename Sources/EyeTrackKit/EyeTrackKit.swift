//
//  EyeTrackKit.swift
//
//
//  Top-level namespace: device support detection, authorization, version.
//  Gives consumer apps a single, discoverable entry point before they
//  instantiate any tracker or controller.
//

import Foundation
import ARKit
import AVFoundation
import Photos

public enum EyeTrackKit {
    public static let version: String = "2.0.0"

    /// `true` only on devices with a TrueDepth front-facing camera (iPhone X
    /// and later, recent iPad Pro). Apps should fail-fast on unsupported
    /// hardware rather than instantiate `EyeTrackController`.
    public static var isSupported: Bool {
        ARFaceTrackingConfiguration.isSupported
    }

    public enum AuthorizationStatus: Sendable {
        case notDetermined
        case denied
        case authorized
        case restricted
    }

    /// Aggregate authorization status across the permissions EyeTrackKit
    /// uses. `.authorized` only when all required scopes are granted.
    public static var authorizationStatus: AuthorizationStatus {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return .authorized
        case .denied:     return .denied
        case .restricted: return .restricted
        case .notDetermined: return .notDetermined
        @unknown default: return .denied
        }
    }

    public struct AuthorizationResult: Sendable {
        public let camera: AuthorizationStatus
        /// Photos `.addOnly` scope. Only relevant if you call
        /// `EyeTrackRecorder.stopAndExport`.
        public let photoLibraryAdd: AuthorizationStatus
        public let microphone: AuthorizationStatus

        public var isFullyAuthorized: Bool {
            camera == .authorized
        }
    }

    public enum AuthorizationError: Error, LocalizedError {
        case unsupportedDevice
        case cameraDenied

        public var errorDescription: String? {
            switch self {
            case .unsupportedDevice: return "Device does not support ARKit face tracking."
            case .cameraDenied: return "Camera access is required for eye tracking."
            }
        }
    }

    public struct AuthorizationOptions: OptionSet, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }

        public static let camera = AuthorizationOptions(rawValue: 1 << 0)
        public static let photoLibraryAdd = AuthorizationOptions(rawValue: 1 << 1)
        public static let microphone = AuthorizationOptions(rawValue: 1 << 2)

        public static let `default`: AuthorizationOptions = [.camera]
        public static let recording: AuthorizationOptions = [.camera, .photoLibraryAdd]
    }

    /// Requests every authorization scope in `options` in parallel and
    /// returns the aggregate result. Throws only when a *required* (camera)
    /// scope is denied, since the library cannot function without it.
    @discardableResult
    public static func requestAuthorization(
        _ options: AuthorizationOptions = .default
    ) async throws -> AuthorizationResult {
        guard isSupported else { throw AuthorizationError.unsupportedDevice }

        async let cameraTask: AuthorizationStatus = options.contains(.camera)
            ? requestCameraAccess()
            : .authorized
        async let photosTask: AuthorizationStatus = options.contains(.photoLibraryAdd)
            ? requestPhotosAddAccess()
            : .authorized
        async let micTask: AuthorizationStatus = options.contains(.microphone)
            ? requestMicrophoneAccess()
            : .authorized

        let (cam, photos, mic) = await (cameraTask, photosTask, micTask)
        let result = AuthorizationResult(camera: cam, photoLibraryAdd: photos, microphone: mic)
        if options.contains(.camera) && cam != .authorized {
            throw AuthorizationError.cameraDenied
        }
        return result
    }

    // MARK: - Per-permission helpers

    private static func requestCameraAccess() async -> AuthorizationStatus {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return .authorized
        case .denied:     return .denied
        case .restricted: return .restricted
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            return granted ? .authorized : .denied
        @unknown default: return .denied
        }
    }

    private static func requestMicrophoneAccess() async -> AuthorizationStatus {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return .authorized
        case .denied:     return .denied
        case .restricted: return .restricted
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            return granted ? .authorized : .denied
        @unknown default: return .denied
        }
    }

    private static func requestPhotosAddAccess() async -> AuthorizationStatus {
        let current = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        switch current {
        case .authorized, .limited: return .authorized
        case .denied:               return .denied
        case .restricted:           return .restricted
        case .notDetermined:
            let new = await withCheckedContinuation { (cont: CheckedContinuation<PHAuthorizationStatus, Never>) in
                PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                    cont.resume(returning: status)
                }
            }
            switch new {
            case .authorized, .limited: return .authorized
            case .denied:               return .denied
            case .restricted:           return .restricted
            case .notDetermined:        return .notDetermined
            @unknown default:           return .denied
            }
        @unknown default: return .denied
        }
    }
}
