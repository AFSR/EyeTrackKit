//
//  EyeTrackSceneSync.swift
//
//
//  Shared ARSCNViewDelegate / ARSessionDelegate / SCNSceneRendererDelegate
//  logic used by both EyeTrackView.Coordinator and EyeTrackViewController.
//
//  Replaces the previous ARVideoKit-driven `RenderARDelegate` callback with
//  Apple-native sources:
//    - Raw camera buffers come from `ARSession.didUpdate(frame:)`
//    - Recording frames are pulled in `renderer(_:didRenderScene:atTime:)`
//
//  Updates to `EyeTrack` are coalesced on the main queue so the queue cannot
//  accumulate a backlog of stale anchors at 60+ fps.
//

import Foundation
import ARKit
import SceneKit

final class EyeTrackSceneSync {
    private weak var eyeTrack: EyeTrack?
    private weak var sceneView: ARSCNView?
    var recorder: EyeTrackRecorder?

    private let lock = NSLock()
    private var pendingAnchor: ARFaceAnchor?
    private var dispatchInFlight = false

    init(eyeTrack: EyeTrack, sceneView: ARSCNView, recorder: EyeTrackRecorder? = nil) {
        self.eyeTrack = eyeTrack
        self.sceneView = sceneView
        self.recorder = recorder
    }

    // MARK: - SCNSceneRendererDelegate

    func handleAdd(node: SCNNode, anchor: ARAnchor) {
        eyeTrack?.face.node.transform = node.transform
        if let faceAnchor = anchor as? ARFaceAnchor {
            scheduleUpdate(with: faceAnchor)
        }
    }

    func handleUpdate(node: SCNNode, anchor: ARAnchor) {
        eyeTrack?.face.node.transform = node.transform
        if let faceAnchor = anchor as? ARFaceAnchor {
            scheduleUpdate(with: faceAnchor)
        }
    }

    func handleSceneTick() {
        guard let pov = sceneView?.pointOfView else { return }
        eyeTrack?.device.node.transform = pov.transform
    }

    /// Called from `renderer(_:didRenderScene:atTime:)` on the SceneKit render
    /// thread. Pulls a frame into the recorder's writer pipeline.
    func handleDidRenderScene(at time: TimeInterval) {
        recorder?.captureFrame(at: time)
    }

    // MARK: - ARSessionDelegate

    /// Replaces ARVideoKit's `RenderARDelegate.frame(didRender:with:using:)`
    /// callback. ARSession exposes the raw camera buffer as `frame.capturedImage`.
    func handleSession(didUpdate frame: ARFrame) {
        let buffer = frame.capturedImage
        // User callback often touches UI, so hop to main. Not coalesced —
        // typical consumers want every camera frame.
        DispatchQueue.main.async { [weak self] in
            self?.eyeTrack?.updateFrame(pixelBuffer: buffer)
        }
    }

    // MARK: - Coalesced face-anchor dispatch

    private func scheduleUpdate(with anchor: ARFaceAnchor) {
        lock.lock()
        pendingAnchor = anchor
        let shouldDispatch = !dispatchInFlight
        if shouldDispatch { dispatchInFlight = true }
        lock.unlock()

        guard shouldDispatch else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let anchor = self.pendingAnchor
            self.pendingAnchor = nil
            self.dispatchInFlight = false
            self.lock.unlock()
            if let anchor {
                self.eyeTrack?.update(anchor: anchor)
            }
        }
    }
}
