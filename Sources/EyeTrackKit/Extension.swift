//
//  Extension.swift
//
//
//  Created by Yuki Yamato on 2020/10/01.
//

import Foundation
import UIKit
import SceneKit

extension SCNVector3 {
    @inlinable
    func length() -> Float {
        let v = SIMD3<Float>(x, y, z)
        return (v.x * v.x + v.y * v.y + v.z * v.z).squareRoot()
    }

    @inlinable
    static func - (l: SCNVector3, r: SCNVector3) -> SCNVector3 {
        SCNVector3(l.x - r.x, l.y - r.y, l.z - r.z)
    }
}

extension CGPoint {
    @inlinable
    static func + (lhs: CGPoint, rhs: CGPoint) -> CGPoint {
        CGPoint(x: lhs.x + rhs.x, y: lhs.y + rhs.y)
    }

    @inlinable
    static func / (lhs: CGPoint, rhs: CGFloat) -> CGPoint {
        CGPoint(x: lhs.x / rhs, y: lhs.y / rhs)
    }
}

extension Collection where Element == CGFloat {
    @inlinable
    var average: CGFloat? {
        guard !isEmpty else { return nil }
        return reduce(0, +) / CGFloat(count)
    }
}

extension Collection where Element == CGPoint {
    @inlinable
    var average: CGPoint? {
        guard !isEmpty else { return nil }
        return reduce(.zero, +) / CGFloat(count)
    }
}

/// Fixed-capacity ring buffer with O(1) running sum used by the smoothing filter.
/// Avoids the unbounded growth of the original `[CGPoint]` buffer and removes
/// the `suffix(...) + reduce(...)` cost from every frame.
struct RingBuffer<Element> {
    private var storage: [Element?]
    private var head: Int = 0
    private(set) var count: Int = 0

    let capacity: Int

    init(capacity: Int) {
        self.capacity = max(1, capacity)
        self.storage = Array(repeating: nil, count: self.capacity)
    }

    /// Appends a new element. Returns the element it overwrote (if any),
    /// allowing callers to maintain a running sum cheaply.
    @discardableResult
    mutating func append(_ element: Element) -> Element? {
        let evicted = storage[head]
        storage[head] = element
        head = (head + 1) % capacity
        if count < capacity { count += 1 }
        return evicted
    }

    mutating func reset() {
        for i in 0..<storage.count { storage[i] = nil }
        head = 0
        count = 0
    }
}

/// 1-D Kalman filter. Instantiated per axis (x, y) to fuse noisy per-frame
/// gaze estimates into a smooth, low-latency signal.
///
/// The original implementation used a fixed-size moving average which trades
/// latency for smoothness with a hard cutoff. A Kalman filter provides
/// adaptive smoothing: it weights new measurements against accumulated
/// confidence, yielding lower latency and better noise rejection.
struct KalmanFilter1D {
    var processNoise: Double
    var measurementNoise: Double
    private var estimate: Double = 0
    private var errorCovariance: Double = 1
    private var initialized = false

    init(processNoise: Double = 1e-3, measurementNoise: Double = 1e-1) {
        self.processNoise = processNoise
        self.measurementNoise = measurementNoise
    }

    mutating func update(_ measurement: Double) -> Double {
        if !initialized {
            estimate = measurement
            initialized = true
            return estimate
        }
        // Predict
        errorCovariance += processNoise
        // Update
        let gain = errorCovariance / (errorCovariance + measurementNoise)
        estimate += gain * (measurement - estimate)
        errorCovariance *= (1 - gain)
        return estimate
    }

    mutating func reset() {
        estimate = 0
        errorCovariance = 1
        initialized = false
    }
}
