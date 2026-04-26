//
//  EyeTrackView.swift
//
//
//  Created by Yuki Yamato on 2020/10/01.
//

import SwiftUI
import ARKit
import SceneKit
import os

public struct EyeTrackView: UIViewRepresentable {
    public var eyeTrack: EyeTrack
    public var isHidden: Bool
    public var recorderConfiguration: EyeTrackRecorder.Configuration

    /// The ARSCNView is wrapped in `@State` so SwiftUI preserves the same
    /// instance across struct recreations. ARKit sessions are stateful and
    /// expensive to recreate, so we want exactly one across the lifetime of
    /// the parent View identity.
    @State private var sceneView: ARSCNView
    @State private var recorder: EyeTrackRecorder

    private let configuration: ARFaceTrackingConfiguration
    private let logger = Logger(subsystem: "dev.ukitomato.EyeTrackKit", category: "EyeTrackView")

    public init(isHidden: Bool = true,
                eyeTrack: EyeTrack,
                recorderConfiguration: EyeTrackRecorder.Configuration = .default) {
        self.init(isHidden: isHidden,
                  eyeTrack: eyeTrack,
                  sceneView: ARSCNView(frame: .zero),
                  recorderConfiguration: recorderConfiguration)
    }

    public init(isHidden: Bool = true,
                eyeTrack: EyeTrack,
                sceneView: ARSCNView,
                recorderConfiguration: EyeTrackRecorder.Configuration = .default) {
        self.isHidden = isHidden
        self.eyeTrack = eyeTrack
        self.recorderConfiguration = recorderConfiguration
        self._sceneView = State(initialValue: sceneView)
        self._recorder = State(initialValue: EyeTrackRecorder(sceneView: sceneView,
                                                              configuration: recorderConfiguration))

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
    }

    public func pause() {
        sceneView.session.pause()
    }

    public func startRecord() {
        do {
            try recorder.startRecording()
        } catch {
            logger.error("startRecord failed: \(error.localizedDescription)")
        }
    }

    public func stopRecord(finished: @escaping (URL) -> Void = { _ in },
                           isExport: Bool = false) {
        if isExport {
            recorder.stopAndExport { url, error in
                if let error { self.logger.error("export failed: \(error.localizedDescription)") }
                if let url { finished(url) }
            }
        } else {
            recorder.stop { url in
                if let url { finished(url) }
            }
        }
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(eyeTrack: eyeTrack, sceneView: sceneView, recorder: recorder)
    }

    public final class Coordinator: NSObject, ARSCNViewDelegate, ARSessionDelegate {
        private let sync: EyeTrackSceneSync
        private weak var sceneView: ARSCNView?

        init(eyeTrack: EyeTrack, sceneView: ARSCNView, recorder: EyeTrackRecorder) {
            self.sceneView = sceneView
            self.sync = EyeTrackSceneSync(eyeTrack: eyeTrack,
                                          sceneView: sceneView,
                                          recorder: recorder)
            super.init()
            recorder.currentInfoProvider = { [weak eyeTrack] in eyeTrack?.info }
            eyeTrack.registerSceneView(sceneView: sceneView)
        }

        deinit {
            sceneView?.session.pause()
        }

        // MARK: - ARSessionDelegate

        public func session(_ session: ARSession, didUpdate frame: ARFrame) {
            sync.handleSession(didUpdate: frame)
        }

        // MARK: - ARSCNViewDelegate / SCNSceneRendererDelegate

        public func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
            sync.handleAdd(node: node, anchor: anchor)
        }

        public func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
            sync.handleSceneTick()
        }

        public func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
            sync.handleUpdate(node: node, anchor: anchor)
        }

        public func renderer(_ renderer: SCNSceneRenderer,
                             didRenderScene scene: SCNScene,
                             atTime time: TimeInterval) {
            sync.handleDidRenderScene(at: time)
        }
    }
}
