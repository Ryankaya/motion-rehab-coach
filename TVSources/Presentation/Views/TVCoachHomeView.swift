import SwiftUI

struct TVCoachHomeView: View {
    @StateObject private var viewModel: TVCoachViewModel
    @State private var isOptionsPresented = false

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
        .sheet(isPresented: $isOptionsPresented) {
            TVCoachOptionsView(viewModel: viewModel)
        }
    }

    private var showsConnectView: Bool {
        viewModel.continuityCameraCount == 0 && viewModel.trackingState == .waitingForCamera
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
            ZStack(alignment: .topLeading) {
                TVCameraPreviewView(session: viewModel.captureSession)
                    .scaleEffect(viewModel.previewScale, anchor: .top)
                    .offset(y: viewModel.previewOffsetY)
                    .animation(.easeInOut(duration: 0.22), value: viewModel.previewScale)
                    .animation(.easeInOut(duration: 0.18), value: viewModel.previewOffsetY)

                TVPoseOverlay(
                    frame: viewModel.latestPoseFrame,
                    selectedExercise: viewModel.selectedExercise,
                    framingMode: viewModel.framingMode,
                    isCalibrating: viewModel.isCalibrating,
                    isSessionRunning: viewModel.isSessionRunning
                )
                .allowsHitTesting(false)

                VStack(spacing: 14) {
                    statusBar
                        .focusSection()
                    controlsDock(maxWidth: min(geometry.size.width - 42, 1240))
                        .focusSection()
                    Spacer(minLength: 0)
                }
                .padding(20)
            }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(.white.opacity(0.23), lineWidth: 1.2)
            )
            .shadow(color: .black.opacity(0.30), radius: 24, y: 12)
            .padding(14)
        }
    }

    private var statusBar: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(viewModel.selectedExercise.displayName)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                Text(viewModel.statusMessage)
                    .font(.headline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.86))
                    .lineLimit(2)
            }

            Spacer()

            statChip("Camera", viewModel.cameraName)
            statChip("Duration", viewModel.sessionDurationLabel)
            statChip("Calib", "\(Int(viewModel.calibrationProgress * 100))%")

            Button {
                viewModel.openDevicePicker()
            } label: {
                Label("Reconnect", systemImage: "iphone.gen3.camera")
                    .font(.headline.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color(red: 0.05, green: 0.42, blue: 0.68), in: Capsule())
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)

            Button {
                isOptionsPresented = true
            } label: {
                Label("Options", systemImage: "slider.horizontal.3")
                    .font(.headline.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color(red: 0.24, green: 0.31, blue: 0.41), in: Capsule())
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.black.opacity(0.43), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.14))
        )
    }

    private func controlsDock(maxWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                actionButton(
                    title: viewModel.calibrationActionTitle,
                    systemImage: "dot.scope",
                    fill: Color(red: 0.05, green: 0.58, blue: 0.47)
                ) {
                    viewModel.runCalibration()
                }

                actionButton(
                    title: viewModel.sessionActionTitle,
                    systemImage: viewModel.isSessionRunning ? "stop.fill" : "play.fill",
                    fill: viewModel.isSessionRunning
                        ? Color(red: 0.79, green: 0.22, blue: 0.20)
                        : Color(red: 0.03, green: 0.45, blue: 0.78)
                ) {
                    viewModel.toggleSession()
                }
            }

            Text(viewModel.feedback)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(3)
                .padding(.top, 2)

            Text("Use Options to change training, body focus, and coaching settings.")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.74))
                .lineLimit(2)
        }
        .frame(maxWidth: maxWidth, alignment: .leading)
        .padding(14)
        .background(.black.opacity(0.48), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.14))
        )
    }

    private func actionButton(
        title: String,
        systemImage: String,
        fill: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                Text(title)
                    .lineLimit(1)
            }
            .font(.headline.weight(.semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(fill, in: Capsule())
            .foregroundStyle(.white)
            .overlay(
                Capsule().strokeBorder(.white.opacity(0.16))
            )
        }
        .buttonStyle(.plain)
    }

    private func statChip(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.74))
            Text(value)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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

private struct TVCoachOptionsView: View {
    let viewModel: TVCoachViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var selectedExercise: TVExerciseProgram
    @State private var selectedFramingMode: TVFramingMode
    @State private var voiceEnabled: Bool

    init(viewModel: TVCoachViewModel) {
        self.viewModel = viewModel
        _selectedExercise = State(initialValue: viewModel.selectedExercise)
        _selectedFramingMode = State(initialValue: viewModel.framingMode)
        _voiceEnabled = State(initialValue: viewModel.voiceCoachingEnabled)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    optionCard("Training") {
                        Picker("Exercise", selection: $selectedExercise) {
                            ForEach(TVExerciseProgram.allCases) { exercise in
                                Label(exercise.displayName, systemImage: exercise.systemImage)
                                    .tag(exercise)
                            }
                        }
                        .pickerStyle(.menu)

                        Text(selectedExercise.calibrationCue)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white.opacity(0.72))
                    }

                    optionCard("Body Focus") {
                        Picker("Camera Focus", selection: $selectedFramingMode) {
                            ForEach(TVFramingMode.allCases) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        .pickerStyle(.menu)

                        Text(selectedFramingMode.subtitle)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white.opacity(0.72))

                        HStack(spacing: 10) {
                            optionButton("More Feet", systemImage: "arrow.down.to.line") {
                                viewModel.showMoreFeet()
                            }
                            optionButton("More Upper Body", systemImage: "arrow.up.to.line") {
                                viewModel.showMoreUpperBody()
                            }
                            optionButton("Reset", systemImage: "arrow.uturn.backward") {
                                viewModel.resetFramingAdjustments()
                            }
                        }
                    }

                    optionCard("Coaching") {
                        Toggle(isOn: $voiceEnabled) {
                            Label("Voice Direction", systemImage: "speaker.wave.2.fill")
                        }
                        .tint(Color(red: 0.04, green: 0.57, blue: 0.72))

                        Text("Voice cues adapt to selected training with stable timing.")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white.opacity(0.72))
                    }

                    optionCard("Session") {
                        HStack(spacing: 12) {
                            Button("Run Calibration") {
                                viewModel.runCalibration()
                                dismiss()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Color(red: 0.05, green: 0.58, blue: 0.47))

                            Button(viewModel.isSessionRunning ? "End Session" : "Start Session") {
                                viewModel.toggleSession()
                                dismiss()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(
                                viewModel.isSessionRunning
                                    ? Color(red: 0.79, green: 0.22, blue: 0.20)
                                    : Color(red: 0.03, green: 0.45, blue: 0.78)
                            )
                        }

                        Text("Choose body focus first, then run calibration and start session.")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white.opacity(0.72))
                    }
                }
                .padding(.horizontal, 34)
                .padding(.vertical, 28)
            }
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 0.03, green: 0.08, blue: 0.14),
                        Color(red: 0.05, green: 0.13, blue: 0.22)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            )
            .navigationTitle("Session Options")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .onChange(of: selectedExercise) { _, newValue in
                viewModel.selectExercise(newValue)
            }
            .onChange(of: selectedFramingMode) { _, newValue in
                viewModel.selectFramingMode(newValue)
            }
            .onChange(of: voiceEnabled) { _, newValue in
                viewModel.voiceCoachingEnabled = newValue
            }
        }
    }

    private func optionCard<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.black.opacity(0.38), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(0.13), lineWidth: 1.0)
        )
    }

    private func optionButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.11), in: Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
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
            TimelineView(.periodic(from: .now, by: 1.0 / 8.0)) { timeline in
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
        for joint in required {
            guard let posePoint = posePoint(for: joint, in: frame) else { continue }
            let point = point(from: posePoint, in: size)
            if zoneRect.contains(point), posePoint.confidence >= 0.45 {
                insideCount += 1
            }
        }

        let score = Double(insideCount) / Double(required.count)
        let color: Color
        if score >= 0.82 {
            color = Color(red: 0.12, green: 0.82, blue: 0.35)
        } else if score >= 0.55 {
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

        let sideFactor: CGFloat = side == .left ? -1 : 1
        let heelPoint = CGPoint(
            x: anklePoint.x + (norm.x * 14) + (perp.x * 5 * sideFactor),
            y: anklePoint.y + (norm.y * 14) + (perp.y * 5 * sideFactor)
        )
        let toePoint = CGPoint(
            x: anklePoint.x + (norm.x * 7) - (perp.x * 13 * sideFactor),
            y: anklePoint.y + (norm.y * 7) - (perp.y * 13 * sideFactor)
        )

        var path = Path()
        path.move(to: heelPoint)
        path.addLine(to: toePoint)

        let confidence = min(knee.confidence, ankle.confidence)
        let insideZone = zoneRect.contains(heelPoint) || zoneRect.contains(toePoint)
        context.stroke(
            path,
            with: .color(trackingColor(confidence: confidence, insideZone: insideZone, zoneState: zoneState)),
            style: StrokeStyle(lineWidth: 4.4, lineCap: .round, lineJoin: .round)
        )
    }

    private func drawGuideFigure(in context: inout GraphicsContext, size: CGSize, phase: CGFloat) {
        let centerX = size.width * 0.5
        let motionDepth = guideDepth(for: selectedExercise) * phase

        let shoulderY = size.height * 0.20 + motionDepth * 8
        let hipY = size.height * 0.43 + motionDepth * 18
        let kneeY = size.height * 0.66 + motionDepth * 14
        let ankleY = size.height * 0.86 + max(motionDepth * 18, 0)

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

        let guideColor = Color(red: 0.24, green: 0.84, blue: 0.61).opacity(0.62)
        context.stroke(
            skeleton,
            with: .color(guideColor),
            style: StrokeStyle(lineWidth: 4.2, lineCap: .round, lineJoin: .round)
        )

        var kneesPath = Path()
        kneesPath.move(to: CGPoint(x: leftHip.x, y: leftKnee.y))
        kneesPath.addLine(to: leftKnee)
        kneesPath.move(to: CGPoint(x: rightHip.x, y: rightKnee.y))
        kneesPath.addLine(to: rightKnee)
        context.stroke(
            kneesPath,
            with: .color(guideColor.opacity(0.55)),
            style: StrokeStyle(lineWidth: 2.2, lineCap: .round, dash: [6, 5])
        )

        var feetPath = Path()
        feetPath.move(to: CGPoint(x: leftAnkle.x - 14, y: leftAnkle.y + 8))
        feetPath.addLine(to: CGPoint(x: leftAnkle.x + 10, y: leftAnkle.y + 8))
        feetPath.move(to: CGPoint(x: rightAnkle.x - 10, y: rightAnkle.y + 8))
        feetPath.addLine(to: CGPoint(x: rightAnkle.x + 14, y: rightAnkle.y + 8))
        context.stroke(
            feetPath,
            with: .color(guideColor.opacity(0.76)),
            style: StrokeStyle(lineWidth: 3.4, lineCap: .round)
        )

        let headRect = CGRect(x: centerX - 10, y: shoulderY - 24, width: 20, height: 20)
        context.fill(Path(ellipseIn: headRect), with: .color(guideColor))
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
        if confidence >= 0.68 && insideZone {
            return zoneState.color
        }
        if confidence >= 0.45 {
            return Color(red: 0.96, green: 0.68, blue: 0.18)
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
