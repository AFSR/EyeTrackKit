//
//  CalibrationView.swift
//
//  9-point calibration session driven by EyeTrackKit's `Calibrator`. The
//  user fixates each pulsing target while we collect raw gaze samples,
//  then we fit an affine transform and persist the resulting profile.
//

import SwiftUI
import EyeTrackKit

struct CalibrationView: View {
    @EnvironmentObject var tracking: EyeTrackingService
    @Environment(\.dismiss) private var dismiss

    @State private var calibrator: Calibrator?
    @State private var currentTargetIndex: Int = 0
    @State private var collected: Int = 0
    @State private var statusMessage: String = "Look at each dot until it disappears."
    @State private var residual: Double?
    @State private var phase: Phase = .pre

    @State private var targets: [CalibrationTarget] = []
    @State private var screenSize: CGSize = .zero

    private enum Phase { case pre, running, success, failed }
    private let samplesPerTarget = 30

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()

                // Background eye tracker (hidden) to feed the calibrator.
                tracking.controller.view
                    .frame(width: 1, height: 1)
                    .opacity(0)
                    .allowsHitTesting(false)

                switch phase {
                case .pre:
                    introOverlay(in: geo.size)
                case .running:
                    runningOverlay(in: geo.size)
                case .success:
                    resultOverlay(success: true)
                case .failed:
                    resultOverlay(success: false)
                }
            }
            .onAppear {
                screenSize = geo.size
                tracking.controller.start()
            }
            .onDisappear {
                calibrator?.cancel()
                tracking.controller.pause()
            }
        }
        .navigationTitle("Calibration")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    // MARK: - Phases

    private func introOverlay(in size: CGSize) -> some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "scope")
                .font(.system(size: 56))
                .foregroundStyle(.white)
            Text("9-point calibration")
                .font(.title.weight(.semibold))
                .foregroundStyle(.white)
            Text("Hold the device ~30 cm from your face. Keep your head still and follow the dot with your eyes only.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.75))
                .padding(.horizontal, 32)
            Spacer()
            Button {
                begin(in: size)
            } label: {
                Text("Start")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(.black)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 32)
        }
    }

    private func runningOverlay(in size: CGSize) -> some View {
        ZStack {
            // Progress text top-center.
            VStack {
                Text("\(currentTargetIndex + 1) / \(targets.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.7))
                ProgressView(value: Double(collected), total: Double(samplesPerTarget))
                    .frame(width: 120)
                    .tint(.white)
            }
            .padding(.top, 24)
            .frame(maxHeight: .infinity, alignment: .top)

            if currentTargetIndex < targets.count {
                CalibrationDot(point: targets[currentTargetIndex].point,
                                progress: CGFloat(collected) / CGFloat(samplesPerTarget))
            }
        }
    }

    private func resultOverlay(success: Bool) -> some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: success ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 64))
                .foregroundStyle(success ? .green : .yellow)
            Text(success ? "Calibration complete" : "Calibration failed")
                .font(.title.weight(.semibold))
                .foregroundStyle(.white)
            if let residual {
                Text(String(format: "Mean error: %.1f points", residual))
                    .foregroundStyle(.white.opacity(0.75))
            }
            Text(statusMessage)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.65))
                .padding(.horizontal, 32)
            Spacer()
            Button {
                dismiss()
            } label: {
                Text("Done")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(.black)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 32)
        }
    }

    // MARK: - Calibration flow

    private func begin(in size: CGSize) {
        let layout: Calibrator.Layout = .nineGrid
        let targets = Calibrator.standardTargets(layout, in: size)
        let calibrator = Calibrator(
            eyeTrack: tracking.controller.eyeTrack,
            targets: targets,
            configuration: .init(samplesPerTarget: samplesPerTarget,
                                 settleDelay: 0.5,
                                 minimumConfidence: 0.25)
        )
        self.targets = targets
        self.calibrator = calibrator
        self.currentTargetIndex = 0
        self.collected = 0
        self.phase = .running
        calibrator.start()

        // Drive the calibrator: poll its `collectedCount` and advance when
        // each target is fully sampled.
        Task { @MainActor in
            while phase == .running, let cal = self.calibrator {
                if case .running(let idx) = cal.state {
                    currentTargetIndex = idx
                    collected = cal.collectedCount
                    if cal.collectedCount >= samplesPerTarget {
                        cal.advance()
                        try? await Task.sleep(nanoseconds: 250_000_000)
                    }
                }
                if cal.state == .finished { finish(); return }
                if cal.state == .cancelled { return }
                try? await Task.sleep(nanoseconds: 16_000_000) // ~60 Hz
            }
        }
    }

    private func finish() {
        guard let calibrator else { return }
        do {
            let profile = try calibrator.finish()
            tracking.applyCalibration(profile)
            _ = try? tracking.saveCurrentCalibration()
            residual = profile.meanResidual
            statusMessage = "Calibration saved. You can recalibrate anytime."
            phase = .success
        } catch {
            statusMessage = error.localizedDescription
            phase = .failed
        }
    }
}

private struct CalibrationDot: View {
    let point: CGPoint
    let progress: CGFloat

    @State private var pulsing = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.3), lineWidth: 2)
                .frame(width: 56, height: 56)
                .scaleEffect(pulsing ? 1.3 : 0.9)
                .opacity(pulsing ? 0 : 1)
            Circle()
                .trim(from: 0, to: max(0.001, progress))
                .stroke(Color.white, style: .init(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 36, height: 36)
            Circle()
                .fill(Color.white)
                .frame(width: 14, height: 14)
        }
        .position(point)
        .onAppear {
            withAnimation(.easeOut(duration: 1.0).repeatForever(autoreverses: false)) {
                pulsing = true
            }
        }
    }
}
