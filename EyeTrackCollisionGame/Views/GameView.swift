//
//  GameView.swift
//
//  The collision game itself: bouncing balls, gaze cursor, score & timer.
//

import SwiftUI
import Combine
import EyeTrackKit

struct GameView: View {
    @EnvironmentObject var tracking: EyeTrackingService
    @Environment(\.dismiss) private var dismiss

    @StateObject private var engine = GameEngine()
    @State private var gazeSubscription: AnyCancellable?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color(red: 0.04, green: 0.05, blue: 0.10).ignoresSafeArea()

                // Hidden eye tracker — drives the gaze stream.
                tracking.controller.view
                    .frame(width: 1, height: 1)
                    .opacity(0)
                    .allowsHitTesting(false)

                // Balls
                ForEach(engine.balls) { ball in
                    BallView(ball: ball)
                }

                // Gaze cursor
                GazeCursor(point: engine.gazePoint, radius: engine.tuning.gazeRadius)

                hud(in: geo.size)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)

                if engine.isFinished {
                    gameOverOverlay
                }
            }
            .onAppear {
                startSession(in: geo.frame(in: .local))
            }
            .onChange(of: geo.size) { _ in
                engine.updateBounds(geo.frame(in: .local))
            }
            .onDisappear {
                stopSession()
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    stopSession()
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding(8)
                        .background(.ultraThinMaterial, in: Circle())
                }
            }
        }
    }

    // MARK: - HUD

    private func hud(in size: CGSize) -> some View {
        VStack {
            HStack {
                Label {
                    Text("\(engine.score)")
                        .font(.title2.weight(.heavy).monospacedDigit())
                } icon: {
                    Image(systemName: "target")
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())

                Spacer()

                if let limit = engine.tuning.roundDuration {
                    Label {
                        Text(timeString(remaining: max(0, limit - engine.elapsed)))
                            .font(.title3.weight(.semibold).monospacedDigit())
                    } icon: {
                        Image(systemName: "timer")
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                }
            }
            Spacer()
        }
    }

    private var gameOverOverlay: some View {
        VStack(spacing: 20) {
            Text("Time's up")
                .font(.system(size: 36, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
            VStack(spacing: 4) {
                Text("Final score")
                    .foregroundStyle(.white.opacity(0.6))
                Text("\(engine.score)")
                    .font(.system(size: 64, weight: .black).monospacedDigit())
                    .foregroundStyle(.white)
            }
            HStack(spacing: 12) {
                Button {
                    dismiss()
                } label: {
                    Text("Home")
                        .font(.headline)
                        .padding(.vertical, 14).frame(maxWidth: .infinity)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(.white)
                }
                Button {
                    restart()
                } label: {
                    Text("Play again")
                        .font(.headline)
                        .padding(.vertical, 14).frame(maxWidth: .infinity)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(.black)
                }
            }
            .padding(.horizontal, 24)
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 28)
        .background(Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 24))
        .padding(.horizontal, 24)
    }

    // MARK: - Session

    private func startSession(in bounds: CGRect) {
        tracking.controller.start()
        engine.start(in: bounds)
        gazeSubscription = tracking.controller.gazeEvents.publisher
            .receive(on: DispatchQueue.main)
            .sink { event in
                engine.gazePoint = event.point
            }
    }

    private func stopSession() {
        gazeSubscription?.cancel()
        gazeSubscription = nil
        engine.stop()
        tracking.controller.pause()
    }

    private func restart() {
        engine.start(in: engine.bounds == .zero
                     ? UIScreen.main.bounds
                     : engine.bounds)
    }

    private func timeString(remaining: TimeInterval) -> String {
        let total = Int(remaining.rounded(.up))
        let m = total / 60
        let s = total % 60
        return String(format: "%01d:%02d", m, s)
    }
}

// MARK: - Subviews

private struct BallView: View {
    let ball: Ball

    var body: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [ball.color.opacity(1.0), ball.color.opacity(0.7)],
                    center: .init(x: 0.35, y: 0.35),
                    startRadius: 1, endRadius: ball.radius
                )
            )
            .overlay(
                Circle().stroke(Color.white.opacity(0.18), lineWidth: 1)
            )
            .frame(width: ball.radius * 2, height: ball.radius * 2)
            .scaleEffect(ball.isExploding ? 1.6 : 1.0)
            .opacity(ball.isExploding ? 0.0 : 1.0)
            .animation(.easeOut(duration: 0.25), value: ball.isExploding)
            .position(ball.position)
            .allowsHitTesting(false)
    }
}

private struct GazeCursor: View {
    let point: CGPoint
    let radius: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.25), lineWidth: 1.5)
                .frame(width: radius * 4, height: radius * 4)
            Circle()
                .fill(Color.white.opacity(0.15))
                .frame(width: radius * 2, height: radius * 2)
            Circle()
                .fill(Color.white)
                .frame(width: 8, height: 8)
        }
        .position(point)
        .allowsHitTesting(false)
        .animation(.linear(duration: 0.05), value: point)
    }
}

