//
//  DistanceCalibrationSheet.swift
//  facekey
//

import SwiftUI

struct DistanceCalibrationSheet: View {
    let calibrator: DistanceCalibrator
    let onAccept: (_ threshold: Float, _ cameraID: String?) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Calibrate detection distance")
                .font(.headline)

            Text("Using \(calibrator.cameraName ?? "the selected camera") for the \(calibrator.profile.title) profile.")
                .foregroundStyle(.secondary)

            CameraPreviewView(session: calibrator.camera.session, faces: calibrator.faces)
                .frame(height: 240)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay {
                    if case .ready = calibrator.state {
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.green, lineWidth: 3)
                    }
                }

            statusText

            if case .ready = calibrator.state {
                Button("Measure again") { calibrator.retry() }
            }

            HStack {
                Spacer()
                Button("Cancel") { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Button("Accept") {
                    if let threshold = calibrator.proposedThreshold {
                        onAccept(threshold, calibrator.cameraID)
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(calibrator.proposedThreshold == nil)
            }
        }
        .padding(20)
        .frame(width: 420)
        .task { await calibrator.start() }
        .onDisappear { calibrator.stop() }
    }

    @ViewBuilder
    private var statusText: some View {
        switch calibrator.state {
        case .starting:
            Text("Starting camera…")
        case .waiting(let message):
            Text(message)
        case .ready(let width):
            Text(String(format: "OK — measured width %.2f. Unlock will start at %.2f.", width, calibrator.proposedThreshold ?? 0))
        case .failed(let message):
            Text(message)
                .foregroundStyle(.red)
        }
    }
}
