//
//  EyeTrackRecorder.swift
//
//
//  In-house replacement for ARVideoKit's `RecordAR`. Captures the rendered
//  ARSCNView content at display rate and encodes it via AVAssetWriter.
//
//  Pipeline:
//    1. SceneKit's render delegate fires `didRenderScene(at:)` from the
//       Metal render thread.
//    2. We pull a CVPixelBuffer from a pre-warmed IOSurface-backed pool.
//    3. CVMetalTextureCache wraps the buffer as an MTLTexture (zero copy).
//    4. SCNRenderer renders the live scene into that texture via a
//       MTLRenderPassDescriptor — no UIImage / CGImage round-trips.
//    5. The buffer is appended to AVAssetWriterInputPixelBufferAdaptor.
//
//  This removes the only reason EyeTrackKit depended on ARVideoKit (last
//  released 2020, unmaintained).
//

import Foundation
import AVFoundation
import ARKit
import SceneKit
import Metal
import Photos
import os

public final class EyeTrackRecorder {
    public enum Codec {
        case h264
        case hevc
    }

    public enum RecorderError: Error {
        case alreadyRecording
        case notRecording
        case sceneViewUnavailable
        case metalDeviceUnavailable
        case writerSetupFailed
        case photoLibraryDenied
    }

    public struct Configuration {
        public var codec: Codec
        public var videoBitRate: Int
        public var maxKeyFrameInterval: Int
        public var outputDirectory: URL?
        /// When `true`, a `<videoName>.csv` is written alongside the video,
        /// containing one row per encoded frame (see `VideoSidecarWriter`).
        public var writeSidecarCSV: Bool

        public init(codec: Codec = .hevc,
                    videoBitRate: Int = 6_000_000,
                    maxKeyFrameInterval: Int = 60,
                    outputDirectory: URL? = nil,
                    writeSidecarCSV: Bool = false) {
            self.codec = codec
            self.videoBitRate = videoBitRate
            self.maxKeyFrameInterval = maxKeyFrameInterval
            self.outputDirectory = outputDirectory
            self.writeSidecarCSV = writeSidecarCSV
        }

        public static let `default` = Configuration()
    }

    public private(set) var isRecording: Bool = false
    public var configuration: Configuration

    /// Optional callback the recorder invokes on every captured frame to
    /// fetch the latest tracking info, written to the sidecar CSV. Set this
    /// before calling `startRecording()`.
    public var currentInfoProvider: (() -> EyeTrackInfo?)?

    /// URL of the most recent recording (set when `startRecording` succeeds).
    public private(set) var lastOutputURL: URL?

    private weak var sceneView: ARSCNView?
    private var renderer: SCNRenderer?
    private var commandQueue: MTLCommandQueue?
    private var pixelBufferPool: CVPixelBufferPool?
    private var textureCache: CVMetalTextureCache?

    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var sidecar: VideoSidecarWriter?

    private var sessionStartTime: CMTime?
    private var outputURL: URL?
    private var renderSize: CGSize = .zero

    private let lock = NSLock()
    private let logger = Logger(subsystem: "dev.ukitomato.EyeTrackKit", category: "EyeTrackRecorder")

    public init(sceneView: ARSCNView, configuration: Configuration = .default) {
        self.sceneView = sceneView
        self.configuration = configuration
    }

    // MARK: - Public API

    public func startRecording() throws {
        lock.lock()
        defer { lock.unlock() }

        guard !isRecording else { throw RecorderError.alreadyRecording }
        guard let sceneView = sceneView else { throw RecorderError.sceneViewUnavailable }
        guard let device = sceneView.device ?? MTLCreateSystemDefaultDevice() else {
            throw RecorderError.metalDeviceUnavailable
        }

        let scale = sceneView.contentScaleFactor > 0 ? sceneView.contentScaleFactor : UIScreen.main.scale
        let bounds = sceneView.bounds
        // H.264/HEVC require even dimensions.
        let pixelWidth = max(2, Int(bounds.width * scale)) & ~1
        let pixelHeight = max(2, Int(bounds.height * scale)) & ~1
        renderSize = CGSize(width: pixelWidth, height: pixelHeight)

        let url = makeOutputURL()
        try? FileManager.default.removeItem(at: url)

        let writer: AVAssetWriter
        do {
            writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        } catch {
            logger.error("AVAssetWriter init failed: \(error.localizedDescription)")
            throw RecorderError.writerSetupFailed
        }

        let codecKey: AVVideoCodecType = (configuration.codec == .hevc) ? .hevc : .h264
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: codecKey,
            AVVideoWidthKey: pixelWidth,
            AVVideoHeightKey: pixelHeight,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: configuration.videoBitRate,
                AVVideoMaxKeyFrameIntervalKey: configuration.maxKeyFrameInterval,
            ],
        ]

        let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        input.expectsMediaDataInRealTime = true
        // Match the device portrait orientation by default; callers can rotate
        // via the UI if needed.
        input.transform = CGAffineTransform.identity

        let bufferAttrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: pixelWidth,
            kCVPixelBufferHeightKey as String: pixelHeight,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:],
            kCVPixelBufferMetalCompatibilityKey as String: true,
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: bufferAttrs
        )

        guard writer.canAdd(input) else { throw RecorderError.writerSetupFailed }
        writer.add(input)

        // Pre-warmed IOSurface-backed pool — avoids per-frame allocation.
        var pool: CVPixelBufferPool?
        let poolAttrs: [String: Any] = [
            kCVPixelBufferPoolMinimumBufferCountKey as String: 3,
        ]
        let poolStatus = CVPixelBufferPoolCreate(
            nil, poolAttrs as CFDictionary, bufferAttrs as CFDictionary, &pool
        )
        guard poolStatus == kCVReturnSuccess, let pool = pool else {
            throw RecorderError.writerSetupFailed
        }

        var cache: CVMetalTextureCache?
        let cacheStatus = CVMetalTextureCacheCreate(nil, nil, device, nil, &cache)
        guard cacheStatus == kCVReturnSuccess, let cache = cache else {
            throw RecorderError.writerSetupFailed
        }

        let scnRenderer = SCNRenderer(device: device, options: nil)
        scnRenderer.scene = sceneView.scene
        scnRenderer.pointOfView = sceneView.pointOfView

        guard let queue = device.makeCommandQueue() else {
            throw RecorderError.writerSetupFailed
        }

        guard writer.startWriting() else {
            logger.error("AVAssetWriter.startWriting failed: \(writer.error?.localizedDescription ?? "unknown")")
            throw RecorderError.writerSetupFailed
        }
        writer.startSession(atSourceTime: .zero)

        self.assetWriter = writer
        self.videoInput = input
        self.pixelBufferAdaptor = adaptor
        self.pixelBufferPool = pool
        self.textureCache = cache
        self.renderer = scnRenderer
        self.commandQueue = queue
        self.outputURL = url
        self.lastOutputURL = url
        self.sessionStartTime = nil
        self.isRecording = true

        if configuration.writeSidecarCSV {
            let sidecar = VideoSidecarWriter(videoURL: url)
            do {
                try sidecar.start()
                self.sidecar = sidecar
            } catch {
                logger.warning("sidecar start failed: \(error.localizedDescription)")
            }
        }

        logger.debug("Recording started: \(url.lastPathComponent) @ \(pixelWidth)x\(pixelHeight)")
    }

    /// Called from the SceneKit render thread on every rendered frame. This
    /// must be cheap: any work here delays the next display refresh.
    public func captureFrame(at time: TimeInterval) {
        lock.lock()
        let recording = isRecording
        let adaptor = pixelBufferAdaptor
        let input = videoInput
        let pool = pixelBufferPool
        let renderer = self.renderer
        let cache = self.textureCache
        let queue = self.commandQueue
        let size = self.renderSize
        let pov = sceneView?.pointOfView
        var sessionStart = sessionStartTime
        lock.unlock()

        guard recording,
              let adaptor, let input, input.isReadyForMoreMediaData,
              let pool, let renderer, let cache, let queue else { return }

        var maybePB: CVPixelBuffer?
        let pbStatus = CVPixelBufferPoolCreatePixelBuffer(nil, pool, &maybePB)
        guard pbStatus == kCVReturnSuccess, let pixelBuffer = maybePB else { return }

        var maybeTex: CVMetalTexture?
        let texStatus = CVMetalTextureCacheCreateTextureFromImage(
            nil, cache, pixelBuffer, nil,
            .bgra8Unorm, Int(size.width), Int(size.height), 0,
            &maybeTex
        )
        guard texStatus == kCVReturnSuccess,
              let cvTexture = maybeTex,
              let texture = CVMetalTextureGetTexture(cvTexture) else { return }

        let passDesc = MTLRenderPassDescriptor()
        passDesc.colorAttachments[0].texture = texture
        passDesc.colorAttachments[0].loadAction = .clear
        passDesc.colorAttachments[0].storeAction = .store
        passDesc.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)

        guard let commandBuffer = queue.makeCommandBuffer() else { return }

        renderer.pointOfView = pov
        renderer.render(
            atTime: time,
            viewport: CGRect(origin: .zero, size: size),
            commandBuffer: commandBuffer,
            passDescriptor: passDesc
        )
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        let scnTime = CMTime(seconds: time, preferredTimescale: 1_000_000)
        let presentationTime: CMTime
        if let start = sessionStart {
            presentationTime = scnTime - start
        } else {
            sessionStart = scnTime
            lock.lock()
            sessionStartTime = scnTime
            lock.unlock()
            presentationTime = .zero
        }

        adaptor.append(pixelBuffer, withPresentationTime: presentationTime)

        if let sidecar, let info = currentInfoProvider?() {
            sidecar.append(info: info, at: scnTime)
        }
    }

    public func stop(completion: @escaping (URL?) -> Void) {
        lock.lock()
        guard isRecording, let writer = assetWriter, let input = videoInput else {
            lock.unlock()
            DispatchQueue.main.async { completion(nil) }
            return
        }
        isRecording = false
        let url = outputURL
        lock.unlock()

        input.markAsFinished()
        sidecar?.stop()
        writer.finishWriting { [weak self] in
            self?.releaseResources()
            DispatchQueue.main.async { completion(url) }
        }
    }

    public func stopAndExport(completion: @escaping (URL?, Error?) -> Void) {
        stop { [weak self] url in
            guard let self, let url else {
                completion(nil, nil)
                return
            }
            self.exportToPhotoLibrary(url: url, completion: completion)
        }
    }

    public func cancel() {
        lock.lock()
        guard isRecording, let writer = assetWriter, let input = videoInput else {
            lock.unlock()
            return
        }
        isRecording = false
        let url = outputURL
        lock.unlock()

        input.markAsFinished()
        writer.cancelWriting()
        sidecar?.stop()
        if let url {
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(at: url.deletingPathExtension().appendingPathExtension("csv"))
        }
        releaseResources()
    }

    // MARK: - Internals

    private func releaseResources() {
        lock.lock()
        defer { lock.unlock() }
        assetWriter = nil
        videoInput = nil
        pixelBufferAdaptor = nil
        pixelBufferPool = nil
        textureCache = nil
        renderer = nil
        commandQueue = nil
        sessionStartTime = nil
        sidecar = nil
    }

    private func exportToPhotoLibrary(url: URL, completion: @escaping (URL?, Error?) -> Void) {
        let perform = {
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            } completionHandler: { _, error in
                DispatchQueue.main.async { completion(url, error) }
            }
        }
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        if status == .authorized || status == .limited {
            perform()
            return
        }
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { newStatus in
            if newStatus == .authorized || newStatus == .limited {
                perform()
            } else {
                DispatchQueue.main.async {
                    completion(url, RecorderError.photoLibraryDenied)
                }
            }
        }
    }

    private func makeOutputURL() -> URL {
        let directory = configuration.outputDirectory
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let name = "eyetrack-\(Int(Date().timeIntervalSince1970 * 1000)).mp4"
        return directory.appendingPathComponent(name)
    }
}
