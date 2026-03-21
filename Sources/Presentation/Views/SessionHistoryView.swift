import Charts
import SwiftUI

struct SessionHistoryView: View {
    @ObservedObject var viewModel: SessionHistoryViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerRow

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if viewModel.sessions.isEmpty {
                Text("No sessions yet. Complete a live session to see metrics here.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                summaryCards
                trendCard
                reportShareCard

                ForEach(viewModel.sessions.prefix(6)) { session in
                    sessionCard(session)
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

    private var headerRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Recent Sessions")
                    .font(.headline)
                if !viewModel.sessions.isEmpty {
                    Text("Clinician mode: \(viewModel.clinicianModeSessionCount)/\(viewModel.sessions.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button {
                Task { await viewModel.exportReportPDF() }
            } label: {
                if viewModel.isExportingReport {
                    Label("Generating...", systemImage: "doc.badge.gearshape")
                } else {
                    Label("Export PDF", systemImage: "doc.text")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.sessions.isEmpty || viewModel.isExportingReport)
        }
    }

    private var summaryCards: some View {
        HStack(spacing: 10) {
            summaryCard(title: "Avg Reps", value: String(format: "%.1f", viewModel.averageReps), accent: Color(red: 0.09, green: 0.45, blue: 0.82))
            summaryCard(title: "Avg Quality", value: "\(Int(viewModel.averageQuality))%", accent: Color(red: 0.10, green: 0.62, blue: 0.34))
            summaryCard(title: "Avg Symmetry", value: "\(Int(viewModel.averageSymmetry))%", accent: Color(red: 0.77, green: 0.20, blue: 0.40))
        }
    }

    private var trendCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Trend Overview")
                .font(.subheadline.weight(.semibold))

            if viewModel.trendPoints.count >= 2 {
                Chart(viewModel.trendPoints) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Quality", point.quality)
                    )
                    .foregroundStyle(Color(red: 0.10, green: 0.62, blue: 0.34))
                    .lineStyle(.init(lineWidth: 2.2, lineCap: .round, lineJoin: .round))

                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Symmetry", point.symmetry)
                    )
                    .foregroundStyle(Color(red: 0.77, green: 0.20, blue: 0.40))
                    .lineStyle(.init(lineWidth: 2.2, lineCap: .round, lineJoin: .round))

                    PointMark(
                        x: .value("Date", point.date),
                        y: .value("Quality", point.quality)
                    )
                    .foregroundStyle(Color(red: 0.10, green: 0.62, blue: 0.34))
                    .symbolSize(22)
                }
                .chartYScale(domain: 0...100)
                .chartLegend(position: .bottom, spacing: 14)
                .frame(height: 180)
            } else {
                Text("Complete at least two sessions to display trends.")
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

    private var reportShareCard: some View {
        Group {
            if let reportURL = viewModel.exportedReportURL {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Latest report ready")
                            .font(.subheadline.weight(.semibold))
                        Text(reportURL.lastPathComponent)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    ShareLink(item: reportURL) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.bordered)
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

    private func sessionCard(_ session: ExerciseSession) -> some View {
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
                Text("Pain \(session.painScore)/10 • RPE \(session.rpeGoal)/10")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text("\(session.repetitionCount) reps")
                    .font(.subheadline.weight(.semibold))
                Text("Q \(Int(session.qualityScore))% • S \(Int(session.averageSymmetryScore))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Alerts \(session.compensationAlertsCount)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(session.compensationAlertsCount == 0 ? Color(red: 0.09, green: 0.62, blue: 0.34) : Color(red: 0.84, green: 0.28, blue: 0.20))
            }
        }
        .padding(12)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.black.opacity(0.07))
        )
    }

    private func summaryCard(title: String, value: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(accent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(accent.opacity(0.24))
        )
    }
}
