//
//  AffineTransform2D.swift
//
//
//  Codable 2D affine transform used by the calibration system to map raw
//  gaze (post-Kalman, pre-calibration) into screen coordinates.
//
//  A 2D affine transform has 6 degrees of freedom:
//    [ a b tx ]   [x]   [a*x + b*y + tx]
//    [ c d ty ] * [y] = [c*x + d*y + ty]
//    [ 0 0  1 ]   [1]   [             1]
//
//  Fitting from N >= 3 sample pairs is a 3-parameter linear regression per
//  axis, solvable with a 3x3 normal-equations system. We implement Gaussian
//  elimination inline to avoid pulling in Accelerate just for this.
//

import Foundation
import CoreGraphics

public struct AffineTransform2D: Codable, Equatable {
    public var a: Double
    public var b: Double
    public var tx: Double
    public var c: Double
    public var d: Double
    public var ty: Double

    public init(a: Double, b: Double, tx: Double, c: Double, d: Double, ty: Double) {
        self.a = a; self.b = b; self.tx = tx
        self.c = c; self.d = d; self.ty = ty
    }

    public static let identity = AffineTransform2D(a: 1, b: 0, tx: 0, c: 0, d: 1, ty: 0)

    @inlinable
    public func apply(to point: CGPoint) -> CGPoint {
        let x = Double(point.x), y = Double(point.y)
        return CGPoint(x: a * x + b * y + tx, y: c * x + d * y + ty)
    }

    /// Fits an affine transform mapping raw gaze samples to target points
    /// using least-squares. Returns the transform plus the per-sample
    /// residual error (Euclidean distance, screen coordinate units).
    public static func fit(
        from samples: [(raw: CGPoint, target: CGPoint)]
    ) -> (transform: AffineTransform2D, residuals: [Double])? {
        guard samples.count >= 3 else { return nil }

        // Build M^T M (3x3) and M^T y for x and y separately.
        // M is N x 3 with rows [raw_x_i, raw_y_i, 1].
        var mtm = [[Double]](repeating: [Double](repeating: 0, count: 3), count: 3)
        var mty_x = [Double](repeating: 0, count: 3)
        var mty_y = [Double](repeating: 0, count: 3)

        for s in samples {
            let row = [Double(s.raw.x), Double(s.raw.y), 1.0]
            for i in 0..<3 {
                for j in 0..<3 { mtm[i][j] += row[i] * row[j] }
                mty_x[i] += row[i] * Double(s.target.x)
                mty_y[i] += row[i] * Double(s.target.y)
            }
        }

        guard let xParams = LinearAlgebra.solve3x3(mtm, mty_x),
              let yParams = LinearAlgebra.solve3x3(mtm, mty_y) else { return nil }

        let transform = AffineTransform2D(
            a: xParams[0], b: xParams[1], tx: xParams[2],
            c: yParams[0], d: yParams[1], ty: yParams[2]
        )

        let residuals = samples.map { s -> Double in
            let mapped = transform.apply(to: s.raw)
            let dx = Double(mapped.x - s.target.x)
            let dy = Double(mapped.y - s.target.y)
            return (dx * dx + dy * dy).squareRoot()
        }
        return (transform, residuals)
    }
}

enum LinearAlgebra {
    /// Solves Ax = b for a 3x3 system via Gaussian elimination with partial
    /// pivoting. Returns nil if the matrix is singular (within 1e-12).
    static func solve3x3(_ A: [[Double]], _ b: [Double]) -> [Double]? {
        var m = A
        var rhs = b
        let n = 3

        for i in 0..<n {
            var pivotRow = i
            var pivotVal = abs(m[i][i])
            for k in (i + 1)..<n where abs(m[k][i]) > pivotVal {
                pivotVal = abs(m[k][i])
                pivotRow = k
            }
            if pivotVal < 1e-12 { return nil }
            if pivotRow != i {
                m.swapAt(i, pivotRow)
                rhs.swapAt(i, pivotRow)
            }
            for k in (i + 1)..<n {
                let factor = m[k][i] / m[i][i]
                for j in i..<n { m[k][j] -= factor * m[i][j] }
                rhs[k] -= factor * rhs[i]
            }
        }

        var x = [Double](repeating: 0, count: n)
        for i in stride(from: n - 1, through: 0, by: -1) {
            var sum = rhs[i]
            for j in (i + 1)..<n { sum -= m[i][j] * x[j] }
            x[i] = sum / m[i][i]
        }
        return x
    }
}
