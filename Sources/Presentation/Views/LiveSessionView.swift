import SwiftUI

struct LiveSessionView: View {
    @StateObject private var viewModel: LiveSessionViewModel

    init(viewModel: LiveSessionViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
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
    }
}
