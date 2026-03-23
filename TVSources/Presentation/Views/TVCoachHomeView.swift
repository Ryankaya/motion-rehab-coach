import SwiftUI

struct TVCoachHomeView: View {
    @StateObject private var viewModel: TVCoachViewModel
    @State private var isTrainingMenuExpanded = false
    @FocusState private var focusedLeftControl: LeftRailFocus?

    private enum LeftRailFocus: Hashable {
        case connectCamera
        case trainingMenu
        case training(TVExerciseProgram)
        case calibrate
        case session
    }

    init(viewModel: TVCoachViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        ZStack {
            background
                .ignoresSafeArea()

            if showsConnectView {
                connectView
            } else {
                liveCameraView
            }
        }
        .onAppear {
            viewModel.onAppear()
        }
        .onDisappear {
            viewModel.onDisappear()
        }
        .onChange(of: focusedLeftControl) { _, next in
            if next == nil {
                isTrainingMenuExpanded = false
            }
        }
        .fullScreenCover(isPresented: $viewModel.isDevicePickerPresented) {
            TVContinuityDevicePickerView(
                onConnected: { device in
                    viewModel.handlePickerConnected(device)
                },
                onCancelled: {
                    viewModel.handlePickerCancelled()
                }
            )
            .ignoresSafeArea()
        }
    }

    private var showsConnectView: Bool {
        viewModel.continuityCameraCount == 0 && viewModel.trackingState == .waitingForCamera
    }

    private var shouldShowReconnectButton: Bool {
        viewModel.continuityCameraCount == 0 || viewModel.trackingState == .waitingForCamera
    }

    private var sessionSummaryText: String {
        if viewModel.isSessionRunning {
            return "Session running • \(viewModel.sessionDurationLabel)"
        }
        if viewModel.isCalibrating {
            return "Calibrating… \(Int(viewModel.calibrationProgress * 100))%"
        }
        if viewModel.isCalibrationReady {
            return "Calibrated and ready"
        }
        return "Calibration required before starting"
    }

    private var showRailLabels: Bool {
        focusedLeftControl != nil
    }

    private var connectView: some View {
        VStack(spacing: 22) {
            Image(systemName: "iphone.gen3.camera")
                .font(.system(size: 64, weight: .semibold))
                .foregroundStyle(Color(red: 0.24, green: 0.79, blue: 0.93))

            Text("Connect iPhone Camera")
                .font(.system(size: 46, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text("Use Continuity Camera to start lower-body rehab coaching on Apple TV.")
                .font(.title3.weight(.medium))
                .foregroundStyle(.white.opacity(0.84))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 820)

            Button {
                viewModel.openDevicePicker()
            } label: {
                Label("Connect iPhone or iPad", systemImage: "link")
                    .font(.title3.weight(.bold))
                    .padding(.horizontal, 30)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 0.03, green: 0.45, blue: 0.77))

            Text(viewModel.statusMessage)
                .font(.headline.weight(.medium))
                .foregroundStyle(.white.opacity(0.76))
                .lineLimit(2)
                .padding(.top, 4)
        }
        .padding(38)
        .background(.black.opacity(0.34), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(.white.opacity(0.14), lineWidth: 1.1)
        )
        .padding(.horizontal, 44)
    }

    private var liveCameraView: some View {
        GeometryReader { geometry in
            let frameHeight = max(1, geometry.size.height - 32)
            let requiredFillScale = 1 + ((2 * abs(viewModel.previewOffsetY)) / frameHeight)
            let effectiveScale = max(viewModel.previewScale, min(requiredFillScale + 0.02, 1.40))

            ZStack(alignment: .leading) {
                ZStack {
                    ZStack {
                        TVCameraPreviewView(session: viewModel.captureSession)

                        TVPoseOverlay(
                            frame: viewModel.latestPoseFrame,
                            selectedExercise: viewModel.selectedExercise,
                            framingMode: viewModel.framingMode,
                            isCalibrating: viewModel.isCalibrating,
                            isSessionRunning: viewModel.isSessionRunning
                        )
                        .allowsHitTesting(false)
                    }
                    .scaleEffect(effectiveScale, anchor: .center)
                    .offset(y: viewModel.previewOffsetY)
                    .animation(.easeInOut(duration: 0.22), value: effectiveScale)
                    .animation(.easeInOut(duration: 0.18), value: viewModel.previewOffsetY)

                    VStack(spacing: 0) {
                        cameraTopMetrics
                            .padding(.top, 18)
                        Spacer(minLength: 0)
                        cameraGuidanceSubtitle
                            .padding(.horizontal, 22)
                            .padding(.bottom, 18)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(.white.opacity(0.23), lineWidth: 1.2)
                )
                .shadow(color: .black.opacity(0.30), radius: 24, y: 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                leftControlRail
                    .padding(.leading, 20)
                    .padding(.vertical, 24)
                    .zIndex(2)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
    }

    private var cameraTopMetrics: some View {
        HStack(spacing: 12) {
            Text(viewModel.selectedExercise.displayName)
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
            dotSeparator
            metricItem(title: "Moves", value: "\(viewModel.movementCount)")
            dotSeparator
            metricItem(title: "Time", value: viewModel.sessionDurationLabel)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(
            LinearGradient(
                colors: [
                    Color.black.opacity(0.62),
                    Color.black.opacity(0.46)
                ],
                startPoint: .top,
                endPoint: .bottom
            ),
            in: Capsule()
        )
        .overlay(
            Capsule().strokeBorder(.white.opacity(0.20))
        )
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var dotSeparator: some View {
        Circle()
            .fill(.white.opacity(0.36))
            .frame(width: 4, height: 4)
    }

    private func metricItem(title: String, value: String) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.76))
            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
        }
    }

    private var cameraGuidanceSubtitle: some View {
        VStack(alignment: .center, spacing: 4) {
            Text(viewModel.feedback)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .multilineTextAlignment(.center)
            Text(sessionSummaryText)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.78))
                .lineLimit(1)
        }
        .frame(maxWidth: 760)
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.black.opacity(0.56), in: Capsule())
        .overlay(
            Capsule().strokeBorder(.white.opacity(0.20))
        )
    }

    private var leftControlRail: some View {
        VStack(spacing: 14) {
            if shouldShowReconnectButton {
                leftRailActionButton(
                    title: "Connect Camera",
                    systemImage: "iphone.gen3.camera",
                    focus: .connectCamera
                ) {
                    viewModel.openDevicePicker()
                    isTrainingMenuExpanded = false
                }
            }

            leftRailActionButton(
                title: "Training",
                systemImage: "list.bullet.rectangle.portrait",
                focus: .trainingMenu
            ) {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isTrainingMenuExpanded.toggle()
                }
            }

            if isTrainingMenuExpanded {
                ForEach(TVExerciseProgram.allCases) { exercise in
                    leftRailActionButton(
                        title: exercise.displayName,
                        systemImage: exercise.systemImage,
                        focus: .training(exercise),
                        isSelected: viewModel.selectedExercise == exercise
                    ) {
                        viewModel.selectExercise(exercise)
                        isTrainingMenuExpanded = false
                    }
                }
            }

            leftRailActionButton(
                title: "Run Calibration",
                systemImage: "dot.scope",
                focus: .calibrate
            ) {
                viewModel.runCalibration()
                isTrainingMenuExpanded = false
            }

            Spacer(minLength: 0)

            leftRailActionButton(
                title: viewModel.sessionActionTitle,
                systemImage: viewModel.isSessionRunning ? "stop.fill" : "play.fill",
                focus: .session
            ) {
                viewModel.toggleSession()
                isTrainingMenuExpanded = false
            }
        }
    }

    private func leftRailActionButton(
        title: String,
        systemImage: String,
        focus: LeftRailFocus,
        isSelected: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            TVRailButtonVisual(
                title: title,
                systemImage: systemImage,
                showLabel: showRailLabels,
                isSelected: isSelected
            )
        }
        .buttonStyle(.plain)
        .focused($focusedLeftControl, equals: focus)
        .accessibilityLabel(title)
    }

    private var background: some View {
        LinearGradient(
            colors: [
                Color(red: 0.04, green: 0.08, blue: 0.13),
                Color(red: 0.07, green: 0.15, blue: 0.24)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

private struct TVRailButtonVisual: View {
    let title: String
    let systemImage: String
    let showLabel: Bool
    let isSelected: Bool

    @Environment(\.isFocused) private var isFocused

    private let buttonSize: CGFloat = 68
    private let cornerRadius: CGFloat = 22
    private let sharedFill = Color(red: 0.18, green: 0.25, blue: 0.35)
    private let expandedWidth: CGFloat = 254

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)

            if showLabel {
                Text(title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white.opacity(0.95))
                }
            }
        }
        .frame(width: showLabel ? expandedWidth : buttonSize, height: buttonSize, alignment: .leading)
        .padding(.horizontal, showLabel ? 16 : 0)
        .background(sharedFill.opacity(isFocused ? 0.98 : 0.92), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(strokeColor, lineWidth: isFocused ? 2.2 : 1.2)
        )
        .shadow(color: .black.opacity(isFocused ? 0.42 : 0.28), radius: isFocused ? 14 : 8, y: 5)
        .scaleEffect(isFocused ? 1.06 : 1.0)
        .animation(.easeInOut(duration: 0.16), value: isFocused)
        .animation(.easeInOut(duration: 0.16), value: showLabel)
    }

    private var strokeColor: Color {
        if isSelected {
            return .white.opacity(0.95)
        }
        return isFocused ? .white.opacity(0.70) : .white.opacity(0.24)
    }
}

private struct TVPoseOverlay: View {
    let frame: PoseFrame?
    let selectedExercise: TVExerciseProgram
    let framingMode: TVFramingMode
    let isCalibrating: Bool
    let isSessionRunning: Bool

    private let skeletonSegments: [(start: OverlayJoint, end: OverlayJoint)] = [
        (.custom("leftShoulder"), .custom("rightShoulder")),
        (.custom("leftShoulder"), .body(.leftHip)),
        (.custom("rightShoulder"), .body(.rightHip)),
        (.body(.leftHip), .body(.rightHip)),
        (.body(.leftHip), .body(.leftKnee)),
        (.body(.leftKnee), .body(.leftAnkle)),
        (.body(.rightHip), .body(.rightKnee)),
        (.body(.rightKnee), .body(.rightAnkle))
    ]

    private let visibleJointOrder: [OverlayJoint] = [
        .custom("neck"),
        .custom("leftShoulder"),
        .custom("rightShoulder"),
        .body(.leftHip),
        .body(.rightHip),
        .body(.leftKnee),
        .body(.rightKnee),
        .body(.leftAnkle),
        .body(.rightAnkle)
    ]

    var body: some View {
        GeometryReader { geometry in
            TimelineView(.periodic(from: .now, by: 1.0 / 12.0)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let phase = CGFloat((sin(t * 2.0) + 1) * 0.5)

                Canvas { context, size in
                    let zoneRect = targetZoneRect(in: size)
                    let zoneState = evaluateZoneState(frame: frame, zoneRect: zoneRect, in: size)
                    drawTargetZones(
                        in: &context,
                        size: size,
                        zoneRect: zoneRect,
                        zoneState: zoneState,
                        phase: phase
                    )

                    if let frame {
                        drawTrackedPose(
                            frame,
                            in: &context,
                            size: size,
                            zoneRect: zoneRect,
                            zoneState: zoneState
                        )
                    } else {
                        drawGuideFigure(in: &context, size: size, phase: phase)
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
        }
    }

    private func targetZoneRect(in size: CGSize) -> CGRect {
        switch framingMode {
        case .fullBody:
            return CGRect(
                x: size.width * 0.20,
                y: size.height * 0.14,
                width: size.width * 0.60,
                height: size.height * 0.78
            )
        case .upperBody:
            return CGRect(
                x: size.width * 0.22,
                y: size.height * 0.10,
                width: size.width * 0.56,
                height: size.height * 0.52
            )
        case .feetToHalfBody:
            return CGRect(
                x: size.width * 0.21,
                y: size.height * 0.21,
                width: size.width * 0.58,
                height: size.height * 0.72
            )
        case .kneeFocus:
            return CGRect(
                x: size.width * 0.24,
                y: size.height * 0.30,
                width: size.width * 0.52,
                height: size.height * 0.58
            )
        case .heelFocus:
            return CGRect(
                x: size.width * 0.24,
                y: size.height * 0.40,
                width: size.width * 0.52,
                height: size.height * 0.50
            )
        }
    }

    private func evaluateZoneState(frame: PoseFrame?, zoneRect: CGRect, in size: CGSize) -> ZoneState {
        guard let frame else {
            return ZoneState(score: 0, color: baseStateColor)
        }

        let required = requiredJointsForZone
        guard !required.isEmpty else {
            return ZoneState(score: 0, color: baseStateColor)
        }

        var insideCount = 0
        var trackedCount = 0
        let tolerantZone = zoneRect.insetBy(dx: -18, dy: -18)

        for joint in required {
            guard let posePoint = posePoint(for: joint, in: frame) else { continue }
            guard posePoint.confidence >= 0.32 else { continue }
            trackedCount += 1
            let point = point(from: posePoint, in: size)
            if tolerantZone.contains(point) {
                insideCount += 1
            }
        }

        guard trackedCount > 0 else {
            return ZoneState(score: 0, color: baseStateColor)
        }

        let score = Double(insideCount) / Double(trackedCount)
        let color: Color
        if score >= 0.58 {
            color = Color(red: 0.12, green: 0.82, blue: 0.35)
        } else if score >= 0.24 {
            color = Color(red: 0.96, green: 0.66, blue: 0.16)
        } else {
            color = Color(red: 0.91, green: 0.30, blue: 0.24)
        }

        return ZoneState(score: score, color: color)
    }

    private var requiredJointsForZone: [OverlayJoint] {
        switch framingMode {
        case .fullBody:
            return [
                .custom("leftShoulder"),
                .custom("rightShoulder"),
                .body(.leftHip),
                .body(.rightHip),
                .body(.leftKnee),
                .body(.rightKnee),
                .body(.leftAnkle),
                .body(.rightAnkle)
            ]
        case .upperBody:
            return [
                .custom("neck"),
                .custom("leftShoulder"),
                .custom("rightShoulder"),
                .body(.leftHip),
                .body(.rightHip)
            ]
        case .feetToHalfBody:
            return [
                .body(.leftHip),
                .body(.rightHip),
                .body(.leftKnee),
                .body(.rightKnee),
                .body(.leftAnkle),
                .body(.rightAnkle)
            ]
        case .kneeFocus:
            return [
                .body(.leftHip),
                .body(.rightHip),
                .body(.leftKnee),
                .body(.rightKnee),
                .body(.leftAnkle),
                .body(.rightAnkle)
            ]
        case .heelFocus:
            return [
                .body(.leftKnee),
                .body(.rightKnee),
                .body(.leftAnkle),
                .body(.rightAnkle)
            ]
        }
    }

    private var baseStateColor: Color {
        if isCalibrating {
            return Color(red: 0.95, green: 0.76, blue: 0.12)
        }
        if isSessionRunning {
            return Color(red: 0.10, green: 0.78, blue: 0.37)
        }
        return Color(red: 0.95, green: 0.44, blue: 0.20)
    }

    private func drawTargetZones(
        in context: inout GraphicsContext,
        size: CGSize,
        zoneRect: CGRect,
        zoneState: ZoneState,
        phase: CGFloat
    ) {
        let pulse = 0.52 + (phase * 0.28)

        let fillGradient = Gradient(colors: [
            zoneState.color.opacity(0.05 + (zoneState.score * 0.10)),
            zoneState.color.opacity(0.01)
        ])
        context.fill(
            Path(roundedRect: zoneRect, cornerRadius: 20),
            with: .linearGradient(
                fillGradient,
                startPoint: CGPoint(x: zoneRect.midX, y: zoneRect.minY),
                endPoint: CGPoint(x: zoneRect.midX, y: zoneRect.maxY)
            )
        )

        context.stroke(
            Path(roundedRect: zoneRect, cornerRadius: 20),
            with: .color(zoneState.color.opacity(Double(pulse))),
            style: StrokeStyle(lineWidth: 3.2, lineCap: .round, lineJoin: .round, dash: [10, 7])
        )

        var centerLine = Path()
        centerLine.move(to: CGPoint(x: zoneRect.midX, y: zoneRect.minY + 16))
        centerLine.addLine(to: CGPoint(x: zoneRect.midX, y: zoneRect.maxY - 16))
        context.stroke(
            centerLine,
            with: .color(zoneState.color.opacity(0.26)),
            style: StrokeStyle(lineWidth: 1.6, lineCap: .round, dash: [4, 7])
        )

        var heelBaseline = Path()
        let baselineY = zoneRect.maxY - max(8, zoneRect.height * 0.03)
        heelBaseline.move(to: CGPoint(x: zoneRect.minX + 22, y: baselineY))
        heelBaseline.addLine(to: CGPoint(x: zoneRect.maxX - 22, y: baselineY))
        context.stroke(
            heelBaseline,
            with: .color(Color(red: 0.96, green: 0.58, blue: 0.18).opacity(0.88)),
            style: StrokeStyle(lineWidth: 2.6, lineCap: .round, dash: [8, 7])
        )
    }

    private func drawTrackedPose(
        _ frame: PoseFrame,
        in context: inout GraphicsContext,
        size: CGSize,
        zoneRect: CGRect,
        zoneState: ZoneState
    ) {
        for segment in skeletonSegments {
            guard
                let start = posePoint(for: segment.start, in: frame),
                let end = posePoint(for: segment.end, in: frame)
            else {
                continue
            }

            let startPoint = point(from: start, in: size)
            let endPoint = point(from: end, in: size)

            var path = Path()
            path.move(to: startPoint)
            path.addLine(to: endPoint)

            let confidence = min(start.confidence, end.confidence)
            let insideZone = zoneRect.contains(startPoint) && zoneRect.contains(endPoint)
            context.stroke(
                path,
                with: .color(trackingColor(confidence: confidence, insideZone: insideZone, zoneState: zoneState)),
                style: StrokeStyle(lineWidth: 5.2, lineCap: .round, lineJoin: .round)
            )
        }

        drawVirtualFeet(frame, in: &context, size: size, zoneRect: zoneRect, zoneState: zoneState)

        for joint in visibleJointOrder {
            guard let posePoint = posePoint(for: joint, in: frame) else { continue }
            let center = point(from: posePoint, in: size)

            let confidenceColor = trackingColor(
                confidence: posePoint.confidence,
                insideZone: zoneRect.contains(center),
                zoneState: zoneState
            )

            let haloRect = CGRect(x: center.x - 7, y: center.y - 7, width: 14, height: 14)
            context.fill(Path(ellipseIn: haloRect), with: .color(confidenceColor.opacity(0.22)))

            let markerRect = CGRect(x: center.x - 4.8, y: center.y - 4.8, width: 9.6, height: 9.6)
            context.fill(Path(ellipseIn: markerRect), with: .color(confidenceColor))
        }
    }

    private func drawVirtualFeet(
        _ frame: PoseFrame,
        in context: inout GraphicsContext,
        size: CGSize,
        zoneRect: CGRect,
        zoneState: ZoneState
    ) {
        drawVirtualFoot(.left, frame: frame, in: &context, size: size, zoneRect: zoneRect, zoneState: zoneState)
        drawVirtualFoot(.right, frame: frame, in: &context, size: size, zoneRect: zoneRect, zoneState: zoneState)
    }

    private func drawVirtualFoot(
        _ side: LegSide,
        frame: PoseFrame,
        in context: inout GraphicsContext,
        size: CGSize,
        zoneRect: CGRect,
        zoneState: ZoneState
    ) {
        let kneeJoint: BodyJoint = side == .left ? .leftKnee : .rightKnee
        let ankleJoint: BodyJoint = side == .left ? .leftAnkle : .rightAnkle

        guard
            let knee = frame.point(for: kneeJoint),
            let ankle = frame.point(for: ankleJoint)
        else {
            return
        }

        let kneePoint = point(from: knee, in: size)
        let anklePoint = point(from: ankle, in: size)

        let legVector = CGPoint(x: anklePoint.x - kneePoint.x, y: anklePoint.y - kneePoint.y)
        let length = max(0.001, hypot(legVector.x, legVector.y))
        let norm = CGPoint(x: legVector.x / length, y: legVector.y / length)
        let perp = CGPoint(x: -norm.y, y: norm.x)

        let foot = estimatedFootPoints(
            anklePoint: anklePoint,
            norm: norm,
            perp: perp,
            side: side,
            legLength: length
        )
        let heelPoint = foot.heel
        let archPoint = foot.arch
        let ballPoint = foot.ball
        let toePoint = foot.toe

        var path = Path()
        path.move(to: heelPoint)
        path.addLine(to: archPoint)
        path.addLine(to: ballPoint)
        path.addLine(to: toePoint)

        let confidence = min(knee.confidence, ankle.confidence)
        let insideZone = zoneRect.contains(heelPoint) || zoneRect.contains(toePoint)
        let color = trackingColor(confidence: confidence, insideZone: insideZone, zoneState: zoneState)

        drawFootSole(
            heel: heelPoint,
            arch: archPoint,
            ball: ballPoint,
            toe: toePoint,
            color: color,
            in: &context
        )

        context.stroke(
            path,
            with: .color(color),
            style: StrokeStyle(
                lineWidth: selectedExercise == .calfRaise ? 5.8 : 4.8,
                lineCap: .round,
                lineJoin: .round
            )
        )

        drawFootJointCircle(center: heelPoint, radius: 6.1, color: color, in: &context)
        drawFootJointCircle(center: archPoint, radius: 4.9, color: Color(red: 0.24, green: 0.80, blue: 0.90), in: &context)
        drawFootJointCircle(center: ballPoint, radius: 5.0, color: Color(red: 0.33, green: 0.86, blue: 0.60), in: &context)
        drawFootJointCircle(center: toePoint, radius: 5.9, color: Color(red: 0.95, green: 0.70, blue: 0.18), in: &context)

        if selectedExercise == .calfRaise {
            let baselineY = zoneRect.maxY - max(8, zoneRect.height * 0.03)
            let liftTop = min(heelPoint.y, baselineY)

            var liftPath = Path()
            liftPath.move(to: CGPoint(x: heelPoint.x, y: baselineY))
            liftPath.addLine(to: CGPoint(x: heelPoint.x, y: liftTop))
            context.stroke(
                liftPath,
                with: .color(Color(red: 0.18, green: 0.83, blue: 0.46).opacity(0.84)),
                style: StrokeStyle(lineWidth: 2.6, lineCap: .round, dash: [4, 4])
            )
        }
    }

    private func estimatedFootPoints(
        anklePoint: CGPoint,
        norm: CGPoint,
        perp: CGPoint,
        side: LegSide,
        legLength: CGFloat
    ) -> (heel: CGPoint, arch: CGPoint, ball: CGPoint, toe: CGPoint) {
        let sideFactor: CGFloat = side == .left ? -1 : 1
        let footLength = max(18, min(legLength * 0.30, 34))
        let footWidth = footLength * 0.28

        let heel = CGPoint(
            x: anklePoint.x + (norm.x * (footLength * 0.40)) + (perp.x * (footWidth * 0.62 * sideFactor)),
            y: anklePoint.y + (norm.y * (footLength * 0.40)) + (perp.y * (footWidth * 0.62 * sideFactor))
        )
        let arch = CGPoint(
            x: anklePoint.x + (norm.x * (footLength * 0.27)) + (perp.x * (footWidth * 0.20 * sideFactor)),
            y: anklePoint.y + (norm.y * (footLength * 0.27)) + (perp.y * (footWidth * 0.20 * sideFactor))
        )
        let ball = CGPoint(
            x: anklePoint.x + (norm.x * (footLength * 0.15)) - (perp.x * (footLength * 0.34 * sideFactor)),
            y: anklePoint.y + (norm.y * (footLength * 0.15)) - (perp.y * (footLength * 0.34 * sideFactor))
        )
        let toe = CGPoint(
            x: anklePoint.x + (norm.x * (footLength * 0.08)) - (perp.x * (footLength * 0.60 * sideFactor)),
            y: anklePoint.y + (norm.y * (footLength * 0.08)) - (perp.y * (footLength * 0.60 * sideFactor))
        )
        return (heel, arch, ball, toe)
    }

    private func drawFootSole(
        heel: CGPoint,
        arch: CGPoint,
        ball: CGPoint,
        toe: CGPoint,
        color: Color,
        in context: inout GraphicsContext
    ) {
        let thickness: CGFloat = 4.2
        let heelLower = CGPoint(x: heel.x, y: heel.y + thickness)
        let archLower = CGPoint(x: arch.x, y: arch.y + thickness)
        let ballLower = CGPoint(x: ball.x, y: ball.y + thickness)
        let toeLower = CGPoint(x: toe.x, y: toe.y + thickness)

        var sole = Path()
        sole.move(to: heel)
        sole.addLine(to: arch)
        sole.addLine(to: ball)
        sole.addLine(to: toe)
        sole.addLine(to: toeLower)
        sole.addLine(to: ballLower)
        sole.addLine(to: archLower)
        sole.addLine(to: heelLower)
        sole.closeSubpath()

        context.fill(sole, with: .color(color.opacity(0.18)))
    }

    private func drawFootJointCircle(
        center: CGPoint,
        radius: CGFloat,
        color: Color,
        in context: inout GraphicsContext
    ) {
        let halo = CGRect(
            x: center.x - (radius + 2),
            y: center.y - (radius + 2),
            width: (radius + 2) * 2,
            height: (radius + 2) * 2
        )
        context.fill(Path(ellipseIn: halo), with: .color(color.opacity(0.20)))

        let marker = CGRect(
            x: center.x - radius,
            y: center.y - radius,
            width: radius * 2,
            height: radius * 2
        )
        context.fill(Path(ellipseIn: marker), with: .color(color))
    }

    private func drawGuideFigure(in context: inout GraphicsContext, size: CGSize, phase: CGFloat) {
        let centerX = size.width * 0.5
        let motionDepth = guideDepth(for: selectedExercise) * phase

        let shoulderY = size.height * 0.23 + motionDepth * 7
        let hipY = size.height * 0.46 + motionDepth * 14
        let kneeY = size.height * 0.63 + motionDepth * 11
        let ankleY = size.height * 0.79 + max(motionDepth * 13, 0)

        let squatShift: CGFloat = selectedExercise == .calfRaise ? 0 : motionDepth * 13
        let lungeSplit: CGFloat = selectedExercise == .lunge ? 18 : 0

        let leftShoulder = CGPoint(x: centerX - 22, y: shoulderY)
        let rightShoulder = CGPoint(x: centerX + 22, y: shoulderY)
        let leftHip = CGPoint(x: centerX - 18, y: hipY)
        let rightHip = CGPoint(x: centerX + 18, y: hipY)
        let leftKnee = CGPoint(x: centerX - 18 - squatShift + lungeSplit, y: kneeY)
        let rightKnee = CGPoint(x: centerX + 18 + squatShift - lungeSplit, y: kneeY)
        let leftAnkle = CGPoint(x: centerX - 20 + lungeSplit, y: ankleY)
        let rightAnkle = CGPoint(x: centerX + 20 - lungeSplit, y: ankleY)

        let armOffset = 20 + (motionDepth * 10)
        let leftElbow = CGPoint(x: leftShoulder.x - armOffset, y: shoulderY + 22)
        let rightElbow = CGPoint(x: rightShoulder.x + armOffset, y: shoulderY + 22)

        var skeleton = Path()
        skeleton.move(to: leftShoulder)
        skeleton.addLine(to: rightShoulder)
        skeleton.move(to: leftShoulder)
        skeleton.addLine(to: leftHip)
        skeleton.move(to: rightShoulder)
        skeleton.addLine(to: rightHip)
        skeleton.move(to: leftHip)
        skeleton.addLine(to: rightHip)
        skeleton.move(to: leftHip)
        skeleton.addLine(to: leftKnee)
        skeleton.addLine(to: leftAnkle)
        skeleton.move(to: rightHip)
        skeleton.addLine(to: rightKnee)
        skeleton.addLine(to: rightAnkle)
        skeleton.move(to: leftShoulder)
        skeleton.addLine(to: leftElbow)
        skeleton.move(to: rightShoulder)
        skeleton.addLine(to: rightElbow)

        let guideColor = Color(red: 0.24, green: 0.84, blue: 0.61)
        context.stroke(
            skeleton,
            with: .color(guideColor.opacity(0.62)),
            style: StrokeStyle(lineWidth: 4.2, lineCap: .round, lineJoin: .round)
        )

        var kneesPath = Path()
        kneesPath.move(to: CGPoint(x: leftHip.x, y: leftKnee.y))
        kneesPath.addLine(to: leftKnee)
        kneesPath.move(to: CGPoint(x: rightHip.x, y: rightKnee.y))
        kneesPath.addLine(to: rightKnee)
        context.stroke(
            kneesPath,
            with: .color(guideColor.opacity(0.48)),
            style: StrokeStyle(lineWidth: 2.2, lineCap: .round, dash: [6, 5])
        )

        drawGuideFoot(knee: leftKnee, ankle: leftAnkle, side: .left, color: guideColor, in: &context)
        drawGuideFoot(knee: rightKnee, ankle: rightAnkle, side: .right, color: guideColor, in: &context)

        let headRect = CGRect(x: centerX - 10, y: shoulderY - 24, width: 20, height: 20)
        context.fill(Path(ellipseIn: headRect), with: .color(guideColor.opacity(0.62)))
    }

    private func drawGuideFoot(
        knee: CGPoint,
        ankle: CGPoint,
        side: LegSide,
        color: Color,
        in context: inout GraphicsContext
    ) {
        let legVector = CGPoint(x: ankle.x - knee.x, y: ankle.y - knee.y)
        let length = max(0.001, hypot(legVector.x, legVector.y))
        let norm = CGPoint(x: legVector.x / length, y: legVector.y / length)
        let perp = CGPoint(x: -norm.y, y: norm.x)
        let foot = estimatedFootPoints(
            anklePoint: ankle,
            norm: norm,
            perp: perp,
            side: side,
            legLength: length
        )

        var path = Path()
        path.move(to: foot.heel)
        path.addLine(to: foot.arch)
        path.addLine(to: foot.ball)
        path.addLine(to: foot.toe)
        context.stroke(
            path,
            with: .color(color.opacity(0.70)),
            style: StrokeStyle(lineWidth: 3.8, lineCap: .round, lineJoin: .round)
        )

        drawFootJointCircle(center: foot.heel, radius: 4.4, color: color.opacity(0.72), in: &context)
        drawFootJointCircle(center: foot.ball, radius: 3.7, color: color.opacity(0.72), in: &context)
        drawFootJointCircle(center: foot.toe, radius: 4.1, color: color.opacity(0.72), in: &context)
    }

    private func guideDepth(for exercise: TVExerciseProgram) -> CGFloat {
        switch exercise {
        case .miniSquat:
            return 0.40
        case .sitToStand:
            return 0.74
        case .squat:
            return 0.82
        case .lunge:
            return 0.70
        case .calfRaise:
            return -0.32
        }
    }

    private func trackingColor(confidence: Double, insideZone: Bool, zoneState: ZoneState) -> Color {
        if confidence >= 0.54 && (insideZone || zoneState.score >= 0.50) {
            return Color(red: 0.16, green: 0.86, blue: 0.42)
        }
        if confidence >= 0.34 {
            return Color(red: 0.93, green: 0.78, blue: 0.20)
        }
        return Color(red: 0.90, green: 0.27, blue: 0.23)
    }

    private func posePoint(for joint: OverlayJoint, in frame: PoseFrame) -> PosePoint? {
        switch joint {
        case let .body(bodyJoint):
            return frame.point(for: bodyJoint)
        case let .custom(key):
            return frame.joints[key]
        }
    }

    private func point(from posePoint: PosePoint, in size: CGSize) -> CGPoint {
        CGPoint(
            x: posePoint.x * size.width,
            y: (1 - posePoint.y) * size.height
        )
    }
}

private struct ZoneState {
    let score: Double
    let color: Color
}

private enum OverlayJoint {
    case body(BodyJoint)
    case custom(String)
}

private enum LegSide {
    case left
    case right
}
