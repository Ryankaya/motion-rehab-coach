import Foundation
import UIKit

struct SessionTrendPoint: Identifiable {
    let id: UUID
    let date: Date
    let reps: Double
    let quality: Double
    let symmetry: Double
    let tempo: Double
}

@MainActor
final class SessionHistoryViewModel: ObservableObject {
    @Published private(set) var sessions: [ExerciseSession] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isExportingReport = false
    @Published var exportedReportURL: URL?
    @Published var errorMessage: String?

    private let sessionStore: any SessionStore

    init(sessionStore: any SessionStore) {
        self.sessionStore = sessionStore
    }

    var trendPoints: [SessionTrendPoint] {
        sessions
            .prefix(20)
            .reversed()
            .map {
                SessionTrendPoint(
                    id: $0.id,
                    date: $0.startedAt,
                    reps: Double($0.repetitionCount),
                    quality: $0.qualityScore,
                    symmetry: $0.averageSymmetryScore,
                    tempo: averageTempo(session: $0)
                )
            }
    }

    var averageQuality: Double {
        sessions.map(\.qualityScore).average
    }

    var averageSymmetry: Double {
        sessions.map(\.averageSymmetryScore).average
    }

    var averageReps: Double {
        sessions.map { Double($0.repetitionCount) }.average
    }

    var clinicianModeSessionCount: Int {
        sessions.filter(\.clinicianSharingMode).count
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }

        do {
            sessions = try await sessionStore.fetchSessions()
            errorMessage = nil
        } catch {
            errorMessage = "Failed to load sessions: \(error.localizedDescription)"
        }
    }

    func exportReportPDF() async {
        guard !sessions.isEmpty else {
            errorMessage = "No sessions available to export yet."
            return
        }

        isExportingReport = true
        defer { isExportingReport = false }

        do {
            let snapshot = Array(sessions.prefix(30))
            let data = makeReportPDFData(from: snapshot)
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd-HHmmss"
            let fileName = "motion-rehab-report-\(formatter.string(from: Date())).pdf"
            let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
            try data.write(to: fileURL, options: .atomic)

            exportedReportURL = fileURL
            errorMessage = nil
        } catch {
            errorMessage = "Failed to export report: \(error.localizedDescription)"
        }
    }

    private func makeReportPDFData(from sessions: [ExerciseSession]) -> Data {
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)

        return renderer.pdfData { context in
            context.beginPage()
            drawReportHeader(in: context, pageRect: pageRect, sessions: sessions)
            drawSummaryCards(in: context, startY: 116, pageRect: pageRect, sessions: sessions)
            drawCharts(in: context, startY: 220, pageRect: pageRect, sessions: sessions)
            drawFootnote(in: context, pageRect: pageRect)

            context.beginPage()
            drawDetailPage(in: context, pageRect: pageRect, sessions: sessions)
        }
    }

    private func drawReportHeader(
        in context: UIGraphicsPDFRendererContext,
        pageRect: CGRect,
        sessions: [ExerciseSession]
    ) {
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 24, weight: .bold),
            .foregroundColor: UIColor(red: 0.05, green: 0.24, blue: 0.43, alpha: 1)
        ]

        let subtitleAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: UIColor.secondaryLabel
        ]

        ("Motion Rehab Coach - Session Report" as NSString)
            .draw(at: CGPoint(x: 36, y: 36), withAttributes: titleAttributes)

        let period = reportDateRangeDescription(for: sessions)
        ("Generated \(Date().formatted(date: .abbreviated, time: .shortened)) • \(period)" as NSString)
            .draw(at: CGPoint(x: 36, y: 70), withAttributes: subtitleAttributes)

        let divider = UIBezierPath()
        divider.move(to: CGPoint(x: 36, y: 96))
        divider.addLine(to: CGPoint(x: pageRect.width - 36, y: 96))
        UIColor.systemGray4.setStroke()
        divider.lineWidth = 1
        divider.stroke()
    }

    private func drawSummaryCards(
        in context: UIGraphicsPDFRendererContext,
        startY: CGFloat,
        pageRect: CGRect,
        sessions: [ExerciseSession]
    ) {
        let cardWidth = (pageRect.width - 36 - 36 - 16) / 3
        let cardHeight: CGFloat = 88

        let cards = [
            ("Sessions", "\(sessions.count)", UIColor(red: 0.08, green: 0.45, blue: 0.76, alpha: 1)),
            ("Avg Quality", "\(Int(sessions.map(\.qualityScore).average))%", UIColor(red: 0.10, green: 0.63, blue: 0.33, alpha: 1)),
            ("Avg Symmetry", "\(Int(sessions.map(\.averageSymmetryScore).average))%", UIColor(red: 0.77, green: 0.20, blue: 0.40, alpha: 1))
        ]

        for (index, card) in cards.enumerated() {
            let x = 36 + CGFloat(index) * (cardWidth + 8)
            let rect = CGRect(x: x, y: startY, width: cardWidth, height: cardHeight)
            drawSummaryCard(in: context.cgContext, rect: rect, title: card.0, value: card.1, accent: card.2)
        }
    }

    private func drawSummaryCard(
        in cgContext: CGContext,
        rect: CGRect,
        title: String,
        value: String,
        accent: UIColor
    ) {
        let background = UIBezierPath(roundedRect: rect, cornerRadius: 12)
        UIColor.secondarySystemBackground.setFill()
        background.fill()

        let border = UIBezierPath(roundedRect: rect, cornerRadius: 12)
        accent.withAlphaComponent(0.25).setStroke()
        border.lineWidth = 1
        border.stroke()

        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: UIColor.secondaryLabel
        ]
        (title as NSString).draw(at: CGPoint(x: rect.minX + 12, y: rect.minY + 12), withAttributes: titleAttributes)

        let valueAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 28, weight: .bold),
            .foregroundColor: accent
        ]
        (value as NSString).draw(at: CGPoint(x: rect.minX + 12, y: rect.minY + 34), withAttributes: valueAttributes)

        _ = cgContext
    }

    private func drawCharts(
        in context: UIGraphicsPDFRendererContext,
        startY: CGFloat,
        pageRect: CGRect,
        sessions: [ExerciseSession]
    ) {
        let chartWidth = (pageRect.width - 36 - 36 - 12) / 2
        let chartHeight: CGFloat = 220

        let quality = sessions.reversed().map(\.qualityScore)
        let symmetry = sessions.reversed().map(\.averageSymmetryScore)
        let reps = sessions.reversed().map { Double($0.repetitionCount) }
        let tempo = sessions.reversed().map { averageTempo(session: $0) }

        drawLineChart(
            in: context.cgContext,
            frame: CGRect(x: 36, y: startY, width: chartWidth, height: chartHeight),
            title: "Quality Trend",
            values: quality,
            accent: UIColor(red: 0.11, green: 0.60, blue: 0.34, alpha: 1),
            fixedRange: 0...100,
            suffix: "%"
        )

        drawLineChart(
            in: context.cgContext,
            frame: CGRect(x: 36 + chartWidth + 12, y: startY, width: chartWidth, height: chartHeight),
            title: "Symmetry Trend",
            values: symmetry,
            accent: UIColor(red: 0.79, green: 0.20, blue: 0.39, alpha: 1),
            fixedRange: 0...100,
            suffix: "%"
        )

        drawLineChart(
            in: context.cgContext,
            frame: CGRect(x: 36, y: startY + chartHeight + 14, width: chartWidth, height: chartHeight),
            title: "Repetition Trend",
            values: reps,
            accent: UIColor(red: 0.10, green: 0.45, blue: 0.84, alpha: 1),
            fixedRange: nil,
            suffix: " reps"
        )

        drawLineChart(
            in: context.cgContext,
            frame: CGRect(x: 36 + chartWidth + 12, y: startY + chartHeight + 14, width: chartWidth, height: chartHeight),
            title: "Tempo Trend",
            values: tempo,
            accent: UIColor(red: 0.15, green: 0.46, blue: 0.79, alpha: 1),
            fixedRange: 0.8...4.0,
            suffix: " s"
        )
    }

    private func drawLineChart(
        in cgContext: CGContext,
        frame: CGRect,
        title: String,
        values: [Double],
        accent: UIColor,
        fixedRange: ClosedRange<Double>?,
        suffix: String
    ) {
        let backgroundPath = UIBezierPath(roundedRect: frame, cornerRadius: 12)
        UIColor.secondarySystemBackground.setFill()
        backgroundPath.fill()

        let borderPath = UIBezierPath(roundedRect: frame, cornerRadius: 12)
        accent.withAlphaComponent(0.20).setStroke()
        borderPath.lineWidth = 1
        borderPath.stroke()

        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: UIColor.label
        ]
        (title as NSString).draw(at: CGPoint(x: frame.minX + 10, y: frame.minY + 10), withAttributes: titleAttributes)

        guard values.count >= 2 else {
            let textAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 12, weight: .medium),
                .foregroundColor: UIColor.secondaryLabel
            ]
            ("Need at least 2 sessions" as NSString)
                .draw(at: CGPoint(x: frame.minX + 10, y: frame.midY), withAttributes: textAttributes)
            return
        }

        let plotRect = CGRect(
            x: frame.minX + 10,
            y: frame.minY + 36,
            width: frame.width - 20,
            height: frame.height - 54
        )

        let derivedMin = values.min() ?? 0
        let derivedMax = values.max() ?? 1
        var minValue = fixedRange?.lowerBound ?? derivedMin
        var maxValue = fixedRange?.upperBound ?? derivedMax

        if minValue == maxValue {
            minValue -= 1
            maxValue += 1
        }

        let baseline = UIBezierPath(rect: plotRect)
        UIColor.systemGray5.setStroke()
        baseline.lineWidth = 1
        baseline.stroke()

        let pointPath = UIBezierPath()
        var plottedPoints: [CGPoint] = []

        for (index, value) in values.enumerated() {
            let xProgress = Double(index) / Double(max(values.count - 1, 1))
            let normalized = (value - minValue) / max(maxValue - minValue, 0.0001)
            let x = plotRect.minX + CGFloat(xProgress) * plotRect.width
            let y = plotRect.maxY - CGFloat(normalized) * plotRect.height
            let point = CGPoint(x: x, y: y)

            if index == 0 {
                pointPath.move(to: point)
            } else {
                pointPath.addLine(to: point)
            }

            plottedPoints.append(point)
        }

        accent.setStroke()
        pointPath.lineWidth = 2.4
        pointPath.lineJoinStyle = .round
        pointPath.lineCapStyle = .round
        pointPath.stroke()

        if let first = plottedPoints.first, let last = plottedPoints.last {
            let fillPath = UIBezierPath()
            fillPath.move(to: CGPoint(x: first.x, y: plotRect.maxY))
            for point in plottedPoints {
                fillPath.addLine(to: point)
            }
            fillPath.addLine(to: CGPoint(x: last.x, y: plotRect.maxY))
            fillPath.close()

            accent.withAlphaComponent(0.10).setFill()
            fillPath.fill()
        }

        let latest = values.last ?? 0
        let valueText = String(format: "Latest %.1f%@", latest, suffix)
        let valueAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: accent
        ]
        (valueText as NSString).draw(
            at: CGPoint(x: frame.minX + 10, y: frame.maxY - 16),
            withAttributes: valueAttributes
        )

        _ = cgContext
    }

    private func drawFootnote(in context: UIGraphicsPDFRendererContext, pageRect: CGRect) {
        let text = "Generated by Motion Rehab Coach. Metrics are on-device estimates and should be interpreted by a clinician."
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10, weight: .regular),
            .foregroundColor: UIColor.secondaryLabel
        ]

        (text as NSString).draw(
            in: CGRect(x: 36, y: pageRect.height - 40, width: pageRect.width - 72, height: 22),
            withAttributes: attributes
        )
        _ = context
    }

    private func drawDetailPage(
        in context: UIGraphicsPDFRendererContext,
        pageRect: CGRect,
        sessions: [ExerciseSession]
    ) {
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 20, weight: .bold),
            .foregroundColor: UIColor(red: 0.05, green: 0.24, blue: 0.43, alpha: 1)
        ]

        ("Session Details" as NSString)
            .draw(at: CGPoint(x: 36, y: 36), withAttributes: titleAttributes)

        let headerY: CGFloat = 76
        let rowHeight: CGFloat = 26

        let headers = ["Date", "Exercise", "Reps", "Quality", "Symmetry", "Pain", "RPE", "Alerts"]
        let widths: [CGFloat] = [100, 120, 44, 56, 66, 40, 40, 44]

        var x = CGFloat(36)
        for (index, header) in headers.enumerated() {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 11, weight: .semibold),
                .foregroundColor: UIColor.secondaryLabel
            ]
            (header as NSString).draw(
                in: CGRect(x: x, y: headerY, width: widths[index], height: rowHeight),
                withAttributes: attributes
            )
            x += widths[index]
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short

        for (index, session) in sessions.prefix(24).enumerated() {
            let rowY = headerY + 20 + (CGFloat(index) * rowHeight)

            if index % 2 == 0 {
                UIColor.systemGray6.setFill()
                UIBezierPath(
                    roundedRect: CGRect(x: 36, y: rowY - 2, width: pageRect.width - 72, height: rowHeight),
                    cornerRadius: 4
                ).fill()
            }

            let columns = [
                formatter.string(from: session.startedAt),
                session.exerciseType.displayName,
                "\(session.repetitionCount)",
                "\(Int(session.qualityScore))%",
                "\(Int(session.averageSymmetryScore))%",
                "\(session.painScore)",
                "\(session.rpeGoal)",
                "\(session.compensationAlertsCount)"
            ]

            var rowX = CGFloat(36)
            for columnIndex in columns.indices {
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 10, weight: .regular),
                    .foregroundColor: UIColor.label
                ]
                (columns[columnIndex] as NSString).draw(
                    in: CGRect(x: rowX, y: rowY + 4, width: widths[columnIndex], height: rowHeight),
                    withAttributes: attributes
                )
                rowX += widths[columnIndex]
            }
        }

        let note = "Clinician mode sessions: \(sessions.filter(\.clinicianSharingMode).count) / \(sessions.count)"
        let noteAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: UIColor(red: 0.08, green: 0.45, blue: 0.76, alpha: 1)
        ]
        (note as NSString).draw(at: CGPoint(x: 36, y: pageRect.height - 42), withAttributes: noteAttributes)

        _ = context
    }

    private func reportDateRangeDescription(for sessions: [ExerciseSession]) -> String {
        guard let newest = sessions.first?.startedAt, let oldest = sessions.last?.startedAt else {
            return "No session range"
        }
        return "Range: \(oldest.formatted(date: .abbreviated, time: .omitted)) - \(newest.formatted(date: .abbreviated, time: .omitted))"
    }

    private func averageTempo(session: ExerciseSession) -> Double {
        let tempos = [session.averageEccentricTempo, session.averageConcentricTempo].filter { $0 > 0 }
        guard !tempos.isEmpty else { return 0 }
        return tempos.average
    }
}

private extension Array where Element == Double {
    var average: Double {
        guard !isEmpty else { return 0 }
        return reduce(0, +) / Double(count)
    }
}
