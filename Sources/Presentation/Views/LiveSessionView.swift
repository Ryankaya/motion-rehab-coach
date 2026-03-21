import SwiftUI

struct LiveSessionView: View {
    @StateObject private var viewModel: LiveSessionViewModel

    init(viewModel: LiveSessionViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                trackingStatusBanner

                CameraPreviewView(session: viewModel.captureSession)
                    .frame(height: 340)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(alignment: .bottomLeading) {
                        Text(viewModel.feedback)
                            .font(.subheadline.weight(.semibold))
                            .padding(10)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                            .padding(12)
                    }

                HStack(spacing: 10) {
                    MetricCardView(
                        title: "Repetitions",
                        value: "\(viewModel.repetitionCount)",
                        accent: .blue
                    )
                    MetricCardView(
                        title: "Quality",
                        value: "\(Int(viewModel.qualityScore))%",
                        accent: .green
                    )
                }

                MetricCardView(
                    title: "Current Knee Angle",
                    value: "\(Int(viewModel.currentKneeAngle))°",
                    accent: .orange
                )

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if viewModel.isSessionRunning {
                    Button("End Session") {
                        viewModel.stopSession()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                } else {
                    Button("Start Session") {
                        viewModel.startSession()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
        }
        .navigationTitle("Live Rehab Session")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if !viewModel.isSessionRunning {
                viewModel.startSession()
            }
        }
    }

    private var trackingStatusBanner: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)

            Text(statusText)
                .font(.subheadline.weight(.semibold))

            Spacer()

            Text("Joints: \(viewModel.visibleJointCount)/6")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
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
            return .orange
        case .tracking:
            return .green
        }
    }
}
