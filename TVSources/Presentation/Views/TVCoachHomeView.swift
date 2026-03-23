import SwiftUI

struct TVCoachHomeView: View {
    @StateObject private var viewModel: TVCoachViewModel
    @State private var isTrainingMenuExpanded = false
    @FocusState private var focusedLeftControl: LeftRailFocus?

    private enum LeftRailFocus: Hashable {
        case connectCamera
        case trainingMenu
        case training(TVExerciseProgram)
        case smallSpace
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

    private var shouldShowAmbientGuidanceAnimation: Bool {
        if viewModel.isCalibrating {
            return true
        }
        return viewModel.isCalibrationReady
            && !viewModel.isSessionRunning
            && !viewModel.isPrepGuideActive
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
        focusedLeftControl != nil || viewModel.isPrepGuideActive
    }

    private var sessionActionIcon: String {
        if viewModel.isPrepGuideActive {
            return "xmark.circle.fill"
        }
        return viewModel.isSessionRunning ? "stop.fill" : "play.fill"
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
            let offsetCompensation = 1 + ((abs(viewModel.previewOffsetY) / frameHeight) * 0.24)
            let effectiveScale = min(max(viewModel.previewScale, offsetCompensation), 1.12)

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

                        if viewModel.isPrepGuideActive || shouldShowAmbientGuidanceAnimation {
                            TVPrepGuideOverlay(
                                frame: viewModel.latestPoseFrame,
                                selectedExercise: viewModel.selectedExercise,
                                countdown: viewModel.prepGuideCountdown,
                                progress: viewModel.isPrepGuideActive ? viewModel.prepGuideProgress : viewModel.calibrationProgress,
                                displayMode: viewModel.isPrepGuideActive ? .prep : .ambient
                            )
                            .allowsHitTesting(false)
                            .transition(.opacity)
                        }
                    }
                    .scaleEffect(effectiveScale, anchor: .center)
                    .offset(y: viewModel.previewOffsetY)
                    .animation(.easeInOut(duration: 0.22), value: effectiveScale)
                    .animation(.easeInOut(duration: 0.18), value: viewModel.previewOffsetY)

                    VStack(spacing: 0) {
                        if !shouldShowAmbientGuidanceAnimation {
                            cameraTopMetrics
                                .padding(.top, 18)
                        }
                        Spacer(minLength: 0)
                        if !shouldShowAmbientGuidanceAnimation {
                            cameraGuidanceSubtitle
                                .padding(.horizontal, 22)
                                .padding(.bottom, 18)
                        }
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

            leftRailActionButton(
                title: "Small Space",
                systemImage: "arrow.up.left.and.arrow.down.right",
                focus: .smallSpace,
                isSelected: viewModel.smallSpaceAssistEnabled
            ) {
                viewModel.enableSmallSpaceAssist()
                isTrainingMenuExpanded = false
            }

            Spacer(minLength: 0)

            leftRailActionButton(
                title: viewModel.sessionActionTitle,
                systemImage: sessionActionIcon,
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

private struct TVPrepGuideOverlay: View {
    enum DisplayMode {
        case prep
        case ambient
    }

    let frame: PoseFrame?
    let selectedExercise: TVExerciseProgram
    let countdown: Int
    let progress: Double
    let displayMode: DisplayMode

    private var accentColor: Color {
        switch selectedExercise {
        case .calfRaise:
            return Color(red: 0.18, green: 0.85, blue: 0.58)
        case .lunge:
            return Color(red: 0.26, green: 0.72, blue: 0.96)
        case .miniSquat:
            return Color(red: 0.20, green: 0.82, blue: 0.71)
        case .sitToStand:
            return Color(red: 0.29, green: 0.78, blue: 0.96)
        case .squat:
            return Color(red: 0.20, green: 0.86, blue: 0.66)
        }
    }

    private var showsInstructionCard: Bool { displayMode == .prep }
    private var phaseTitle: String { countdown > 0 ? "Get Ready" : "Follow Through" }
    private var centerLabel: String { countdown > 0 ? "\(countdown)" : "GO" }
    private let helperText = "Press Session again to cancel"
    private var headerTitle: String { "Prep Guide • \(selectedExercise.displayName)" }

    var body: some View {
        GeometryReader { geometry in
            TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let pulse = CGFloat((sin(t * 4.0) + 1) * 0.5)
                let pathCycle = CGFloat((sin(t * 2.8 - (.pi / 2)) + 1) * 0.5)

                ZStack {
                    Canvas { context, size in
                        let anchors = guideAnchors(in: size)
                        let guidanceState = guidanceVisualState(anchors: anchors, size: size)
                        drawTint(in: &context, size: size)
                        drawMovementField(
                            in: &context,
                            size: size,
                            highlightColor: guidanceState.color,
                            score: guidanceState.score
                        )

                        switch selectedExercise {
                        case .calfRaise:
                            drawCalfGuide(
                                anchors: anchors,
                                guideColor: guidanceState.color,
                                pathCycle: pathCycle,
                                pulse: pulse,
                                in: &context
                            )
                        case .lunge:
                            drawLungeGuide(
                                anchors: anchors,
                                leadLeg: guidanceState.lungeLead,
                                guideColor: guidanceState.color,
                                pathCycle: pathCycle,
                                pulse: pulse,
                                in: &context
                            )
                        case .squat, .sitToStand, .miniSquat:
                            drawSquatGuide(
                                anchors: anchors,
                                guideColor: guidanceState.color,
                                pathCycle: pathCycle,
                                pulse: pulse,
                                in: &context
                            )
                        }

                        drawHumanGuideAvatar(
                            anchors: anchors,
                            lungeLead: guidanceState.lungeLead,
                            guideColor: guidanceState.color,
                            qualityLevel: guidanceState.level,
                            pathCycle: pathCycle,
                            pulse: pulse,
                            in: &context
                        )
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)

                    if showsInstructionCard {
                        VStack(spacing: 16) {
                            prepHeaderBadge
                                .padding(.top, 24)

                            Spacer(minLength: geometry.size.height * 0.10)

                            VStack(spacing: 14) {
                                Text(phaseTitle)
                                    .font(.title3.weight(.semibold))
                                    .foregroundStyle(.white.opacity(0.93))

                                ZStack {
                                    Circle()
                                        .stroke(.white.opacity(0.24), lineWidth: 7)
                                        .frame(width: 124, height: 124)

                                    Circle()
                                        .trim(from: 0, to: max(0.02, min(progress, 1.0)))
                                        .stroke(
                                            AngularGradient(
                                                gradient: Gradient(colors: [
                                                    accentColor,
                                                    Color(red: 0.24, green: 0.67, blue: 0.97)
                                                ]),
                                                center: .center
                                            ),
                                            style: StrokeStyle(lineWidth: 8, lineCap: .round)
                                        )
                                        .rotationEffect(.degrees(-90))
                                        .frame(width: 124, height: 124)

                                    Text(centerLabel)
                                        .font(.system(size: 42, weight: .bold, design: .rounded))
                                        .foregroundStyle(.white)
                                }

                                Text(selectedExercise.prepGuideHint)
                                    .font(.title3.weight(.semibold))
                                    .foregroundStyle(.white.opacity(0.90))
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                                    .frame(maxWidth: 560)

                                Text(helperText)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.white.opacity(0.70))
                            }
                            .padding(.horizontal, 26)
                            .padding(.vertical, 18)
                            .background(.black.opacity(0.62), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 24, style: .continuous)
                                    .strokeBorder(.white.opacity(0.28))
                            )
                            .shadow(color: .black.opacity(0.30), radius: 14, y: 6)

                            Spacer(minLength: geometry.size.height * 0.12)
                        }
                        .padding(.horizontal, 24)
                    }
                }
            }
        }
    }

    private var prepHeaderBadge: some View {
        HStack(spacing: 10) {
            Image(systemName: selectedExercise.systemImage)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 2) {
                Text(headerTitle)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                Text(pathDescriptorText)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.76))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.black.opacity(0.58), in: Capsule())
        .overlay(
            Capsule().strokeBorder(.white.opacity(0.24), lineWidth: 1.0)
        )
    }

    private var pathDescriptorText: String {
        switch selectedExercise {
        case .calfRaise:
            return "Track heel lift and controlled lowering."
        case .lunge:
            return "Track front and rear leg depth."
        case .miniSquat:
            return "Track shallow knee travel."
        case .sitToStand:
            return "Track sit-down and stand-up path."
        case .squat:
            return "Track knee depth and return."
        }
    }

    private func drawTint(in context: inout GraphicsContext, size: CGSize) {
        let overlay = Path(CGRect(origin: .zero, size: size))
        context.fill(
            overlay,
            with: .linearGradient(
                Gradient(colors: [
                    .black.opacity(0.30),
                    .clear,
                    .black.opacity(0.24)
                ]),
                startPoint: CGPoint(x: size.width * 0.5, y: 0),
                endPoint: CGPoint(x: size.width * 0.5, y: size.height)
            )
        )
    }

    private func movementFieldRect(in size: CGSize) -> CGRect {
        CGRect(
            x: size.width * 0.18,
            y: size.height * 0.13,
            width: size.width * 0.64,
            height: size.height * 0.76
        )
    }

    private func drawMovementField(
        in context: inout GraphicsContext,
        size: CGSize,
        highlightColor: Color,
        score: Double
    ) {
        let fieldRect = movementFieldRect(in: size)
        let outer = Path(roundedRect: fieldRect, cornerRadius: 28)
        context.fill(
            outer,
            with: .linearGradient(
                Gradient(colors: [
                    highlightColor.opacity((showsInstructionCard ? 0.10 : 0.20) + (score * 0.06)),
                    highlightColor.opacity((showsInstructionCard ? 0.03 : 0.08) + (score * 0.03))
                ]),
                startPoint: CGPoint(x: fieldRect.midX, y: fieldRect.minY),
                endPoint: CGPoint(x: fieldRect.midX, y: fieldRect.maxY)
            )
        )
        context.stroke(
            outer,
            with: .color(highlightColor.opacity(showsInstructionCard ? 0.72 : 0.96)),
            style: StrokeStyle(lineWidth: 2.8, lineCap: .round, lineJoin: .round, dash: [11, 8])
        )
    }

    private func guidanceVisualState(anchors: GuideAnchors, size: CGSize) -> GuidanceVisualState {
        let lead = estimatedLungeLead(from: anchors)
        guard anchors.hasTrackedPose else {
            return GuidanceVisualState(score: 0.50, color: accentColor, level: .warning, lungeLead: lead)
        }

        let zone = movementFieldRect(in: size).insetBy(dx: -18, dy: -18)
        let candidates = anchors.trackedGuidancePoints
        guard !candidates.isEmpty else {
            return GuidanceVisualState(score: 0.50, color: accentColor, level: .warning, lungeLead: lead)
        }

        let insideCount = candidates.reduce(into: 0) { partial, point in
            if zone.contains(point) {
                partial += 1
            }
        }
        let score = Double(insideCount) / Double(candidates.count)

        let color: Color
        let level: GuidanceLevel
        if score >= 0.58 {
            color = Color(red: 0.12, green: 0.82, blue: 0.35)
            level = .good
        } else if score >= 0.24 {
            color = Color(red: 0.96, green: 0.66, blue: 0.16)
            level = .warning
        } else {
            color = Color(red: 0.91, green: 0.30, blue: 0.24)
            level = .critical
        }
        return GuidanceVisualState(score: score, color: color, level: level, lungeLead: lead)
    }

    private func drawSquatGuide(
        anchors: GuideAnchors,
        guideColor: Color,
        pathCycle: CGFloat,
        pulse: CGFloat,
        in context: inout GraphicsContext
    ) {
        let color = guideColor
        let legLength = anchors.estimatedLegLength
        let verticalFactor: CGFloat
        switch selectedExercise {
        case .sitToStand:
            verticalFactor = 0.39
        case .miniSquat:
            verticalFactor = 0.24
        default:
            verticalFactor = 0.34
        }
        let verticalTravel = max(62, legLength * verticalFactor)
        let startOffset = max(14, legLength * 0.06)
        let hipTravel = max(42, verticalTravel * 0.76)

        drawTrack(
            from: CGPoint(x: anchors.hipCenter.x, y: anchors.hipCenter.y - startOffset),
            to: CGPoint(x: anchors.hipCenter.x, y: anchors.hipCenter.y + hipTravel),
            color: color,
            pathCycle: pathCycle,
            pulse: pulse,
            in: &context
        )
    }

    private func drawLungeGuide(
        anchors: GuideAnchors,
        leadLeg: LegSide,
        guideColor: Color,
        pathCycle: CGFloat,
        pulse: CGFloat,
        in context: inout GraphicsContext
    ) {
        let legLength = anchors.estimatedLegLength
        let frontKnee = leadLeg == .left ? anchors.leftKnee : anchors.rightKnee
        let frontTravel = max(78, legLength * 0.40)
        let frontStart = max(24, legLength * 0.11)

        drawTrack(
            from: CGPoint(x: frontKnee.x, y: frontKnee.y - frontStart),
            to: CGPoint(x: frontKnee.x, y: frontKnee.y + frontTravel),
            color: guideColor,
            pathCycle: pathCycle,
            pulse: pulse,
            in: &context
        )
    }

    private func drawCalfGuide(
        anchors: GuideAnchors,
        guideColor: Color,
        pathCycle: CGFloat,
        pulse: CGFloat,
        in context: inout GraphicsContext
    ) {
        let color = guideColor
        let legLength = anchors.estimatedLegLength
        let liftTravel = max(48, legLength * 0.24)
        let startOffset = max(10, legLength * 0.05)
        let ankleCenter = CGPoint(
            x: (anchors.leftAnkle.x + anchors.rightAnkle.x) * 0.5,
            y: (anchors.leftAnkle.y + anchors.rightAnkle.y) * 0.5
        )

        drawTrack(
            from: CGPoint(x: ankleCenter.x, y: ankleCenter.y + startOffset),
            to: CGPoint(x: ankleCenter.x, y: ankleCenter.y - liftTravel),
            color: color,
            pathCycle: pathCycle,
            pulse: pulse,
            in: &context
        )
    }

    private func drawTrack(
        from start: CGPoint,
        to end: CGPoint,
        color: Color,
        pathCycle: CGFloat,
        pulse: CGFloat,
        in context: inout GraphicsContext
    ) {
        var track = Path()
        track.move(to: start)
        track.addLine(to: end)

        context.stroke(
            track,
            with: .color(color.opacity(showsInstructionCard ? 0.26 : 0.36)),
            style: StrokeStyle(lineWidth: showsInstructionCard ? 7.2 : 8.6, lineCap: .round)
        )
        context.stroke(
            track,
            with: .color(color.opacity(showsInstructionCard ? 0.96 : 1.0)),
            style: StrokeStyle(lineWidth: showsInstructionCard ? 3.9 : 4.6, lineCap: .round, dash: [14, 9])
        )

        let dot = CGPoint(
            x: start.x + ((end.x - start.x) * pathCycle),
            y: start.y + ((end.y - start.y) * pathCycle)
        )
        let haloSize: CGFloat = 9.5 + (pulse * 6.4)
        context.fill(
            Path(ellipseIn: CGRect(x: dot.x - haloSize, y: dot.y - haloSize, width: haloSize * 2, height: haloSize * 2)),
            with: .color(color.opacity(0.28))
        )
        context.fill(
            Path(ellipseIn: CGRect(x: dot.x - 5, y: dot.y - 5, width: 10, height: 10)),
            with: .color(color)
        )

        drawArrowHead(at: end, from: start, color: color, in: &context)
    }

    private func drawHumanGuideAvatar(
        anchors: GuideAnchors,
        lungeLead: LegSide,
        guideColor: Color,
        qualityLevel: GuidanceLevel,
        pathCycle: CGFloat,
        pulse: CGFloat,
        in context: inout GraphicsContext
    ) {
        let eased = motionProgress(for: pathCycle)
        let startPose = guidePose(anchors: anchors, motion: 0, lungeLead: lungeLead)
        let targetPose = guidePose(anchors: anchors, motion: 1, lungeLead: lungeLead)
        let animatedPose = guidePose(anchors: anchors, motion: eased, lungeLead: lungeLead)

        drawMovementArrows(from: startPose, to: targetPose, color: guideColor, in: &context)

        drawBodyPose(
            startPose,
            color: .white.opacity(showsInstructionCard ? 0.25 : 0.20),
            qualityLevel: .warning,
            lineWidth: showsInstructionCard ? 6.0 : 7.0,
            jointRadius: 4.4,
            pulse: pulse,
            dashed: true,
            in: &context
        )
        drawBodyPose(
            targetPose,
            color: guideColor.opacity(showsInstructionCard ? 0.55 : 0.66),
            qualityLevel: qualityLevel,
            lineWidth: showsInstructionCard ? 6.4 : 7.4,
            jointRadius: 4.8,
            pulse: pulse,
            dashed: true,
            in: &context
        )
        drawBodyPose(
            animatedPose,
            color: guideColor,
            qualityLevel: qualityLevel,
            lineWidth: showsInstructionCard ? 9.2 : 11.2,
            jointRadius: 5.3 + (pulse * 0.9),
            pulse: pulse,
            dashed: false,
            in: &context
        )
    }

    private func guidePose(anchors: GuideAnchors, motion: CGFloat, lungeLead: LegSide) -> GuideBodyPose {
        var leftHip = anchors.leftHip
        var rightHip = anchors.rightHip
        var leftKnee = anchors.leftKnee
        var rightKnee = anchors.rightKnee
        var leftAnkle = anchors.leftAnkle
        var rightAnkle = anchors.rightAnkle

        let legLength = anchors.estimatedLegLength
        let bodyScale = max(0.90, min(1.45, legLength / 320))
        let hipWidth = max(34, anchors.hipWidth)
        let leftThighLength = max(26, distance(anchors.leftHip, anchors.leftKnee))
        let rightThighLength = max(26, distance(anchors.rightHip, anchors.rightKnee))
        let leftShinLength = max(24, distance(anchors.leftKnee, anchors.leftAnkle))
        let rightShinLength = max(24, distance(anchors.rightKnee, anchors.rightAnkle))
        let leftUpperArmLength = max(18, distance(anchors.leftShoulder, anchors.leftElbow))
        let rightUpperArmLength = max(18, distance(anchors.rightShoulder, anchors.rightElbow))
        let leftLowerArmLength = max(16, distance(anchors.leftElbow, anchors.leftWrist))
        let rightLowerArmLength = max(16, distance(anchors.rightElbow, anchors.rightWrist))
        var shoulderForwardShift: CGFloat = 0

        switch selectedExercise {
        case .squat:
            let down = motion
            let depth: CGFloat = 70 * bodyScale
            leftHip.y += depth * down
            rightHip.y += depth * down
            leftKnee.y += depth * 0.72 * down
            rightKnee.y += depth * 0.72 * down
            leftKnee.x -= hipWidth * 0.13 * down
            rightKnee.x += hipWidth * 0.13 * down
            leftAnkle.y += depth * 0.10 * down
            rightAnkle.y += depth * 0.10 * down
        case .sitToStand:
            let down = motion
            let depth: CGFloat = 88 * bodyScale
            leftHip.y += depth * down
            rightHip.y += depth * down
            leftKnee.y += depth * 0.62 * down
            rightKnee.y += depth * 0.62 * down
            leftKnee.x -= hipWidth * 0.11 * down
            rightKnee.x += hipWidth * 0.11 * down
            shoulderForwardShift = hipWidth * 0.26 * down
        case .miniSquat:
            let down = motion
            let depth: CGFloat = 44 * bodyScale
            leftHip.y += depth * down
            rightHip.y += depth * down
            leftKnee.y += depth * 0.64 * down
            rightKnee.y += depth * 0.64 * down
            leftKnee.x -= hipWidth * 0.09 * down
            rightKnee.x += hipWidth * 0.09 * down
        case .lunge:
            let down = motion
            let split = hipWidth * (0.82 * bodyScale) * down
            if lungeLead == .left {
                leftHip.x -= split * 0.38
                rightHip.x += split * 0.38
                leftKnee.x -= split * 0.88
                rightKnee.x += split * 0.62
                leftAnkle.x -= split * 1.02
                rightAnkle.x += split * 0.78
                leftHip.y += (34 * bodyScale) * down
                rightHip.y += (20 * bodyScale) * down
                leftKnee.y += (70 * bodyScale) * down
                rightKnee.y += (28 * bodyScale) * down
            } else {
                rightHip.x += split * 0.38
                leftHip.x -= split * 0.38
                rightKnee.x += split * 0.88
                leftKnee.x -= split * 0.62
                rightAnkle.x += split * 1.02
                leftAnkle.x -= split * 0.78
                rightHip.y += (34 * bodyScale) * down
                leftHip.y += (20 * bodyScale) * down
                rightKnee.y += (70 * bodyScale) * down
                leftKnee.y += (28 * bodyScale) * down
            }
            shoulderForwardShift = hipWidth * 0.14 * down
        case .calfRaise:
            let rise = motion
            let lift: CGFloat = (42 * bodyScale) * rise
            leftAnkle.y -= lift * 0.42
            rightAnkle.y -= lift * 0.42
            leftKnee.y -= lift * 0.22
            rightKnee.y -= lift * 0.22
            leftHip.y -= lift * 0.16
            rightHip.y -= lift * 0.16
        }

        leftKnee = constrainedPoint(
            from: leftHip,
            toward: leftKnee,
            length: leftThighLength,
            fallbackDirection: CGPoint(x: -0.06, y: 1)
        )
        rightKnee = constrainedPoint(
            from: rightHip,
            toward: rightKnee,
            length: rightThighLength,
            fallbackDirection: CGPoint(x: 0.06, y: 1)
        )
        leftAnkle = constrainedPoint(
            from: leftKnee,
            toward: leftAnkle,
            length: leftShinLength,
            fallbackDirection: CGPoint(x: -0.02, y: 1)
        )
        rightAnkle = constrainedPoint(
            from: rightKnee,
            toward: rightAnkle,
            length: rightShinLength,
            fallbackDirection: CGPoint(x: 0.02, y: 1)
        )

        let torsoHeight = max(72, min(176, anchors.torsoHeight * 0.98))
        let movedHipCenter = CGPoint(x: (leftHip.x + rightHip.x) * 0.5, y: (leftHip.y + rightHip.y) * 0.5)
        let shoulderOffsetFromHip = CGPoint(
            x: anchors.shoulderCenter.x - anchors.hipCenter.x,
            y: anchors.shoulderCenter.y - anchors.hipCenter.y
        )
        let shoulderCenter = CGPoint(
            x: movedHipCenter.x + shoulderOffsetFromHip.x + shoulderForwardShift,
            y: movedHipCenter.y + shoulderOffsetFromHip.y - max(0, (anchors.torsoHeight - torsoHeight))
        )
        let shoulderHalfVector = CGPoint(
            x: (anchors.rightShoulder.x - anchors.leftShoulder.x) * 0.5,
            y: (anchors.rightShoulder.y - anchors.leftShoulder.y) * 0.5
        )
        let leftShoulder = CGPoint(x: shoulderCenter.x - shoulderHalfVector.x, y: shoulderCenter.y - shoulderHalfVector.y)
        let rightShoulder = CGPoint(x: shoulderCenter.x + shoulderHalfVector.x, y: shoulderCenter.y + shoulderHalfVector.y)

        let leftUpperArmDirection = normalizedVector(
            from: anchors.leftShoulder,
            to: anchors.leftElbow,
            fallback: CGPoint(x: -0.34, y: 0.94)
        )
        let rightUpperArmDirection = normalizedVector(
            from: anchors.rightShoulder,
            to: anchors.rightElbow,
            fallback: CGPoint(x: 0.34, y: 0.94)
        )
        let leftLowerArmDirection = normalizedVector(
            from: anchors.leftElbow,
            to: anchors.leftWrist,
            fallback: leftUpperArmDirection
        )
        let rightLowerArmDirection = normalizedVector(
            from: anchors.rightElbow,
            to: anchors.rightWrist,
            fallback: rightUpperArmDirection
        )

        let leftElbow = point(from: leftShoulder, direction: leftUpperArmDirection, length: leftUpperArmLength)
        let rightElbow = point(from: rightShoulder, direction: rightUpperArmDirection, length: rightUpperArmLength)
        let leftWrist = point(from: leftElbow, direction: leftLowerArmDirection, length: leftLowerArmLength)
        let rightWrist = point(from: rightElbow, direction: rightLowerArmDirection, length: rightLowerArmLength)

        let neckOffset = CGPoint(
            x: anchors.neck.x - anchors.shoulderCenter.x,
            y: anchors.neck.y - anchors.shoulderCenter.y
        )
        let neck = CGPoint(x: shoulderCenter.x + neckOffset.x, y: shoulderCenter.y + neckOffset.y)
        let shoulderWidth = max(38, distance(leftShoulder, rightShoulder))
        let headRadius = max(12, min(30, min(shoulderWidth * 0.30, torsoHeight * 0.22)))
        let headLift = max(headRadius + 6, torsoHeight * 0.19)
        let headCenter = CGPoint(x: neck.x, y: neck.y - headLift)

        let dynamicHeelLift = selectedExercise == .calfRaise ? (legLength * 0.12 * motion) : 0
        let leftFootLength = max(20, min(42, leftShinLength * 0.36))
        let rightFootLength = max(20, min(42, rightShinLength * 0.36))
        let leftFoot = guideFootPoints(
            knee: leftKnee,
            ankle: leftAnkle,
            side: .left,
            footLength: leftFootLength,
            heelLift: dynamicHeelLift
        )
        let rightFoot = guideFootPoints(
            knee: rightKnee,
            ankle: rightAnkle,
            side: .right,
            footLength: rightFootLength,
            heelLift: dynamicHeelLift
        )

        return GuideBodyPose(
            headCenter: headCenter,
            headRadius: headRadius,
            leftShoulder: leftShoulder,
            rightShoulder: rightShoulder,
            leftElbow: leftElbow,
            rightElbow: rightElbow,
            leftWrist: leftWrist,
            rightWrist: rightWrist,
            leftHip: leftHip,
            rightHip: rightHip,
            leftKnee: leftKnee,
            rightKnee: rightKnee,
            leftAnkle: leftAnkle,
            rightAnkle: rightAnkle,
            leftHeel: leftFoot.heel,
            rightHeel: rightFoot.heel,
            leftToe: leftFoot.toe,
            rightToe: rightFoot.toe,
            lungeLead: lungeLead
        )
    }

    private func guideFootPoints(
        knee: CGPoint,
        ankle: CGPoint,
        side: LegSide,
        footLength: CGFloat,
        heelLift: CGFloat
    ) -> (heel: CGPoint, toe: CGPoint) {
        let shinDirection = normalizedVector(from: knee, to: ankle, fallback: CGPoint(x: 0, y: 1))
        let lateralDirection = CGPoint(x: -shinDirection.y, y: shinDirection.x)
        let sideFactor: CGFloat = side == .left ? -1 : 1
        let heelSide = footLength * 0.22 * sideFactor
        let toeSide = footLength * 0.76 * sideFactor
        let forwardHeel = footLength * 0.16
        let forwardToe = footLength * 0.10
        let heel = CGPoint(
            x: ankle.x + (shinDirection.x * forwardHeel) + (lateralDirection.x * heelSide),
            y: ankle.y + (shinDirection.y * forwardHeel) + (lateralDirection.y * heelSide) - heelLift
        )
        let toe = CGPoint(
            x: ankle.x - (shinDirection.x * forwardToe) - (lateralDirection.x * toeSide),
            y: ankle.y - (shinDirection.y * forwardToe) - (lateralDirection.y * toeSide)
        )
        return (heel: heel, toe: toe)
    }

    private func drawMovementArrows(
        from start: GuideBodyPose,
        to target: GuideBodyPose,
        color: Color,
        in context: inout GraphicsContext
    ) {
        let arrowColor = color.opacity(showsInstructionCard ? 0.70 : 0.90)
        switch selectedExercise {
        case .calfRaise:
            drawMotionArrow(from: start.leftHeel, to: target.leftHeel, color: arrowColor, in: &context)
            drawMotionArrow(from: start.rightHeel, to: target.rightHeel, color: arrowColor, in: &context)
        case .lunge:
            let leadingKneeStart = start.leadingKnee
            let leadingKneeEnd = target.leadingKnee
            drawMotionArrow(from: leadingKneeStart, to: leadingKneeEnd, color: arrowColor, in: &context)
            drawMotionArrow(from: start.leftHipCenter, to: target.leftHipCenter, color: arrowColor, in: &context)
        case .squat, .sitToStand, .miniSquat:
            drawMotionArrow(from: start.leftHipCenter, to: target.leftHipCenter, color: arrowColor, in: &context)
            drawMotionArrow(from: start.leftKnee, to: target.leftKnee, color: arrowColor, in: &context)
            drawMotionArrow(from: start.rightKnee, to: target.rightKnee, color: arrowColor, in: &context)
        }
    }

    private func drawMotionArrow(
        from start: CGPoint,
        to end: CGPoint,
        color: Color,
        in context: inout GraphicsContext
    ) {
        var path = Path()
        path.move(to: start)
        path.addLine(to: end)
        context.stroke(
            path,
            with: .color(color),
            style: StrokeStyle(lineWidth: 2.8, lineCap: .round, dash: [8, 7])
        )
        drawArrowHead(at: end, from: start, color: color, in: &context)
    }

    private func drawBodyPose(
        _ pose: GuideBodyPose,
        color: Color,
        qualityLevel: GuidanceLevel,
        lineWidth: CGFloat,
        jointRadius: CGFloat,
        pulse: CGFloat,
        dashed: Bool,
        in context: inout GraphicsContext
    ) {
        let palette = palette(for: qualityLevel)
        var torso = Path()
        torso.move(to: pose.leftShoulder)
        torso.addLine(to: pose.rightShoulder)
        torso.addLine(to: pose.rightHip)
        torso.addLine(to: pose.leftHip)
        torso.closeSubpath()
        let torsoFillColor = dashed ? color.opacity(0.08) : palette.torso.opacity(0.20)
        context.fill(torso, with: .color(torsoFillColor))

        if dashed {
            let segments: [(CGPoint, CGPoint)] = [
                (pose.leftShoulder, pose.rightShoulder),
                (pose.leftShoulder, pose.leftElbow),
                (pose.leftElbow, pose.leftWrist),
                (pose.rightShoulder, pose.rightElbow),
                (pose.rightElbow, pose.rightWrist),
                (pose.leftShoulder, pose.leftHip),
                (pose.rightShoulder, pose.rightHip),
                (pose.leftHip, pose.rightHip),
                (pose.leftHip, pose.leftKnee),
                (pose.leftKnee, pose.leftAnkle),
                (pose.rightHip, pose.rightKnee),
                (pose.rightKnee, pose.rightAnkle),
                (pose.leftAnkle, pose.leftHeel),
                (pose.leftAnkle, pose.leftToe),
                (pose.leftHeel, pose.leftToe),
                (pose.rightAnkle, pose.rightHeel),
                (pose.rightAnkle, pose.rightToe),
                (pose.rightHeel, pose.rightToe)
            ]

            for (start, end) in segments {
                drawSegment(
                    from: start,
                    to: end,
                    color: color.opacity(0.72),
                    lineWidth: lineWidth,
                    dashed: true,
                    in: &context
                )
            }
        } else {
            drawSegment(from: pose.leftShoulder, to: pose.rightShoulder, color: palette.shoulderLine, lineWidth: lineWidth, dashed: false, in: &context)
            drawSegment(from: pose.leftShoulder, to: pose.leftElbow, color: palette.armLeft, lineWidth: lineWidth, dashed: false, in: &context)
            drawSegment(from: pose.leftElbow, to: pose.leftWrist, color: palette.armLeft, lineWidth: lineWidth, dashed: false, in: &context)
            drawSegment(from: pose.rightShoulder, to: pose.rightElbow, color: palette.armRight, lineWidth: lineWidth, dashed: false, in: &context)
            drawSegment(from: pose.rightElbow, to: pose.rightWrist, color: palette.armRight, lineWidth: lineWidth, dashed: false, in: &context)

            drawSegment(from: pose.leftShoulder, to: pose.leftHip, color: palette.torso, lineWidth: lineWidth, dashed: false, in: &context)
            drawSegment(from: pose.rightShoulder, to: pose.rightHip, color: palette.torso, lineWidth: lineWidth, dashed: false, in: &context)
            drawSegment(from: pose.leftHip, to: pose.rightHip, color: palette.hipLine, lineWidth: lineWidth, dashed: false, in: &context)

            drawSegment(from: pose.leftHip, to: pose.leftKnee, color: palette.leftLeg, lineWidth: lineWidth, dashed: false, in: &context)
            drawSegment(from: pose.leftKnee, to: pose.leftAnkle, color: palette.leftLeg, lineWidth: lineWidth, dashed: false, in: &context)
            drawSegment(from: pose.rightHip, to: pose.rightKnee, color: palette.rightLeg, lineWidth: lineWidth, dashed: false, in: &context)
            drawSegment(from: pose.rightKnee, to: pose.rightAnkle, color: palette.rightLeg, lineWidth: lineWidth, dashed: false, in: &context)

            drawSegment(from: pose.leftAnkle, to: pose.leftHeel, color: palette.foot, lineWidth: lineWidth * 0.90, dashed: false, in: &context)
            drawSegment(from: pose.leftAnkle, to: pose.leftToe, color: palette.foot, lineWidth: lineWidth * 0.90, dashed: false, in: &context)
            drawSegment(from: pose.leftHeel, to: pose.leftToe, color: palette.foot, lineWidth: lineWidth * 0.90, dashed: false, in: &context)
            drawSegment(from: pose.rightAnkle, to: pose.rightHeel, color: palette.foot, lineWidth: lineWidth * 0.90, dashed: false, in: &context)
            drawSegment(from: pose.rightAnkle, to: pose.rightToe, color: palette.foot, lineWidth: lineWidth * 0.90, dashed: false, in: &context)
            drawSegment(from: pose.rightHeel, to: pose.rightToe, color: palette.foot, lineWidth: lineWidth * 0.90, dashed: false, in: &context)
        }

        let headRect = CGRect(
            x: pose.headCenter.x - pose.headRadius,
            y: pose.headCenter.y - pose.headRadius,
            width: pose.headRadius * 2,
            height: pose.headRadius * 2
        )
        let headColor = dashed ? color.opacity(0.42) : palette.head
        context.fill(Path(ellipseIn: headRect), with: .color(headColor))

        if dashed {
            drawJointHighlights(
                points: pose.jointsForMarkers,
                radius: jointRadius + (pulse * 0.4),
                color: color,
                in: &context
            )
            return
        }

        drawJointMarker(at: pose.leftShoulder, radius: jointRadius, color: palette.shoulderLine, in: &context)
        drawJointMarker(at: pose.rightShoulder, radius: jointRadius, color: palette.shoulderLine, in: &context)
        drawJointMarker(at: pose.leftElbow, radius: jointRadius * 0.98, color: palette.armLeft, in: &context)
        drawJointMarker(at: pose.rightElbow, radius: jointRadius * 0.98, color: palette.armRight, in: &context)
        drawJointMarker(at: pose.leftWrist, radius: jointRadius * 0.94, color: palette.hand, in: &context)
        drawJointMarker(at: pose.rightWrist, radius: jointRadius * 0.94, color: palette.hand, in: &context)
        drawJointMarker(at: pose.leftHip, radius: jointRadius, color: palette.hipLine, in: &context)
        drawJointMarker(at: pose.rightHip, radius: jointRadius, color: palette.hipLine, in: &context)
        drawJointMarker(at: pose.leftKnee, radius: jointRadius * 1.02, color: palette.knee, in: &context)
        drawJointMarker(at: pose.rightKnee, radius: jointRadius * 1.02, color: palette.knee, in: &context)
        drawJointMarker(at: pose.leftAnkle, radius: jointRadius * 0.98, color: palette.ankle, in: &context)
        drawJointMarker(at: pose.rightAnkle, radius: jointRadius * 0.98, color: palette.ankle, in: &context)
        drawJointMarker(at: pose.leftHeel, radius: jointRadius * 0.90, color: palette.foot, in: &context)
        drawJointMarker(at: pose.rightHeel, radius: jointRadius * 0.90, color: palette.foot, in: &context)
        drawJointMarker(at: pose.leftToe, radius: jointRadius * 0.88, color: palette.foot, in: &context)
        drawJointMarker(at: pose.rightToe, radius: jointRadius * 0.88, color: palette.foot, in: &context)

        let leftHandRadius = handRadius(elbow: pose.leftElbow, wrist: pose.leftWrist)
        let rightHandRadius = handRadius(elbow: pose.rightElbow, wrist: pose.rightWrist)
        drawHandMarker(center: pose.leftWrist, radius: leftHandRadius, color: palette.hand, in: &context)
        drawHandMarker(center: pose.rightWrist, radius: rightHandRadius, color: palette.hand, in: &context)
    }

    private func drawSegment(
        from start: CGPoint,
        to end: CGPoint,
        color: Color,
        lineWidth: CGFloat,
        dashed: Bool,
        in context: inout GraphicsContext
    ) {
        var limb = Path()
        limb.move(to: start)
        limb.addLine(to: end)
        context.stroke(
            limb,
            with: .color(color),
            style: StrokeStyle(
                lineWidth: lineWidth,
                lineCap: .round,
                lineJoin: .round,
                dash: dashed ? [9, 8] : []
            )
        )
    }

    private func handRadius(elbow: CGPoint, wrist: CGPoint) -> CGFloat {
        max(4.5, min(11, distance(elbow, wrist) * 0.34))
    }

    private func drawHandMarker(
        center: CGPoint,
        radius: CGFloat,
        color: Color,
        in context: inout GraphicsContext
    ) {
        let halo = CGRect(
            x: center.x - (radius + 3.5),
            y: center.y - (radius + 3.5),
            width: (radius + 3.5) * 2,
            height: (radius + 3.5) * 2
        )
        context.fill(Path(ellipseIn: halo), with: .color(color.opacity(0.20)))

        let circle = CGRect(
            x: center.x - radius,
            y: center.y - radius,
            width: radius * 2,
            height: radius * 2
        )
        context.fill(Path(ellipseIn: circle), with: .color(color.opacity(0.95)))
    }

    private func drawJointMarker(
        at point: CGPoint,
        radius: CGFloat,
        color: Color,
        in context: inout GraphicsContext
    ) {
        let halo = CGRect(
            x: point.x - (radius + 2.8),
            y: point.y - (radius + 2.8),
            width: (radius + 2.8) * 2,
            height: (radius + 2.8) * 2
        )
        context.fill(Path(ellipseIn: halo), with: .color(color.opacity(0.18)))

        let marker = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
        context.fill(Path(ellipseIn: marker), with: .color(color.opacity(0.96)))
    }

    private func drawJointHighlights(
        points: [CGPoint],
        radius: CGFloat,
        color: Color,
        in context: inout GraphicsContext
    ) {
        for point in points {
            let haloRadius = radius + 2.8
            let halo = CGRect(
                x: point.x - haloRadius,
                y: point.y - haloRadius,
                width: haloRadius * 2,
                height: haloRadius * 2
            )
            context.fill(Path(ellipseIn: halo), with: .color(color.opacity(0.18)))

            let marker = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
            context.fill(Path(ellipseIn: marker), with: .color(color.opacity(0.96)))
        }
    }

    private func palette(for level: GuidanceLevel) -> GuidancePalette {
        switch level {
        case .good:
            return GuidancePalette(
                head: Color(red: 0.44, green: 0.86, blue: 1.0),
                shoulderLine: Color(red: 0.34, green: 0.77, blue: 1.0),
                torso: Color(red: 0.22, green: 0.72, blue: 0.99),
                armLeft: Color(red: 0.62, green: 0.60, blue: 0.99),
                armRight: Color(red: 0.74, green: 0.58, blue: 0.96),
                hand: Color(red: 0.84, green: 0.63, blue: 0.96),
                hipLine: Color(red: 0.18, green: 0.88, blue: 0.72),
                leftLeg: Color(red: 0.18, green: 0.86, blue: 0.43),
                rightLeg: Color(red: 0.20, green: 0.78, blue: 0.58),
                knee: Color(red: 0.97, green: 0.79, blue: 0.25),
                ankle: Color(red: 0.98, green: 0.67, blue: 0.30),
                foot: Color(red: 0.98, green: 0.86, blue: 0.45)
            )
        case .warning:
            return GuidancePalette(
                head: Color(red: 0.98, green: 0.82, blue: 0.40),
                shoulderLine: Color(red: 0.98, green: 0.74, blue: 0.33),
                torso: Color(red: 0.97, green: 0.64, blue: 0.30),
                armLeft: Color(red: 0.99, green: 0.71, blue: 0.49),
                armRight: Color(red: 0.99, green: 0.67, blue: 0.45),
                hand: Color(red: 0.99, green: 0.80, blue: 0.57),
                hipLine: Color(red: 0.95, green: 0.57, blue: 0.24),
                leftLeg: Color(red: 0.97, green: 0.63, blue: 0.22),
                rightLeg: Color(red: 0.93, green: 0.56, blue: 0.20),
                knee: Color(red: 0.98, green: 0.76, blue: 0.32),
                ankle: Color(red: 0.99, green: 0.69, blue: 0.32),
                foot: Color(red: 0.99, green: 0.78, blue: 0.45)
            )
        case .critical:
            return GuidancePalette(
                head: Color(red: 0.99, green: 0.53, blue: 0.45),
                shoulderLine: Color(red: 0.97, green: 0.40, blue: 0.33),
                torso: Color(red: 0.93, green: 0.30, blue: 0.28),
                armLeft: Color(red: 0.96, green: 0.38, blue: 0.41),
                armRight: Color(red: 0.95, green: 0.34, blue: 0.37),
                hand: Color(red: 0.99, green: 0.56, blue: 0.51),
                hipLine: Color(red: 0.92, green: 0.26, blue: 0.24),
                leftLeg: Color(red: 0.95, green: 0.32, blue: 0.26),
                rightLeg: Color(red: 0.90, green: 0.24, blue: 0.22),
                knee: Color(red: 0.99, green: 0.67, blue: 0.44),
                ankle: Color(red: 0.99, green: 0.58, blue: 0.38),
                foot: Color(red: 0.99, green: 0.71, blue: 0.49)
            )
        }
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }

    private func normalizedVector(from start: CGPoint, to end: CGPoint, fallback: CGPoint) -> CGPoint {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let magnitude = hypot(dx, dy)
        if magnitude < 0.001 {
            let fallbackMagnitude = max(0.001, hypot(fallback.x, fallback.y))
            return CGPoint(x: fallback.x / fallbackMagnitude, y: fallback.y / fallbackMagnitude)
        }
        return CGPoint(x: dx / magnitude, y: dy / magnitude)
    }

    private func point(from start: CGPoint, direction: CGPoint, length: CGFloat) -> CGPoint {
        CGPoint(
            x: start.x + (direction.x * length),
            y: start.y + (direction.y * length)
        )
    }

    private func constrainedPoint(
        from start: CGPoint,
        toward target: CGPoint,
        length: CGFloat,
        fallbackDirection: CGPoint
    ) -> CGPoint {
        let unit = normalizedVector(from: start, to: target, fallback: fallbackDirection)
        return point(from: start, direction: unit, length: length)
    }

    private func motionProgress(for phase: CGFloat) -> CGFloat {
        let eased = phase * phase * (3 - (2 * phase))
        let intensity = showsInstructionCard ? 1.14 : 1.22
        return min(1, max(0, eased * intensity))
    }

    private func estimatedLungeLead(from anchors: GuideAnchors) -> LegSide {
        let leftAngle = kneeAngle(hip: anchors.leftHip, knee: anchors.leftKnee, ankle: anchors.leftAnkle)
        let rightAngle = kneeAngle(hip: anchors.rightHip, knee: anchors.rightKnee, ankle: anchors.rightAnkle)
        let delta = leftAngle - rightAngle
        if delta < -4 {
            return .left
        }
        if delta > 4 {
            return .right
        }
        return anchors.leftKnee.y > anchors.rightKnee.y ? .left : .right
    }

    private func kneeAngle(hip: CGPoint, knee: CGPoint, ankle: CGPoint) -> CGFloat {
        let v1 = CGPoint(x: hip.x - knee.x, y: hip.y - knee.y)
        let v2 = CGPoint(x: ankle.x - knee.x, y: ankle.y - knee.y)
        let mag = max(0.001, hypot(v1.x, v1.y) * hypot(v2.x, v2.y))
        let dot = (v1.x * v2.x) + (v1.y * v2.y)
        let cosine = max(-1, min(1, dot / mag))
        return acos(cosine) * 180 / .pi
    }

    private func drawArrowHead(
        at tip: CGPoint,
        from start: CGPoint,
        color: Color,
        in context: inout GraphicsContext
    ) {
        let angle = atan2(tip.y - start.y, tip.x - start.x)
        let arrowLength: CGFloat = 14
        let spread: CGFloat = 0.62
        let p1 = CGPoint(
            x: tip.x - (arrowLength * cos(angle - spread)),
            y: tip.y - (arrowLength * sin(angle - spread))
        )
        let p2 = CGPoint(
            x: tip.x - (arrowLength * cos(angle + spread)),
            y: tip.y - (arrowLength * sin(angle + spread))
        )

        var head = Path()
        head.move(to: tip)
        head.addLine(to: p1)
        head.addLine(to: p2)
        head.closeSubpath()
        context.fill(head, with: .color(color.opacity(0.92)))
    }

    private func guideAnchors(in size: CGSize) -> GuideAnchors {
        let leftHipResult = trackedBodyPoint(.leftHip, in: size, fallback: CGPoint(x: size.width * 0.46, y: size.height * 0.45))
        let rightHipResult = trackedBodyPoint(.rightHip, in: size, fallback: CGPoint(x: size.width * 0.54, y: size.height * 0.45))
        let leftKneeResult = trackedBodyPoint(.leftKnee, in: size, fallback: CGPoint(x: size.width * 0.45, y: size.height * 0.62))
        let rightKneeResult = trackedBodyPoint(.rightKnee, in: size, fallback: CGPoint(x: size.width * 0.55, y: size.height * 0.62))
        let leftAnkleResult = trackedBodyPoint(.leftAnkle, in: size, fallback: CGPoint(x: size.width * 0.45, y: size.height * 0.79))
        let rightAnkleResult = trackedBodyPoint(.rightAnkle, in: size, fallback: CGPoint(x: size.width * 0.55, y: size.height * 0.79))

        let defaultShoulderY = ((leftHipResult.point.y + rightHipResult.point.y) * 0.5) - 118
        let leftShoulderResult = trackedCustomPoint("leftShoulder", in: size, fallback: CGPoint(x: leftHipResult.point.x - 16, y: defaultShoulderY))
        let rightShoulderResult = trackedCustomPoint("rightShoulder", in: size, fallback: CGPoint(x: rightHipResult.point.x + 16, y: defaultShoulderY))
        let measuredShoulderWidth = max(40, abs(rightShoulderResult.point.x - leftShoulderResult.point.x))
        let estimatedTorso = max(72, abs(defaultShoulderY - ((leftHipResult.point.y + rightHipResult.point.y) * 0.5)))

        let leftElbowFallback = CGPoint(
            x: leftShoulderResult.point.x - (measuredShoulderWidth * 0.34),
            y: leftShoulderResult.point.y + (estimatedTorso * 0.44)
        )
        let rightElbowFallback = CGPoint(
            x: rightShoulderResult.point.x + (measuredShoulderWidth * 0.34),
            y: rightShoulderResult.point.y + (estimatedTorso * 0.44)
        )
        let leftWristFallback = CGPoint(
            x: leftShoulderResult.point.x - (measuredShoulderWidth * 0.24),
            y: leftShoulderResult.point.y + (estimatedTorso * 0.84)
        )
        let rightWristFallback = CGPoint(
            x: rightShoulderResult.point.x + (measuredShoulderWidth * 0.24),
            y: rightShoulderResult.point.y + (estimatedTorso * 0.84)
        )
        let leftElbowResult = trackedCustomPoint("leftElbow", in: size, fallback: leftElbowFallback)
        let rightElbowResult = trackedCustomPoint("rightElbow", in: size, fallback: rightElbowFallback)
        let leftWristResult = trackedCustomPoint("leftWrist", in: size, fallback: leftWristFallback)
        let rightWristResult = trackedCustomPoint("rightWrist", in: size, fallback: rightWristFallback)
        let neckFallback = CGPoint(
            x: (leftShoulderResult.point.x + rightShoulderResult.point.x) * 0.5,
            y: (leftShoulderResult.point.y + rightShoulderResult.point.y) * 0.5 + 4
        )
        let neckResult = trackedCustomPoint("neck", in: size, fallback: neckFallback)

        return GuideAnchors(
            leftShoulder: leftShoulderResult.point,
            rightShoulder: rightShoulderResult.point,
            neck: neckResult.point,
            leftElbow: leftElbowResult.point,
            rightElbow: rightElbowResult.point,
            leftWrist: leftWristResult.point,
            rightWrist: rightWristResult.point,
            leftHip: leftHipResult.point,
            rightHip: rightHipResult.point,
            leftKnee: leftKneeResult.point,
            rightKnee: rightKneeResult.point,
            leftAnkle: leftAnkleResult.point,
            rightAnkle: rightAnkleResult.point,
            trackedGuidancePoints: [
                leftShoulderResult.tracked ? leftShoulderResult.point : nil,
                rightShoulderResult.tracked ? rightShoulderResult.point : nil,
                leftElbowResult.tracked ? leftElbowResult.point : nil,
                rightElbowResult.tracked ? rightElbowResult.point : nil,
                leftWristResult.tracked ? leftWristResult.point : nil,
                rightWristResult.tracked ? rightWristResult.point : nil,
                leftHipResult.tracked ? leftHipResult.point : nil,
                rightHipResult.tracked ? rightHipResult.point : nil,
                leftKneeResult.tracked ? leftKneeResult.point : nil,
                rightKneeResult.tracked ? rightKneeResult.point : nil,
                leftAnkleResult.tracked ? leftAnkleResult.point : nil,
                rightAnkleResult.tracked ? rightAnkleResult.point : nil
            ].compactMap { $0 }
        )
    }

    private func bodyPoint(_ joint: BodyJoint, in size: CGSize) -> CGPoint? {
        guard let pose = frame?.point(for: joint), pose.confidence >= 0.25 else { return nil }
        return CGPoint(x: pose.x * size.width, y: (1 - pose.y) * size.height)
    }

    private func customPoint(_ key: String, in size: CGSize) -> CGPoint? {
        guard let pose = frame?.joints[key], pose.confidence >= 0.25 else { return nil }
        return CGPoint(x: pose.x * size.width, y: (1 - pose.y) * size.height)
    }

    private func trackedBodyPoint(_ joint: BodyJoint, in size: CGSize, fallback: CGPoint) -> (point: CGPoint, tracked: Bool) {
        if let point = bodyPoint(joint, in: size) {
            return (point, true)
        }
        return (fallback, false)
    }

    private func trackedCustomPoint(_ key: String, in size: CGSize, fallback: CGPoint) -> (point: CGPoint, tracked: Bool) {
        if let point = customPoint(key, in: size) {
            return (point, true)
        }
        return (fallback, false)
    }
}

private struct GuideAnchors {
    let leftShoulder: CGPoint
    let rightShoulder: CGPoint
    let neck: CGPoint
    let leftElbow: CGPoint
    let rightElbow: CGPoint
    let leftWrist: CGPoint
    let rightWrist: CGPoint
    let leftHip: CGPoint
    let rightHip: CGPoint
    let leftKnee: CGPoint
    let rightKnee: CGPoint
    let leftAnkle: CGPoint
    let rightAnkle: CGPoint
    let trackedGuidancePoints: [CGPoint]

    var hipCenter: CGPoint {
        CGPoint(x: (leftHip.x + rightHip.x) * 0.5, y: (leftHip.y + rightHip.y) * 0.5)
    }

    var hipWidth: CGFloat {
        abs(rightHip.x - leftHip.x)
    }

    var estimatedLegLength: CGFloat {
        let leftLeg = hypot(leftHip.x - leftKnee.x, leftHip.y - leftKnee.y)
            + hypot(leftKnee.x - leftAnkle.x, leftKnee.y - leftAnkle.y)
        let rightLeg = hypot(rightHip.x - rightKnee.x, rightHip.y - rightKnee.y)
            + hypot(rightKnee.x - rightAnkle.x, rightKnee.y - rightAnkle.y)
        return max(120, (leftLeg + rightLeg) * 0.5)
    }

    var shoulderCenter: CGPoint {
        CGPoint(x: (leftShoulder.x + rightShoulder.x) * 0.5, y: (leftShoulder.y + rightShoulder.y) * 0.5)
    }

    var shoulderWidth: CGFloat {
        max(40, abs(rightShoulder.x - leftShoulder.x))
    }

    var torsoHeight: CGFloat {
        max(72, min(170, distance(hipCenter, shoulderCenter)))
    }

    var hasTrackedPose: Bool {
        trackedGuidancePoints.count >= 5
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }
}

private struct GuidanceVisualState {
    let score: Double
    let color: Color
    let level: GuidanceLevel
    let lungeLead: LegSide
}

private enum GuidanceLevel {
    case good
    case warning
    case critical
}

private struct GuidancePalette {
    let head: Color
    let shoulderLine: Color
    let torso: Color
    let armLeft: Color
    let armRight: Color
    let hand: Color
    let hipLine: Color
    let leftLeg: Color
    let rightLeg: Color
    let knee: Color
    let ankle: Color
    let foot: Color
}

private struct GuideBodyPose {
    let headCenter: CGPoint
    let headRadius: CGFloat
    let leftShoulder: CGPoint
    let rightShoulder: CGPoint
    let leftElbow: CGPoint
    let rightElbow: CGPoint
    let leftWrist: CGPoint
    let rightWrist: CGPoint
    let leftHip: CGPoint
    let rightHip: CGPoint
    let leftKnee: CGPoint
    let rightKnee: CGPoint
    let leftAnkle: CGPoint
    let rightAnkle: CGPoint
    let leftHeel: CGPoint
    let rightHeel: CGPoint
    let leftToe: CGPoint
    let rightToe: CGPoint
    let lungeLead: LegSide

    var leftHipCenter: CGPoint {
        CGPoint(x: (leftHip.x + rightHip.x) * 0.5, y: (leftHip.y + rightHip.y) * 0.5)
    }

    var leadingKnee: CGPoint {
        lungeLead == .left ? leftKnee : rightKnee
    }

    var jointsForMarkers: [CGPoint] {
        [
            leftShoulder,
            rightShoulder,
            leftElbow,
            rightElbow,
            leftWrist,
            rightWrist,
            leftHip,
            rightHip,
            leftKnee,
            rightKnee,
            leftAnkle,
            rightAnkle,
            leftHeel,
            rightHeel,
            leftToe,
            rightToe
        ]
    }
}

private struct TVPoseOverlay: View {
    let frame: PoseFrame?
    let selectedExercise: TVExerciseProgram
    let framingMode: TVFramingMode
    let isCalibrating: Bool
    let isSessionRunning: Bool

    private let skeletonSegments: [(start: OverlayJoint, end: OverlayJoint, part: OverlayBodyPart)] = [
        (.custom("leftShoulder"), .custom("rightShoulder"), .shoulderLine),
        (.custom("leftShoulder"), .body(.leftHip), .torso),
        (.custom("rightShoulder"), .body(.rightHip), .torso),
        (.body(.leftHip), .body(.rightHip), .hipLine),
        (.body(.leftHip), .body(.leftKnee), .leftLeg),
        (.body(.leftKnee), .body(.leftAnkle), .leftLeg),
        (.body(.rightHip), .body(.rightKnee), .rightLeg),
        (.body(.rightKnee), .body(.rightAnkle), .rightLeg)
    ]

    private let visibleJointOrder: [(joint: OverlayJoint, part: OverlayBodyPart)] = [
        (.custom("neck"), .head),
        (.custom("leftShoulder"), .shoulderLine),
        (.custom("rightShoulder"), .shoulderLine),
        (.body(.leftHip), .hipLine),
        (.body(.rightHip), .hipLine),
        (.body(.leftKnee), .knee),
        (.body(.rightKnee), .knee),
        (.body(.leftAnkle), .ankle),
        (.body(.rightAnkle), .ankle)
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
                x: size.width * 0.16,
                y: size.height * 0.10,
                width: size.width * 0.68,
                height: size.height * 0.84
            )
        case .upperBody:
            return CGRect(
                x: size.width * 0.18,
                y: size.height * 0.08,
                width: size.width * 0.64,
                height: size.height * 0.60
            )
        case .feetToHalfBody:
            return CGRect(
                x: size.width * 0.17,
                y: size.height * 0.16,
                width: size.width * 0.66,
                height: size.height * 0.80
            )
        case .kneeFocus:
            return CGRect(
                x: size.width * 0.18,
                y: size.height * 0.24,
                width: size.width * 0.64,
                height: size.height * 0.66
            )
        case .heelFocus:
            return CGRect(
                x: size.width * 0.18,
                y: size.height * 0.34,
                width: size.width * 0.64,
                height: size.height * 0.58
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
        let tolerantZone = zoneRect.insetBy(dx: -28, dy: -24)

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
            let opacity = segmentOpacity(confidence: confidence, insideZone: insideZone, zoneState: zoneState)
            context.stroke(
                path,
                with: .color(overlayPartColor(segment.part).opacity(opacity)),
                style: StrokeStyle(lineWidth: 5.2, lineCap: .round, lineJoin: .round)
            )
        }

        drawVirtualFeet(frame, in: &context, size: size, zoneRect: zoneRect, zoneState: zoneState)

        for item in visibleJointOrder {
            guard let posePoint = posePoint(for: item.joint, in: frame) else { continue }
            let center = point(from: posePoint, in: size)

            let confidenceOpacity = segmentOpacity(
                confidence: posePoint.confidence,
                insideZone: zoneRect.contains(center),
                zoneState: zoneState
            )
            let color = overlayPartColor(item.part).opacity(confidenceOpacity)

            let haloRect = CGRect(x: center.x - 7, y: center.y - 7, width: 14, height: 14)
            context.fill(Path(ellipseIn: haloRect), with: .color(color.opacity(0.28)))

            let markerRect = CGRect(x: center.x - 4.8, y: center.y - 4.8, width: 9.6, height: 9.6)
            context.fill(Path(ellipseIn: markerRect), with: .color(color))
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
        let color = overlayPartColor(.foot).opacity(segmentOpacity(confidence: confidence, insideZone: insideZone, zoneState: zoneState))

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

    private func segmentOpacity(confidence: Double, insideZone: Bool, zoneState: ZoneState) -> Double {
        let confidenceFactor = max(0.30, min(1.0, confidence))
        let zoneFactor: Double = (insideZone || zoneState.score >= 0.50) ? 1.0 : 0.75
        return max(0.36, min(1.0, confidenceFactor * zoneFactor))
    }

    private func overlayPartColor(_ part: OverlayBodyPart) -> Color {
        switch part {
        case .head:
            return Color(red: 0.45, green: 0.86, blue: 1.0)
        case .shoulderLine:
            return Color(red: 0.36, green: 0.76, blue: 1.0)
        case .torso:
            return Color(red: 0.26, green: 0.73, blue: 0.96)
        case .hipLine:
            return Color(red: 0.22, green: 0.88, blue: 0.72)
        case .leftLeg:
            return Color(red: 0.16, green: 0.86, blue: 0.46)
        case .rightLeg:
            return Color(red: 0.20, green: 0.78, blue: 0.60)
        case .knee:
            return Color(red: 0.97, green: 0.79, blue: 0.25)
        case .ankle:
            return Color(red: 0.98, green: 0.67, blue: 0.30)
        case .foot:
            return Color(red: 0.99, green: 0.84, blue: 0.43)
        }
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

private enum OverlayBodyPart {
    case head
    case shoulderLine
    case torso
    case hipLine
    case leftLeg
    case rightLeg
    case knee
    case ankle
    case foot
}

private enum LegSide {
    case left
    case right
}
