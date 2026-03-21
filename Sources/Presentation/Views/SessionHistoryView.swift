import SwiftUI

struct SessionHistoryView: View {
    @ObservedObject var viewModel: SessionHistoryViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Sessions")
                .font(.headline)

            if viewModel.sessions.isEmpty {
                Text("No sessions yet. Complete a live session to see metrics here.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.sessions.prefix(5)) { session in
                    HStack(spacing: 12) {
                        Image(systemName: session.exerciseType.systemImage)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Color(red: 0.03, green: 0.39, blue: 0.54))
                            .frame(width: 34, height: 34)
                            .background(Color(red: 0.91, green: 0.97, blue: 1.0), in: RoundedRectangle(cornerRadius: 8))

                        VStack(alignment: .leading, spacing: 4) {
                            Text(session.exerciseType.displayName)
                                .font(.subheadline.weight(.semibold))
                            Text(session.startedAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 4) {
                            Text("\(session.repetitionCount) reps")
                                .font(.subheadline.weight(.semibold))
                            Text("Quality \(Int(session.qualityScore))%")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(12)
                    .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.black.opacity(0.07))
                    )
                }
            }
        }
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(0.30))
        )
    }
}
