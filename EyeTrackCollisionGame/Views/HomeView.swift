//
//  HomeView.swift
//

import SwiftUI

struct HomeView: View {
    @EnvironmentObject var tracking: EyeTrackingService

    var body: some View {
        ZStack {
            backgroundGradient.ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                VStack(spacing: 8) {
                    Text("Gaze Collision")
                        .font(.system(size: 44, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Pop balls with your eyes.")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.7))
                }

                statusCard
                    .padding(.horizontal, 24)

                Spacer()

                VStack(spacing: 16) {
                    NavigationLink {
                        CalibrationView()
                    } label: {
                        ActionLabel(icon: "scope",
                                    title: tracking.isCalibrated ? "Recalibrate" : "Calibrate",
                                    subtitle: "9-point calibration · ~30 s")
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        GameView()
                    } label: {
                        ActionLabel(icon: "play.fill",
                                    title: "Play",
                                    subtitle: tracking.isCalibrated
                                        ? "Calibration ready"
                                        : "Calibrate first for best accuracy",
                                    enabled: canPlay)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canPlay)

                    if tracking.isCalibrated {
                        Button(role: .destructive) {
                            tracking.clearCalibration()
                        } label: {
                            Text("Clear calibration")
                                .font(.callout)
                                .foregroundStyle(.white.opacity(0.6))
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
        .navigationBarHidden(true)
    }

    private var canPlay: Bool {
        tracking.authorizationState == .authorized
    }

    @ViewBuilder
    private var statusCard: some View {
        switch tracking.authorizationState {
        case .unknown:
            statusRow(icon: "hourglass", text: "Requesting permissions…", tint: .yellow)
        case .authorized:
            statusRow(icon: "checkmark.circle.fill",
                      text: tracking.isCalibrated
                        ? "Ready · calibration on file"
                        : "Camera ready · calibrate to improve accuracy",
                      tint: .green)
        case .denied(let reason):
            statusRow(icon: "exclamationmark.triangle.fill",
                      text: reason,
                      tint: .red)
        case .unsupported:
            statusRow(icon: "xmark.octagon.fill",
                      text: "This device doesn't have a TrueDepth camera.",
                      tint: .red)
        }
    }

    private func statusRow(icon: String, text: String, tint: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(tint)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.85))
            Spacer()
        }
        .padding(14)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
    }

    private var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [Color(red: 0.05, green: 0.07, blue: 0.15),
                     Color(red: 0.02, green: 0.02, blue: 0.06)],
            startPoint: .top, endPoint: .bottom
        )
    }
}

private struct ActionLabel: View {
    let icon: String
    let title: String
    let subtitle: String
    var enabled: Bool = true

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .frame(width: 48, height: 48)
                .background(Color.white.opacity(0.1), in: Circle())
                .foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline).foregroundStyle(.white)
                Text(subtitle).font(.caption).foregroundStyle(.white.opacity(0.6))
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(.white.opacity(0.4))
        }
        .padding(16)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
        .opacity(enabled ? 1 : 0.4)
    }
}
