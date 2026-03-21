import SwiftUI

struct DashboardView: View {
    @ObservedObject var container: AppContainer
    @StateObject private var historyViewModel: SessionHistoryViewModel
    @State private var selectedExerciseType: ExerciseType = .squat

    init(container: AppContainer) {
        self.container = container
        _historyViewModel = StateObject(wrappedValue: container.makeSessionHistoryViewModel())
    }

    var body: some View {
        NavigationStack {
            ZStack {
                backgroundGradient
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        heroCard
                        exercisePickerCard
                        startSessionCard
                        SessionHistoryView(viewModel: historyViewModel)
                    }
                    .padding(16)
                }
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

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Motion Rehab Coach")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text("Choose a guided protocol, then train with real-time on-device form feedback and voice direction.")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.92))

            HStack(spacing: 10) {
                pill("Live Tracking")
                pill("Voice Coaching")
                pill("Offline Sessions")
            }
            .padding(.top, 4)
        }
        .padding(18)
        .background(
            LinearGradient(
                colors: [Color(red: 0.03, green: 0.29, blue: 0.50), Color(red: 0.06, green: 0.47, blue: 0.57)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(.white.opacity(0.18))
        )
    }

    private var exercisePickerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Select Program")
                .font(.headline)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(ExerciseType.allCases) { exercise in
                        exerciseChip(for: exercise)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(0.3))
        )
    }

    private var startSessionCard: some View {
        NavigationLink {
            LiveSessionView(viewModel: container.makeLiveSessionViewModel(exerciseType: selectedExerciseType))
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: selectedExerciseType.systemImage)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color(red: 0.03, green: 0.33, blue: 0.57))
                    Text("Start \(selectedExerciseType.displayName)")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Color(red: 0.03, green: 0.38, blue: 0.54))
                }

                Text(selectedExerciseType.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    labelBadge("Metric: \(selectedExerciseType.primaryMetricTitle)")
                    labelBadge("Voice enabled")
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(.systemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.08))
            )
        }
        .buttonStyle(.plain)
    }

    private func exerciseChip(for exercise: ExerciseType) -> some View {
        let isSelected = selectedExerciseType == exercise

        return Button {
            selectedExerciseType = exercise
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: exercise.systemImage)
                        .font(.subheadline.weight(.semibold))
                    Text(exercise.displayName)
                        .font(.subheadline.weight(.semibold))
                }
                Text(exercise.subtitle)
                    .font(.caption)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: 200, alignment: .leading)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? Color(red: 0.05, green: 0.38, blue: 0.56) : Color(.systemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(isSelected ? Color.clear : Color.black.opacity(0.08))
            )
            .foregroundStyle(isSelected ? .white : .primary)
        }
    }

    private func pill(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.white.opacity(0.22), in: Capsule())
            .foregroundStyle(.white)
    }

    private func labelBadge(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(red: 0.94, green: 0.98, blue: 1.0), in: Capsule())
            .foregroundStyle(Color(red: 0.02, green: 0.32, blue: 0.51))
    }

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color(red: 0.96, green: 0.98, blue: 1.0),
                Color(red: 0.90, green: 0.95, blue: 0.98)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}
