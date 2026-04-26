//
//  ContentView.swift
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var tracking: EyeTrackingService

    var body: some View {
        NavigationStack {
            HomeView()
        }
        .task {
            if tracking.authorizationState == .unknown {
                await tracking.requestAuthorization()
            }
        }
    }
}
