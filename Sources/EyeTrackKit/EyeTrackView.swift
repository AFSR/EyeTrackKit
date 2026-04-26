//
//  EyeTrackView.swift
//
//
//  Created by Yuki Yamato on 2020/10/01.
//

import SwiftUI
import ARKit
import SceneKit
import ARVideoKit
import os

public struct EyeTrackView: UIViewRepresentable {
    public var eyeTrack: EyeTrack
    public var isHidden: Bool

    /// The ARSCNView is wrapped in `@State` so SwiftUI preserves the same
    /// instance across struct recreations. ARKit sessions are stateful and
    /// expensive to recreate, so we want exactly one across the lifetime of
    /// the parent View identity.
    @State private var sceneView: ARSCNView
    @State private var recorder: RecordAR?
    private let configuration: ARFaceTrackingConfiguration
    private let logger = Logger(subsystem: "dev.ukitomato.EyeTrackKit", category: "EyeTrackView")

    public init(isHidden: Bool = true, eyeTrack: EyeTrack) {
        self.init(isHidden: isHidden, eyeTrack: eyeTrack, sceneView: ARSCNView(frame: .zero))
    }

    public init(isHidden: Bool = true, eyeTrack: EyeTrack, sceneView: ARSCNView) {
        self.isHidden = isHidden
        self.eyeTrack = eyeTrack
        self._sceneView = State(initialValue: sceneView)
        self._recorder = State(initialValue: RecordAR(ARSceneKit: sceneView))

        let configuration = ARFaceTrackingConfiguration()
        configuration.isLightEstimationEnabled = true
        if ARFaceTrackingConfiguration.supportsWorldTracking {
            configuration.isWorldTrackingEnabled = true
        }
        self.configuration = configuration
    }

    public func makeUIView(context: Context) -> ARSCNView {
        sceneView.delegate = context.coordinator
        sceneView.session.delegate = context.coordinator
        sceneView.isHidden = isHidden
        sceneView.automaticallyUpdatesLighting = true
        sceneView.rendersContinuously = true

        recorder?.renderAR = context.coordinator
        recorder?.onlyRenderWhileRecording = false
        return sceneView
    }

    public func updateUIView(_ uiView: ARSCNView, context: Context) {
        uiView.isHidden = isHidden
    }

    public func hide() {
        logger.debug("hide")
        sceneView.isHidden = true
    }

    public func show() {
        logger.debug("show")
        sceneView.isHidden = false
    }

    public func start() {
        sceneView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        recorder?.prepare(configuration)
    }

    public func pause() {
        sceneView.session.pause()
        recorder?.rest()
    }

    public func startRecord() {
        recorder?.record()
    }

    public func stopRecord(finished: @escaping (URL) -> Void = { _ in },
                           isExport: Bool = false) {
        if isExport {
            recorder?.stopAndExport()
        } else {
            recorder?.stop { url in
                finished(url)
            }
        }
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(eyeTrack: eyeTrack, sceneView: sceneView, recorder: recorder)
    }

    public final class Coordinator: NSObject, ARSCNViewDelegate, ARSessionDelegate, RenderARDelegate {
        private let sync: EyeTrackSceneSync
        private weak var sceneView: ARSCNView?
        private let recorder: RecordAR?

        init(eyeTrack: EyeTrack, sceneView: ARSCNView, recorder: RecordAR?) {
            self.sceneView = sceneView
            self.recorder = recorder
            self.sync = EyeTrackSceneSync(eyeTrack: eyeTrack, sceneView: sceneView)
            super.init()
            eyeTrack.registerSceneView(sceneView: sceneView)
        }

        deinit {
            recorder?.rest()
            sceneView?.session.pause()
        }

        public func frame(didRender buffer: CVPixelBuffer, with time: CMTime, using rawBuffer: CVPixelBuffer) {
            sync.handleFrame(buffer: rawBuffer)
        }

        public func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
            sync.handleAdd(node: node, anchor: anchor)
        }

        public func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
            sync.handleSceneTick()
        }

        public func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
            sync.handleUpdate(node: node, anchor: anchor)
        }
    }
}
