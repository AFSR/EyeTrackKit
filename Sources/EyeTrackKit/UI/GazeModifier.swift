//
//  GazeModifier.swift
//
//
//  SwiftUI view modifiers that fire when the user's gaze enters, dwells on,
//  or exits a view.
//
//  Caveats:
//   - The gaze point reported by EyeTrack is in the configured
//     `coordinateSpace`. These modifiers expect `.screenPoints`. If you
//     configure `.normalized`, multiply by the screen size before comparing.
//   - The gaze point is in *screen* coordinates (top-left origin). We use
//     `GeometryReader.frame(in: .global)` which returns window coordinates;
//     in single-window apps these are equivalent for the main window.
//

import SwiftUI

@available(iOS 16.0, *)
public extension View {
    /// Fires `action` once each time the gaze enters this view's frame and
    /// stays inside for `dwell`.
    func onGazeEnter(eyeTrack: EyeTrack,
                     dwell: TimeInterval = 0.3,
                     perform action: @escaping () -> Void) -> some View {
        modifier(GazeDwellModifier(eyeTrack: eyeTrack, dwell: dwell, action: action))
    }

    /// Fires `action` whenever the gaze leaves this view's frame.
    func onGazeExit(eyeTrack: EyeTrack,
                    perform action: @escaping () -> Void) -> some View {
        modifier(GazeExitModifier(eyeTrack: eyeTrack, action: action))
    }
}

@available(iOS 16.0, *)
private struct GazeDwellModifier: ViewModifier {
    @ObservedObject var eyeTrack: EyeTrack
    let dwell: TimeInterval
    let action: () -> Void

    @State private var entryTime: Date?
    @State private var hasFired: Bool = false
    @State private var frame: CGRect = .zero

    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear { frame = geo.frame(in: .global) }
                        .onChange(of: geo.frame(in: .global)) { newValue in
                            frame = newValue
                        }
                }
            )
            .onChange(of: eyeTrack.lookAtPoint) { newPoint in
                let inside = frame.contains(newPoint)
                if inside {
                    if entryTime == nil { entryTime = Date(); hasFired = false }
                    if !hasFired,
                       let start = entryTime,
                       Date().timeIntervalSince(start) >= dwell {
                        hasFired = true
                        action()
                    }
                } else {
                    entryTime = nil
                    hasFired = false
                }
            }
    }
}

@available(iOS 16.0, *)
private struct GazeExitModifier: ViewModifier {
    @ObservedObject var eyeTrack: EyeTrack
    let action: () -> Void

    @State private var wasInside: Bool = false
    @State private var frame: CGRect = .zero

    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear { frame = geo.frame(in: .global) }
                        .onChange(of: geo.frame(in: .global)) { newValue in
                            frame = newValue
                        }
                }
            )
            .onChange(of: eyeTrack.lookAtPoint) { newPoint in
                let inside = frame.contains(newPoint)
                if wasInside && !inside { action() }
                wasInside = inside
            }
    }
}
