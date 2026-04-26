//
//  UIView+Gaze.swift
//
//
//  UIKit helpers for gaze hit-testing.
//

import UIKit

public extension UIView {
    /// Returns `true` when the gaze point (in screen-points, top-left origin)
    /// falls within this view's bounds in window coordinates.
    func gazeContains(_ gazePoint: CGPoint) -> Bool {
        guard window != nil else { return false }
        let inWindow = convert(bounds, to: nil)
        return inWindow.contains(gazePoint)
    }

    /// Hit-tests `self` and its descendants against the gaze point and
    /// returns the deepest visible view that contains it, or nil if the
    /// gaze is outside.
    func gazeHitTest(_ gazePoint: CGPoint) -> UIView? {
        guard let window = window else { return nil }
        let local = window.convert(gazePoint, to: self)
        return hitTest(local, with: nil)
    }
}
