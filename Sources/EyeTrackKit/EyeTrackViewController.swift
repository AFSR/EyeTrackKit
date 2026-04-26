//
//  EyeTrackViewController.swift
//
//
//  Created by Yuki Yamato on 2020/11/03.
//

import UIKit
import SceneKit
import ARKit

open class EyeTrackViewController: UIViewController, ARSCNViewDelegate, ARSessionDelegate {

    public private(set) var sceneView: ARSCNView!
    public private(set) var eyeTrack: EyeTrack!
    public private(set) var recorder: EyeTrackRecorder?
    public var isHidden: Bool = true

    private var sync: EyeTrackSceneSync!

    public func initialize(isHidden: Bool = true,
                           eyeTrack: EyeTrack,
                           recorderConfiguration: EyeTrackRecorder.Configuration = .default) {
        self.isHidden = isHidden
        self.eyeTrack = eyeTrack

        let sceneView = ARSCNView(frame: super.view.frame)
        self.sceneView = sceneView
        self.view.addSubview(sceneView)

        sceneView.delegate = self
        sceneView.session.delegate = self
        sceneView.isHidden = isHidden
        sceneView.automaticallyUpdatesLighting = true
        sceneView.rendersContinuously = true

        eyeTrack.registerSceneView(sceneView: sceneView)
        let recorder = EyeTrackRecorder(sceneView: sceneView, configuration: recorderConfiguration)
        recorder.currentInfoProvider = { [weak eyeTrack] in eyeTrack?.info }
        self.recorder = recorder
        sync = EyeTrackSceneSync(eyeTrack: eyeTrack, sceneView: sceneView, recorder: recorder)
    }

    public func hide() {
        sceneView.isHidden = true
    }

    public func show() {
        sceneView.isHidden = false
    }

    public func startRecord() {
        do {
            try recorder?.startRecording()
        } catch {
            print("EyeTrackKit recorder start failed: \(error)")
        }
    }

    public func stopRecord(finished: @escaping (URL) -> Void = { _ in },
                           isExport: Bool = true) {
        if isExport {
            recorder?.stopAndExport { url, _ in
                if let url { finished(url) }
            }
        } else {
            recorder?.stop { url in
                if let url { finished(url) }
            }
        }
    }

    open override func viewDidLoad() {
        super.viewDidLoad()
    }

    open override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        let configuration = ARFaceTrackingConfiguration()
        configuration.isLightEstimationEnabled = true
        if ARFaceTrackingConfiguration.supportsWorldTracking {
            configuration.isWorldTrackingEnabled = true
        }
        sceneView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    }

    open override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sceneView.session.pause()
    }

    // MARK: - ARSessionDelegate

    open func session(_ session: ARSession, didFailWithError error: Error) { }
    open func sessionWasInterrupted(_ session: ARSession) { }
    open func sessionInterruptionEnded(_ session: ARSession) { }

    public func session(_ session: ARSession, didUpdate frame: ARFrame) {
        sync.handleSession(didUpdate: frame)
    }

    // Override hook for subclasses to react to anchor updates.
    open func updateViewWithUpdateAnchor() { }

    // MARK: - ARSCNViewDelegate / SCNSceneRendererDelegate

    public func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        sync.handleAdd(node: node, anchor: anchor)
    }

    public func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        sync.handleUpdate(node: node, anchor: anchor)
    }

    public func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        sync.handleSceneTick()
    }

    public func renderer(_ renderer: SCNSceneRenderer,
                         didRenderScene scene: SCNScene,
                         atTime time: TimeInterval) {
        sync.handleDidRenderScene(at: time)
    }
}
