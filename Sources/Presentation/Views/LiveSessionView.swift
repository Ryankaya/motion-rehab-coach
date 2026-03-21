import SwiftUI

struct LiveSessionView: View {
    @StateObject private var viewModel: LiveSessionViewModel

    init(viewModel: LiveSessionViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                headerCard
                trackingStatusBanner
                cameraCard
                metricsGrid
                actionCard
            }
            .padding(14)
        }
        .background(backgroundGradient.ignoresSafeArea())
        .navigationTitle(viewModel.selectedExerciseType.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if !viewModel.isSessionRunning {
                viewModel.startSession()
            }
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(viewModel.selectedExerciseType.subtitle)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            Toggle(isOn: $viewModel.voiceCoachingEnabled) {
                Label("Voice Direction", systemImage: "waveform.and.mic")
                    .font(.subheadline.weight(.semibold))
            }
            .toggleStyle(.switch)
        }
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.25))
        )
    }

    private var cameraCard: some View {
        CameraPreviewView(session: viewModel.captureSession)
            .frame(height: 360)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(alignment: .bottomLeading) {
                Text(viewModel.feedback)
                    .font(.subheadline.weight(.semibold))
                    .padding(10)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                    .padding(12)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.35), lineWidth: 1.2)
            )
            .shadow(color: .black.opacity(0.12), radius: 12, y: 8)
    }

    private var metricsGrid: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                MetricCardView(
                    title: "Repetitions",
                    value: "\(viewModel.repetitionCount)",
                    accent: Color(red: 0.10, green: 0.44, blue: 0.84)
                )
                MetricCardView(
                    title: "Quality",
                    value: "\(Int(viewModel.qualityScore))%",
                    accent: Color(red: 0.02, green: 0.54, blue: 0.41)
                )
            }

            MetricCardView(
                title: viewModel.primaryMetricTitle,
                value: "\(Int(viewModel.currentPrimaryMetricValue))\(viewModel.primaryMetricUnit)",
                accent: Color(red: 0.93, green: 0.40, blue: 0.08)
            )
        }
    }

    private var actionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if viewModel.isSessionRunning {
                Button("End Session") {
                    viewModel.stopSession()
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.78, green: 0.18, blue: 0.14))
            } else {
                Button("Start Session") {
                    viewModel.startSession()
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.03, green: 0.43, blue: 0.53))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.black.opacity(0.07))
        )
    }

    private var trackingStatusBanner: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)

            Text(statusText)
                .font(.subheadline.weight(.semibold))

            Spacer()

            Text("Joints \(viewModel.visibleJointCount)/6")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.black.opacity(0.08))
        )
    }

    private var statusText: String {
        switch viewModel.trackingState {
        case .idle:
            return "Idle"
        case .searching:
            return "Searching for pose"
        case .tracking:
            return "Tracking active"
        }
    }

    private var statusColor: Color {
        switch viewModel.trackingState {
        case .idle:
            return .gray
        case .searching:
            return Color(red: 0.88, green: 0.58, blue: 0.16)
        case .tracking:
            return Color(red: 0.09, green: 0.67, blue: 0.38)
        }
    }

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color(red: 0.96, green: 0.98, blue: 1.0),
                Color(red: 0.88, green: 0.94, blue: 0.98)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}
