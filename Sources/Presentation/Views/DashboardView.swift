import SwiftUI

struct DashboardView: View {
    @ObservedObject var container: AppContainer
    @StateObject private var historyViewModel: SessionHistoryViewModel

    @State private var selectedExerciseType: ExerciseType = .squat
    @State private var painScore = 2.0
    @State private var rpeGoal = 6.0
    @State private var clinicianSharingMode = false
    @State private var metronomeEnabled = true

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
                        readinessCard
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

            Text("Choose a guided protocol, calibrate once, then train with live form correction and voice coaching.")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.92))

            HStack(spacing: 10) {
                pill("Adaptive Targets")
                pill("Tempo Coaching")
                pill("Session Reports")
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

    private var readinessCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Pre-Session Setup")
                    .font(.headline)
                Spacer()
                Text(protocolIntensityLabel)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(protocolIntensityColor.opacity(0.20), in: Capsule())
                    .foregroundStyle(protocolIntensityColor)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Pain (0-10)")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(Int(painScore))/10")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color(red: 0.84, green: 0.35, blue: 0.18))
                }

                Slider(value: $painScore, in: 0...10, step: 1)
                    .tint(Color(red: 0.84, green: 0.35, blue: 0.18))
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("RPE Goal (1-10)")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(Int(rpeGoal))/10")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color(red: 0.05, green: 0.43, blue: 0.62))
                }

                Slider(value: $rpeGoal, in: 1...10, step: 1)
                    .tint(Color(red: 0.05, green: 0.43, blue: 0.62))
            }

            Toggle(isOn: $metronomeEnabled) {
                Label("Tempo Metronome", systemImage: "metronome")
                    .font(.subheadline.weight(.semibold))
            }

            Toggle(isOn: $clinicianSharingMode) {
                Label("Clinician Sharing Mode", systemImage: "person.2.badge.gearshape")
                    .font(.subheadline.weight(.semibold))
            }

            Text(protocolSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.black.opacity(0.08))
        )
    }

    private var startSessionCard: some View {
        NavigationLink {
            LiveSessionView(
                viewModel: container.makeLiveSessionViewModel(
                    exerciseType: selectedExerciseType,
                    painScore: Int(painScore),
                    rpeGoal: Int(rpeGoal),
                    clinicianSharingMode: clinicianSharingMode,
                    metronomeEnabled: metronomeEnabled
                )
            )
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
                    labelBadge("Pain \(Int(painScore))/10")
                    labelBadge("RPE \(Int(rpeGoal))/10")
                    if metronomeEnabled {
                        labelBadge("Metronome on")
                    }
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

    private var protocolIntensityLabel: String {
        if painScore >= 7 || rpeGoal <= 4 {
            return "Conservative"
        }
        if painScore >= 4 || rpeGoal <= 6 {
            return "Moderate"
        }
        return "Standard"
    }

    private var protocolIntensityColor: Color {
        switch protocolIntensityLabel {
        case "Conservative":
            return Color(red: 0.83, green: 0.30, blue: 0.20)
        case "Moderate":
            return Color(red: 0.88, green: 0.58, blue: 0.16)
        default:
            return Color(red: 0.09, green: 0.62, blue: 0.34)
        }
    }

    private var protocolSummary: String {
        let exerciseContext: String
        switch selectedExerciseType {
        case .calfRaise:
            exerciseContext = "Lift height"
        case .squat, .sitToStand, .lunge, .miniSquat:
            exerciseContext = "Depth target"
        }

        return "\(exerciseContext) auto-adjusts from pain \(Int(painScore))/10 and RPE \(Int(rpeGoal))/10. " +
            "Use clinician mode when you plan to export reports for therapist review."
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
