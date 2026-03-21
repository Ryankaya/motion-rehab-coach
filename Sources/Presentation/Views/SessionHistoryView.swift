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
                    HStack {
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
                    .padding(10)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                }
            }
        }
    }
}
