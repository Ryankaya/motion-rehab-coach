import AVKit
import SwiftUI

struct TVCoachHomeView: View {
    @StateObject private var viewModel: TVCoachViewModel

    init(viewModel: TVCoachViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        ZStack {
            background
                .ignoresSafeArea()

            VStack(spacing: 20) {
                header

                HStack(spacing: 22) {
                    cameraPanel
                    detailsPanel
                }

                footer
            }
            .padding(.horizontal, 34)
            .padding(.vertical, 26)
        }
        .onAppear {
            viewModel.onAppear()
        }
        .onDisappear {
            viewModel.onDisappear()
        }
        .fullScreenCover(isPresented: $viewModel.isDevicePickerPresented) {
            TVContinuityDevicePickerView(
                onConnected: { _ in
                    viewModel.handlePickerConnected()
                },
                onCancelled: {
                    viewModel.handlePickerCancelled()
                }
            )
            .ignoresSafeArea()
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Motion Rehab Coach TV")
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text(viewModel.statusMessage)
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.white.opacity(0.86))
                    .lineLimit(2)
            }

            Spacer()

            Button {
                if AVContinuityDevicePickerViewController.isSupported {
                    viewModel.openDevicePicker()
                } else {
                    viewModel.reconnectPreferredCamera()
                }
            } label: {
                Label(
                    AVContinuityDevicePickerViewController.isSupported ? "Connect iPhone Camera" : "Reconnect Camera",
                    systemImage: "iphone.gen3.camera"
                )
                .frame(minWidth: 280)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 0.04, green: 0.42, blue: 0.66))

            Button("Stop") {
                viewModel.stopTracking()
            }
            .buttonStyle(.bordered)
        }
    }

    private var cameraPanel: some View {
        ZStack(alignment: .bottomLeading) {
            CameraPreviewView(session: viewModel.captureSession)

            TVPoseOverlay(frame: viewModel.latestPoseFrame)
                .allowsHitTesting(false)

            Text(viewModel.feedback)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.white.opacity(0.30), lineWidth: 1.4)
        )
        .shadow(color: .black.opacity(0.35), radius: 20, y: 12)
    }

    private var detailsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Live Details")
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)

            detailRow(title: "Camera", value: viewModel.cameraName)
            detailRow(title: "Continuity Devices", value: "\(viewModel.continuityCameraCount)")
            detailRow(title: "Visible Joints", value: "\(viewModel.visibleJointCount)/\(BodyJoint.allCases.count)")
            detailRow(title: "Posture Score", value: "\(Int(viewModel.postureScore))%")
            detailRow(title: "Processing FPS", value: String(format: "%.1f", viewModel.estimatedFPS))
            detailRow(title: "State", value: trackingStateLabel)

            Spacer()

            Text("Tip: Place Apple TV and yourself so your full lower body stays in frame.")
                .font(.headline.weight(.medium))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(3)
        }
        .frame(width: 430, alignment: .leading)
        .padding(18)
        .background(.black.opacity(0.30), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.white.opacity(0.20))
        )
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Label("Green lines mean stable posture tracking", systemImage: "checkmark.circle.fill")
            Label("Red lines mean correction needed", systemImage: "exclamationmark.triangle.fill")
        }
        .font(.headline.weight(.semibold))
        .foregroundStyle(.white.opacity(0.88))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func detailRow(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.80))
            Spacer(minLength: 14)
            Text(value)
                .font(.headline.weight(.bold))
                .multilineTextAlignment(.trailing)
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var trackingStateLabel: String {
        switch viewModel.trackingState {
        case .waitingForCamera:
            return "Waiting for Camera"
        case .searchingPose:
            return "Searching Pose"
        case .trackingPose:
            return "Tracking"
        case .stopped:
            return "Stopped"
        }
    }

    private var background: some View {
        LinearGradient(
            colors: [
                Color(red: 0.05, green: 0.09, blue: 0.14),
                Color(red: 0.07, green: 0.14, blue: 0.22)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

private struct TVPoseOverlay: View {
    let frame: PoseFrame?

    private let segments: [(start: BodyJoint, end: BodyJoint)] = [
        (.leftHip, .leftKnee),
        (.leftKnee, .leftAnkle),
        (.rightHip, .rightKnee),
        (.rightKnee, .rightAnkle)
    ]

    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                guard let frame else { return }

                for segment in segments {
                    guard
                        let start = frame.point(for: segment.start),
                        let end = frame.point(for: segment.end)
                    else {
                        continue
                    }

                    var path = Path()
                    path.move(to: point(from: start, in: size))
                    path.addLine(to: point(from: end, in: size))

                    let confidence = min(start.confidence, end.confidence)
                    context.stroke(
                        path,
                        with: .color(lineColor(for: confidence)),
                        style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round)
                    )
                }

                for joint in BodyJoint.allCases {
                    guard let jointPoint = frame.point(for: joint) else { continue }

                    let center = point(from: jointPoint, in: size)
                    let marker = CGRect(x: center.x - 5, y: center.y - 5, width: 10, height: 10)
                    context.fill(Path(ellipseIn: marker), with: .color(lineColor(for: jointPoint.confidence)))
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }

    private func point(from posePoint: PosePoint, in size: CGSize) -> CGPoint {
        CGPoint(
            x: posePoint.x * size.width,
            y: (1 - posePoint.y) * size.height
        )
    }

    private func lineColor(for confidence: Double) -> Color {
        if confidence >= 0.70 {
            return Color(red: 0.16, green: 0.84, blue: 0.36)
        }
        if confidence >= 0.45 {
            return Color(red: 0.96, green: 0.68, blue: 0.18)
        }
        return Color(red: 0.90, green: 0.27, blue: 0.23)
    }
}
