//
//  GameEngine.swift
//
//  Physics + state for the collision game. Balls bounce elastically off
//  the play-area edges; when the gaze cursor overlaps a ball it explodes,
//  the score increments, and a replacement spawns somewhere safe.
//

import SwiftUI
import Combine
import UIKit

@MainActor
final class GameEngine: ObservableObject {
    // MARK: - Tunables

    struct Tuning {
        var ballCount: Int = 12
        var minRadius: CGFloat = 28
        var maxRadius: CGFloat = 44
        var minSpeed: CGFloat = 90    // points / second
        var maxSpeed: CGFloat = 220
        var gazeRadius: CGFloat = 22
        /// Soft pad to keep balls fully inside the play area at spawn.
        var spawnInset: CGFloat = 16
        /// Time the explosion animation plays before the ball is removed.
        var explosionDuration: TimeInterval = 0.25
        /// Game length. Set to nil for endless play.
        var roundDuration: TimeInterval? = 60
    }

    var tuning = Tuning()

    // MARK: - Published state

    @Published private(set) var balls: [Ball] = []
    @Published private(set) var score: Int = 0
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var isRunning: Bool = false
    @Published private(set) var isFinished: Bool = false

    /// Smoothed gaze point in screen-points (top-left origin), supplied by
    /// the host view from the EyeTrackKit gaze stream.
    @Published var gazePoint: CGPoint = .zero

    // MARK: - Private state

    private(set) var bounds: CGRect = .zero
    private var displayLink: CADisplayLink?
    private var lastTickTime: CFTimeInterval = 0
    private var startedAt: Date?

    // MARK: - Lifecycle

    func start(in bounds: CGRect) {
        self.bounds = bounds
        score = 0
        elapsed = 0
        isFinished = false
        isRunning = true
        startedAt = Date()
        balls = (0..<tuning.ballCount).map { _ in spawnBall() }
        startDisplayLink()
    }

    func stop() {
        isRunning = false
        displayLink?.invalidate()
        displayLink = nil
    }

    func updateBounds(_ newBounds: CGRect) {
        bounds = newBounds
    }

    // MARK: - Display link loop

    private func startDisplayLink() {
        displayLink?.invalidate()
        let proxy = DisplayLinkProxy(target: self)
        let link = CADisplayLink(target: proxy, selector: #selector(DisplayLinkProxy.tick(_:)))
        link.add(to: .main, forMode: .common)
        lastTickTime = CACurrentMediaTime()
        displayLink = link
    }

    @objc fileprivate func tick(_ link: CADisplayLink) {
        let now = CACurrentMediaTime()
        let dt = min(now - lastTickTime, 1.0 / 30.0) // clamp big gaps
        lastTickTime = now
        step(dt: CGFloat(dt))
    }

    // MARK: - Step

    private func step(dt: CGFloat) {
        guard isRunning else { return }
        elapsed = startedAt.map { Date().timeIntervalSince($0) } ?? 0

        if let limit = tuning.roundDuration, elapsed >= limit {
            stop()
            isFinished = true
            return
        }

        // Move and bounce.
        for i in balls.indices {
            guard !balls[i].isExploding else { continue }
            balls[i].position.x += balls[i].velocity.dx * dt
            balls[i].position.y += balls[i].velocity.dy * dt

            let r = balls[i].radius
            if balls[i].position.x - r < bounds.minX {
                balls[i].position.x = bounds.minX + r
                balls[i].velocity.dx = abs(balls[i].velocity.dx)
            } else if balls[i].position.x + r > bounds.maxX {
                balls[i].position.x = bounds.maxX - r
                balls[i].velocity.dx = -abs(balls[i].velocity.dx)
            }
            if balls[i].position.y - r < bounds.minY {
                balls[i].position.y = bounds.minY + r
                balls[i].velocity.dy = abs(balls[i].velocity.dy)
            } else if balls[i].position.y + r > bounds.maxY {
                balls[i].position.y = bounds.maxY - r
                balls[i].velocity.dy = -abs(balls[i].velocity.dy)
            }
        }

        // Gaze collisions.
        for i in balls.indices where !balls[i].isExploding {
            let dx = balls[i].position.x - gazePoint.x
            let dy = balls[i].position.y - gazePoint.y
            let distSquared = dx * dx + dy * dy
            let touchDist = balls[i].radius + tuning.gazeRadius
            if distSquared < touchDist * touchDist {
                balls[i].explodingSince = Date()
                score += 1
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }
        }

        // Recycle expired explosions.
        let now = Date()
        for i in balls.indices {
            if let started = balls[i].explodingSince,
               now.timeIntervalSince(started) >= tuning.explosionDuration {
                balls[i] = spawnBall()
            }
        }
    }

    private func spawnBall() -> Ball {
        let radius = CGFloat.random(in: tuning.minRadius...tuning.maxRadius)
        let pad = radius + tuning.spawnInset

        // Avoid spawning under the current gaze cursor.
        var position: CGPoint
        var attempts = 0
        repeat {
            position = CGPoint(
                x: CGFloat.random(in: (bounds.minX + pad)...(bounds.maxX - pad)),
                y: CGFloat.random(in: (bounds.minY + pad)...(bounds.maxY - pad))
            )
            attempts += 1
        } while attempts < 6 && distance(position, gazePoint) < (radius + tuning.gazeRadius + 60)

        let speed = CGFloat.random(in: tuning.minSpeed...tuning.maxSpeed)
        let angle = CGFloat.random(in: 0..<(2 * .pi))
        let velocity = CGVector(dx: cos(angle) * speed, dy: sin(angle) * speed)
        let color = Ball.palette.randomElement() ?? .red

        return Ball(position: position, velocity: velocity, radius: radius, color: color)
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = a.x - b.x, dy = a.y - b.y
        return (dx * dx + dy * dy).squareRoot()
    }
}

/// CADisplayLink retains its target. Wrapping the engine in a proxy with a
/// weak ref prevents the display link from keeping the engine alive after
/// the view disappears.
private final class DisplayLinkProxy {
    weak var target: GameEngine?
    init(target: GameEngine) { self.target = target }

    @objc func tick(_ link: CADisplayLink) {
        Task { @MainActor in target?.tick(link) }
    }
}
