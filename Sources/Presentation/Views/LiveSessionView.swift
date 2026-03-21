import Foundation
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
                calibrationCard
                trackingStatusBanner
                movementGuideCard
                cameraCard
                metricsGrid
                actionCard
            }
            .padding(14)
        }
        .background(backgroundGradient.ignoresSafeArea())
        .navigationTitle(viewModel.selectedExerciseType.displayName)
        .navigationBarTitleDisplayMode(.inline)
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

    private var calibrationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: calibrationIcon)
                    .foregroundStyle(calibrationTint)
                Text("Personalized Calibration")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(viewModel.targetProfileSourceLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Text(viewModel.calibrationMessage)
                .font(.caption)
                .foregroundStyle(.secondary)

            if viewModel.isCalibrating {
                ProgressView(value: viewModel.calibrationProgress)
                    .progressViewStyle(.linear)
                    .tint(Color(red: 0.05, green: 0.44, blue: 0.56))
                Text("\(Int(viewModel.calibrationProgress * 100))%")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                Button(viewModel.isCalibrationReady ? "Recalibrate" : "Run Calibration") {
                    viewModel.runCalibration()
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.03, green: 0.43, blue: 0.53))
                .disabled(viewModel.isCalibrating || viewModel.isSessionRunning)

                if viewModel.isCalibrationReady {
                    Label("Ready", systemImage: "checkmark.seal.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color(red: 0.11, green: 0.66, blue: 0.33))
                }
            }
        }
        .padding(12)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.black.opacity(0.07))
        )
    }

    private var movementGuideCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Movement Guide", systemImage: "figure.strengthtraining.traditional")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("Target \(targetMetricRangeText)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            MovementGuideAnimationView(exerciseType: viewModel.selectedExerciseType)
                .frame(height: 126)
        }
        .padding(12)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.black.opacity(0.07))
        )
    }

    private var cameraCard: some View {
        ZStack(alignment: .bottomLeading) {
            CameraPreviewView(session: viewModel.captureSession)

            PoseCoachingOverlay(
                frame: viewModel.latestPoseFrame,
                jointTargets: viewModel.jointTargets,
                metricInTargetRange: viewModel.metricInTargetRange,
                alignmentScore: viewModel.formAlignmentScore
            )
            .allowsHitTesting(false)

            Text(viewModel.feedback)
                .font(.subheadline.weight(.semibold))
                .padding(10)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                .padding(12)
        }
        .frame(height: 360)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
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
                accent: viewModel.metricInTargetRange
                    ? Color(red: 0.06, green: 0.62, blue: 0.32)
                    : Color(red: 0.93, green: 0.40, blue: 0.08)
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
            } else if viewModel.isCalibrating {
                Button("Calibrating...") {}
                    .buttonStyle(.borderedProminent)
                    .disabled(true)
            } else if !viewModel.isCalibrationReady {
                Button("Run Calibration") {
                    viewModel.runCalibration()
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.03, green: 0.43, blue: 0.53))
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

            Text("Form \(Int(viewModel.formAlignmentScore * 100))%")
                .font(.caption.weight(.semibold))
                .foregroundStyle(formColor)
        }
        .padding(12)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.black.opacity(0.08))
        )
    }

    private var calibrationIcon: String {
        if viewModel.isCalibrating {
            return "viewfinder.circle.fill"
        }
        if viewModel.isCalibrationReady {
            return "checkmark.seal.fill"
        }
        return "exclamationmark.triangle.fill"
    }

    private var calibrationTint: Color {
        if viewModel.isCalibrating {
            return Color(red: 0.07, green: 0.48, blue: 0.58)
        }
        if viewModel.isCalibrationReady {
            return Color(red: 0.10, green: 0.66, blue: 0.33)
        }
        return Color(red: 0.90, green: 0.56, blue: 0.15)
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

    private var formColor: Color {
        if viewModel.formAlignmentScore >= 0.75 {
            return Color(red: 0.10, green: 0.66, blue: 0.33)
        }
        if viewModel.formAlignmentScore >= 0.5 {
            return Color(red: 0.90, green: 0.56, blue: 0.15)
        }
        return Color(red: 0.83, green: 0.22, blue: 0.18)
    }

    private var targetMetricRangeText: String {
        let range = viewModel.targetMetricRange
        if viewModel.primaryMetricUnit == "°" {
            return "\(Int(range.lowerBound))-\(Int(range.upperBound))\(viewModel.primaryMetricUnit)"
        }
        return String(format: "%.1f-%.1f%@", range.lowerBound, range.upperBound, viewModel.primaryMetricUnit)
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

private struct MovementGuideAnimationView: View {
    let exerciseType: ExerciseType
    @State private var animationPhase = 0.0

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(red: 0.94, green: 0.98, blue: 1.0))

            Canvas { context, size in
                let phase = animationPhase
                let depth = CGFloat(movementDepth * phase)

                drawFigure(in: &context, size: size, phase: depth, alpha: 0.30, offset: 0)
                drawFigure(in: &context, size: size, phase: 0, alpha: 0.20, offset: 0)

                var arrow = Path()
                let arrowX = size.width * 0.13
                let topY = size.height * 0.24
                let bottomY = size.height * 0.78
                arrow.move(to: CGPoint(x: arrowX, y: topY))
                arrow.addLine(to: CGPoint(x: arrowX, y: bottomY))
                arrow.move(to: CGPoint(x: arrowX - 6, y: bottomY - 10))
                arrow.addLine(to: CGPoint(x: arrowX, y: bottomY))
                arrow.addLine(to: CGPoint(x: arrowX + 6, y: bottomY - 10))

                context.stroke(
                    arrow,
                    with: .color(Color(red: 0.08, green: 0.45, blue: 0.57).opacity(0.65)),
                    style: StrokeStyle(lineWidth: 2.0, lineCap: .round, lineJoin: .round, dash: [6, 5])
                )
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)

            Text("Mirror this pattern")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color(red: 0.06, green: 0.39, blue: 0.52))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.white.opacity(0.8), in: Capsule())
                .padding(10)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                animationPhase = 1
            }
        }
    }

    private var movementDepth: Double {
        switch exerciseType {
        case .miniSquat:
            return 0.45
        case .sitToStand:
            return 0.75
        case .squat:
            return 0.82
        case .lunge:
            return 0.76
        case .calfRaise:
            return -0.42
        }
    }

    private func drawFigure(
        in context: inout GraphicsContext,
        size: CGSize,
        phase: CGFloat,
        alpha: Double,
        offset: CGFloat
    ) {
        let centerX = size.width * (0.52 + offset)
        let shoulderY = size.height * 0.20 + (exerciseType == .calfRaise ? phase * 8 : phase * 10)
        let hipY = size.height * 0.44 + (exerciseType == .calfRaise ? phase * 4 : phase * 24)
        let kneeY = size.height * 0.67 + (exerciseType == .calfRaise ? phase * 2 : phase * 14)
        let ankleY = size.height * 0.86 + (exerciseType == .calfRaise ? phase * 18 : 0)

        let squatKneeShift = (exerciseType == .squat || exerciseType == .miniSquat || exerciseType == .sitToStand)
            ? (phase * 14)
            : 0
        let lungeSplit: CGFloat = exerciseType == .lunge ? 22 : 0

        let leftHip = CGPoint(x: centerX - 18, y: hipY)
        let rightHip = CGPoint(x: centerX + 18, y: hipY)
        let leftKnee = CGPoint(x: centerX - 18 - squatKneeShift + lungeSplit, y: kneeY)
        let rightKnee = CGPoint(x: centerX + 18 + squatKneeShift - lungeSplit, y: kneeY)
        let leftAnkle = CGPoint(x: centerX - 20 + lungeSplit, y: ankleY)
        let rightAnkle = CGPoint(x: centerX + 20 - lungeSplit, y: ankleY)
        let shoulder = CGPoint(x: centerX, y: shoulderY)

        var body = Path()
        body.move(to: shoulder)
        body.addLine(to: CGPoint(x: centerX, y: hipY - 8))
        body.move(to: leftHip)
        body.addLine(to: rightHip)
        body.move(to: leftHip)
        body.addLine(to: leftKnee)
        body.addLine(to: leftAnkle)
        body.move(to: rightHip)
        body.addLine(to: rightKnee)
        body.addLine(to: rightAnkle)

        let bodyColor = Color(red: 0.06, green: 0.42, blue: 0.54).opacity(alpha)
        context.stroke(
            body,
            with: .color(bodyColor),
            style: StrokeStyle(lineWidth: 4.0, lineCap: .round, lineJoin: .round)
        )

        let headRect = CGRect(x: centerX - 10, y: shoulderY - 24, width: 20, height: 20)
        context.fill(Path(ellipseIn: headRect), with: .color(bodyColor))
    }
}

private struct PoseCoachingOverlay: View {
    let frame: PoseFrame?
    let jointTargets: [BodyJoint: JointTarget]
    let metricInTargetRange: Bool
    let alignmentScore: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topTrailing) {
                targetZones(size: geometry.size)

                Canvas { context, size in
                    guard let frame else { return }

                    for segment in trackedSegments {
                        guard
                            let startPose = frame.point(for: segment.start),
                            let endPose = frame.point(for: segment.end)
                        else {
                            continue
                        }

                        let startPoint = toViewPoint(startPose, size: size)
                        let endPoint = toViewPoint(endPose, size: size)
                        let startValid = isJointInTarget(segment.start, point: startPose)
                        let endValid = isJointInTarget(segment.end, point: endPose)

                        var path = Path()
                        path.move(to: startPoint)
                        path.addLine(to: endPoint)

                        context.stroke(
                            path,
                            with: .color(segmentColor(startValid: startValid, endValid: endValid)),
                            style: StrokeStyle(lineWidth: 5.0, lineCap: .round, lineJoin: .round)
                        )
                    }

                    for joint in BodyJoint.allCases {
                        guard let pose = frame.point(for: joint) else { continue }
                        let isValid = isJointInTarget(joint, point: pose)
                        let center = toViewPoint(pose, size: size)
                        let circleRect = CGRect(x: center.x - 4.5, y: center.y - 4.5, width: 9, height: 9)
                        let color = isValid
                            ? Color(red: 0.11, green: 0.78, blue: 0.35)
                            : Color(red: 0.90, green: 0.27, blue: 0.24)
                        context.fill(Path(ellipseIn: circleRect), with: .color(color))
                    }
                }

                Text("Form \(Int(alignmentScore * 100))%")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        alignmentScore >= 0.75
                            ? Color(red: 0.10, green: 0.66, blue: 0.33)
                            : (alignmentScore >= 0.5
                                ? Color(red: 0.90, green: 0.56, blue: 0.15)
                                : Color(red: 0.83, green: 0.22, blue: 0.18)),
                        in: Capsule()
                    )
                    .padding(10)
            }
        }
    }

    private var trackedSegments: [(start: BodyJoint, end: BodyJoint)] {
        [
            (.leftHip, .leftKnee),
            (.leftKnee, .leftAnkle),
            (.rightHip, .rightKnee),
            (.rightKnee, .rightAnkle)
        ]
    }

    private func targetZones(size: CGSize) -> some View {
        let leftRect = laneRect(for: .left, size: size)
        let rightRect = laneRect(for: .right, size: size)
        let zoneColor = metricInTargetRange
            ? Color(red: 0.10, green: 0.74, blue: 0.32)
            : Color(red: 0.89, green: 0.30, blue: 0.22)

        return ZStack {
            laneView(rect: leftRect, color: zoneColor)
            laneView(rect: rightRect, color: zoneColor)
        }
    }

    private func laneView(rect: CGRect, color: Color) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(color.opacity(0.10))
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)

            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(color.opacity(0.65), style: StrokeStyle(lineWidth: 1.6, dash: [8, 6]))
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
        }
    }

    private func laneRect(for side: OverlayBodySide, size: CGSize) -> CGRect {
        let joints: [BodyJoint] = side == .left
            ? [.leftHip, .leftKnee, .leftAnkle]
            : [.rightHip, .rightKnee, .rightAnkle]

        let targets = joints.compactMap { jointTargets[$0] }
        guard !targets.isEmpty else {
            let fallbackX = side == .left ? size.width * 0.32 : size.width * 0.68
            return CGRect(x: fallbackX - 38, y: size.height * 0.18, width: 76, height: size.height * 0.66)
        }

        let minX = targets.map { $0.x.lowerBound }.min() ?? 0.2
        let maxX = targets.map { $0.x.upperBound }.max() ?? 0.8
        let minY = targets.map { $0.y.lowerBound }.min() ?? 0.1
        let maxY = targets.map { $0.y.upperBound }.max() ?? 0.9

        let paddedX = clampedUnitRange((minX - 0.02)...(maxX + 0.02))
        let paddedY = clampedUnitRange((minY - 0.03)...(maxY + 0.03))

        let x = paddedX.lowerBound * size.width
        let width = max((paddedX.upperBound - paddedX.lowerBound) * size.width, 60)
        let topY = (1 - paddedY.upperBound) * size.height
        let bottomY = (1 - paddedY.lowerBound) * size.height
        let height = max(bottomY - topY, 90)

        return CGRect(x: x, y: topY, width: width, height: height)
    }

    private func segmentColor(startValid: Bool, endValid: Bool) -> Color {
        if startValid && endValid && metricInTargetRange {
            return Color(red: 0.10, green: 0.76, blue: 0.33)
        }
        if startValid || endValid {
            return Color(red: 0.93, green: 0.61, blue: 0.14)
        }
        return Color(red: 0.89, green: 0.28, blue: 0.22)
    }

    private func toViewPoint(_ point: PosePoint, size: CGSize) -> CGPoint {
        CGPoint(
            x: point.x * size.width,
            y: (1 - point.y) * size.height
        )
    }

    private func isJointInTarget(_ joint: BodyJoint, point: PosePoint) -> Bool {
        guard let target = jointTargets[joint] else { return false }
        return target.x.contains(point.x) && target.y.contains(point.y)
    }

    private func clampedUnitRange(_ range: ClosedRange<Double>) -> ClosedRange<Double> {
        max(0.02, range.lowerBound)...min(0.98, range.upperBound)
    }
}

private enum OverlayBodySide {
    case left
    case right
}
