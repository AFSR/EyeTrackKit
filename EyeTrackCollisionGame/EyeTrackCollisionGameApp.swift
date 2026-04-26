//
//  EyeTrackCollisionGameApp.swift
//

import SwiftUI

@main
struct EyeTrackCollisionGameApp: App {
    @StateObject private var tracking = EyeTrackingService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(tracking)
                .preferredColorScheme(.dark)
                .statusBar(hidden: true)
                .persistentSystemOverlays(.hidden)
        }
    }
}
