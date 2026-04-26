//
//  EyeTrackSceneSync.swift
//
//
//  Shared ARSCNViewDelegate logic used by both EyeTrackView.Coordinator and
//  EyeTrackViewController. Eliminates the duplication that previously existed
//  across both call sites and adds frame-coalescing on the main queue to
//  prevent update jobs from piling up under load.
//

import Foundation
import ARKit
import SceneKit

final class EyeTrackSceneSync {
    private weak var eyeTrack: EyeTrack?
    private weak var sceneView: ARSCNView?

    /// Atomic flag — true while an update is enqueued on the main queue.
    /// We coalesce by overwriting `pendingAnchor` and skipping a new dispatch.
    /// At 60+ fps this trades a missed intermediate frame for a guarantee
    /// that the main queue never accumulates a backlog of stale updates.
    private let lock = NSLock()
    private var pendingAnchor: ARFaceAnchor?
    private var dispatchInFlight = false

    init(eyeTrack: EyeTrack, sceneView: ARSCNView) {
        self.eyeTrack = eyeTrack
        self.sceneView = sceneView
    }

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

    func handleFrame(buffer: CVPixelBuffer) {
        // Pixel buffer callbacks fire from ARKit's render thread. The handler
        // is user-supplied and may touch UI state, so we hop to main but
        // do not coalesce here — typically the user wants every frame.
        DispatchQueue.main.async { [weak self] in
            self?.eyeTrack?.updateFrame(pixelBuffer: buffer)
        }
    }

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
