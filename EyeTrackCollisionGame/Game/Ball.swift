//
//  Ball.swift
//

import SwiftUI

struct Ball: Identifiable, Equatable {
    let id = UUID()
    var position: CGPoint
    var velocity: CGVector
    var radius: CGFloat
    var color: Color
    /// When the ball is hit by the gaze, we mark it exploding so the view
    /// can render the disappearance animation before it's removed.
    var explodingSince: Date?

    var isExploding: Bool { explodingSince != nil }

    static let palette: [Color] = [
        Color(red: 0.96, green: 0.31, blue: 0.41),
        Color(red: 0.36, green: 0.78, blue: 0.92),
        Color(red: 0.99, green: 0.78, blue: 0.20),
        Color(red: 0.55, green: 0.93, blue: 0.55),
        Color(red: 0.85, green: 0.45, blue: 0.92),
        Color(red: 0.99, green: 0.55, blue: 0.30),
    ]
}
