import SwiftUI

struct DashboardView: View {
    @ObservedObject var container: AppContainer
    @StateObject private var historyViewModel: SessionHistoryViewModel

    init(container: AppContainer) {
        self.container = container
        _historyViewModel = StateObject(wrappedValue: container.makeSessionHistoryViewModel())
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Motion Rehab Coach")
                            .font(.largeTitle.weight(.bold))
                        Text("Professional-grade rehab tracking with on-device pose intelligence.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    NavigationLink {
                        LiveSessionView(viewModel: container.makeLiveSessionViewModel())
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Start Guided Squat Session")
                                    .font(.headline)
                                Text("Track reps, depth, and quality in real time.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.secondary)
                        }
                        .padding()
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)

                    SessionHistoryView(viewModel: historyViewModel)
                }
                .padding()
            }
            .navigationTitle("Dashboard")
            .toolbar {
                Button("Refresh") {
                    Task { await historyViewModel.load() }
                }
            }
        }
        .task {
            await historyViewModel.load()
        }
    }
}
