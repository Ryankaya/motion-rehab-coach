import Foundation

struct RepetitionSnapshot {
    let repetitionCount: Int
    let primaryMetricValue: Double?
    let qualityScore: Double
    let feedback: String
}

final class RepetitionAnalyzer {
    private let exerciseType: ExerciseType

    private var repetitionCount = 0
    private var reachedDepth = false
    private var currentRepMinAngle = 180.0
    private var repQualityScores: [Double] = []

    private var activeLungeSide: BodySide?
    private var baselineAnkleY: Double?
    private var peakAnkleRise = 0.0

    init(exerciseType: ExerciseType = .squat) {
        self.exerciseType = exerciseType
    }

    func reset() {
        repetitionCount = 0
        reachedDepth = false
        currentRepMinAngle = 180.0
        repQualityScores.removeAll(keepingCapacity: true)
        activeLungeSide = nil
        baselineAnkleY = nil
        peakAnkleRise = 0
    }

    func process(_ frame: PoseFrame) -> RepetitionSnapshot? {
        switch exerciseType {
        case .squat:
            return processBilateral(frame, profile: .squat)
        case .sitToStand:
            return processBilateral(frame, profile: .sitToStand)
        case .miniSquat:
            return processBilateral(frame, profile: .miniSquat)
        case .lunge:
            return processLunge(frame)
        case .calfRaise:
            return processCalfRaise(frame)
        }
    }

    var latestRepetitionCount: Int { repetitionCount }
    var qualityScore: Double { repQualityScores.average }

    private func processBilateral(_ frame: PoseFrame, profile: BilateralProfile) -> RepetitionSnapshot {
        guard let kneeAngle = averageKneeAngle(from: frame) else {
            return snapshot(metric: nil, feedback: "Move into frame so both legs are visible.")
        }

        var feedback = profile.feedback(for: kneeAngle)

        if kneeAngle < profile.downThreshold {
            reachedDepth = true
            currentRepMinAngle = min(currentRepMinAngle, kneeAngle)
            feedback = profile.bottomFeedback
        }

        if reachedDepth && kneeAngle > profile.upThreshold {
            repetitionCount += 1
            repQualityScores.append(profile.qualityScore(for: currentRepMinAngle))
            reachedDepth = false
            currentRepMinAngle = 180.0
            feedback = "Rep \(repetitionCount) completed. Great control."
        }

        return snapshot(metric: kneeAngle, feedback: feedback)
    }

    private func processLunge(_ frame: PoseFrame) -> RepetitionSnapshot {
        let kneeAngles = legKneeAngles(from: frame)

        guard let leftAngle = kneeAngles.left, let rightAngle = kneeAngles.right else {
            return snapshot(metric: nil, feedback: "Keep both knees and ankles in frame for lunge tracking.")
        }

        let frontSide: BodySide = leftAngle < rightAngle ? .left : .right
        let frontAngle = min(leftAngle, rightAngle)
        let asymmetry = abs(leftAngle - rightAngle)

        let depthThreshold = 105.0
        let returnThreshold = 155.0
        let stanceThreshold = 12.0

        var feedback = "Lower into your lunge with control."

        if !reachedDepth {
            if asymmetry < stanceThreshold {
                feedback = "Step into a split stance before lowering."
                return snapshot(metric: frontAngle, feedback: feedback)
            }

            if frontAngle < depthThreshold {
                reachedDepth = true
                activeLungeSide = frontSide
                currentRepMinAngle = frontAngle
                feedback = "Great depth. Drive through your front heel to stand."
            }
        } else {
            let trackedAngle: Double
            switch activeLungeSide {
            case .left:
                trackedAngle = leftAngle
            case .right:
                trackedAngle = rightAngle
            case .none:
                trackedAngle = frontAngle
            }

            currentRepMinAngle = min(currentRepMinAngle, trackedAngle)
            feedback = "Push up with control and return to tall stance."

            if min(leftAngle, rightAngle) > returnThreshold {
                repetitionCount += 1
                repQualityScores.append(scoreForLunge(minAngle: currentRepMinAngle))
                reachedDepth = false
                currentRepMinAngle = 180
                activeLungeSide = nil
                feedback = "Rep \(repetitionCount) completed. Strong lunge."
            }
        }

        return snapshot(metric: frontAngle, feedback: feedback)
    }

    private func processCalfRaise(_ frame: PoseFrame) -> RepetitionSnapshot {
        guard let averageAnkleY = averageAnkleY(from: frame) else {
            return snapshot(metric: nil, feedback: "Keep both ankles visible for calf raise tracking.")
        }

        guard let kneeAngle = averageKneeAngle(from: frame) else {
            return snapshot(metric: nil, feedback: "Keep your knees visible and stand tall.")
        }

        if baselineAnkleY == nil {
            baselineAnkleY = averageAnkleY
        }

        guard let baselineAnkleY else {
            return snapshot(metric: nil, feedback: "Preparing tracking baseline.")
        }

        if !reachedDepth && kneeAngle > 150 {
            self.baselineAnkleY = (baselineAnkleY * 0.92) + (averageAnkleY * 0.08)
        }

        let ankleRise = max(0, averageAnkleY - baselineAnkleY)
        let ankleRisePercent = ankleRise * 100

        if kneeAngle < 145 {
            return snapshot(metric: ankleRisePercent, feedback: "Keep knees straighter while lifting your heels.")
        }

        var feedback = "Rise onto your toes."
        if ankleRise > 0.022 {
            reachedDepth = true
            peakAnkleRise = max(peakAnkleRise, ankleRise)
            feedback = "Great height. Hold briefly, then lower slowly."
        } else if ankleRise > 0.010 {
            feedback = "Lift a little higher onto your toes."
        }

        if reachedDepth && ankleRise < 0.008 {
            repetitionCount += 1
            repQualityScores.append(scoreForCalfRaise(peakRise: peakAnkleRise))
            reachedDepth = false
            peakAnkleRise = 0
            feedback = "Rep \(repetitionCount) completed. Controlled calf raise."
        }

        return snapshot(metric: ankleRisePercent, feedback: feedback)
    }

    private func snapshot(metric: Double?, feedback: String) -> RepetitionSnapshot {
        RepetitionSnapshot(
            repetitionCount: repetitionCount,
            primaryMetricValue: metric,
            qualityScore: qualityScore,
            feedback: feedback
        )
    }

    private func scoreForLunge(minAngle: Double) -> Double {
        switch minAngle {
        case 78...102:
            return 95
        case 65..<78, 102...118:
            return 82
        case 55..<65, 118...130:
            return 68
        default:
            return 50
        }
    }

    private func scoreForCalfRaise(peakRise: Double) -> Double {
        switch peakRise {
        case 0.030...:
            return 95
        case 0.024..<0.030:
            return 84
        case 0.018..<0.024:
            return 70
        default:
            return 55
        }
    }

    private func averageKneeAngle(from frame: PoseFrame) -> Double? {
        let kneeAngles = legKneeAngles(from: frame)
        return [kneeAngles.left, kneeAngles.right].compactMap { $0 }.averageOrNil
    }

    private func averageAnkleY(from frame: PoseFrame) -> Double? {
        guard
            let leftAnkle = frame.point(for: .leftAnkle)?.y,
            let rightAnkle = frame.point(for: .rightAnkle)?.y
        else {
            return nil
        }
        return (leftAnkle + rightAnkle) / 2
    }

    private func legKneeAngles(from frame: PoseFrame) -> (left: Double?, right: Double?) {
        (
            left: kneeAngle(hip: .leftHip, knee: .leftKnee, ankle: .leftAnkle, frame: frame),
            right: kneeAngle(hip: .rightHip, knee: .rightKnee, ankle: .rightAnkle, frame: frame)
        )
    }

    private func kneeAngle(
        hip: BodyJoint,
        knee: BodyJoint,
        ankle: BodyJoint,
        frame: PoseFrame
    ) -> Double? {
        guard
            let hipPoint = frame.point(for: hip),
            let kneePoint = frame.point(for: knee),
            let anklePoint = frame.point(for: ankle)
        else {
            return nil
        }

        let upper = vector(from: kneePoint, to: hipPoint)
        let lower = vector(from: kneePoint, to: anklePoint)

        let dot = upper.x * lower.x + upper.y * lower.y
        let magnitude = (upper.x * upper.x + upper.y * upper.y).squareRoot() *
            (lower.x * lower.x + lower.y * lower.y).squareRoot()

        guard magnitude > 0 else { return nil }

        let cosine = max(-1, min(1, dot / magnitude))
        return acos(cosine) * 180 / .pi
    }

    private func vector(from p1: PosePoint, to p2: PosePoint) -> (x: Double, y: Double) {
        (x: p2.x - p1.x, y: p2.y - p1.y)
    }
}

private extension RepetitionAnalyzer {
    enum BodySide {
        case left
        case right
    }

    struct BilateralProfile {
        let downThreshold: Double
        let upThreshold: Double
        let idealDepthRange: ClosedRange<Double>
        let goodDepthRange: ClosedRange<Double>
        let bottomFeedback: String
        let standFeedback: String
        let descendFeedback: String
        let tooDeepFeedback: String
        let strongFeedback: String

        func feedback(for kneeAngle: Double) -> String {
            if kneeAngle > (upThreshold - 8) {
                return standFeedback
            }
            if kneeAngle > downThreshold {
                return descendFeedback
            }
            if kneeAngle < idealDepthRange.lowerBound - 12 {
                return tooDeepFeedback
            }
            return strongFeedback
        }

        func qualityScore(for minAngle: Double) -> Double {
            if idealDepthRange.contains(minAngle) {
                return 95
            }
            if goodDepthRange.contains(minAngle) {
                return 82
            }
            if minAngle < goodDepthRange.lowerBound {
                return 74
            }
            return 58
        }
    }
}

private extension RepetitionAnalyzer.BilateralProfile {
    static let squat = Self(
        downThreshold: 104,
        upThreshold: 160,
        idealDepthRange: 78...102,
        goodDepthRange: 68...116,
        bottomFeedback: "Great depth. Drive up with control.",
        standFeedback: "Start lowering with control.",
        descendFeedback: "Go slightly deeper.",
        tooDeepFeedback: "Too deep. Slow down and stabilize.",
        strongFeedback: "Excellent squat depth."
    )

    static let sitToStand = Self(
        downThreshold: 114,
        upThreshold: 164,
        idealDepthRange: 88...116,
        goodDepthRange: 78...126,
        bottomFeedback: "Good chair depth. Stand up smoothly.",
        standFeedback: "Hinge hips back and sit with control.",
        descendFeedback: "Lower a little further.",
        tooDeepFeedback: "Depth is too low for sit-to-stand. Keep it controlled.",
        strongFeedback: "Nice sit-to-stand pattern."
    )

    static let miniSquat = Self(
        downThreshold: 126,
        upThreshold: 166,
        idealDepthRange: 112...130,
        goodDepthRange: 104...138,
        bottomFeedback: "Great mini-squat range. Rise with control.",
        standFeedback: "Begin a small controlled bend.",
        descendFeedback: "Slightly lower.",
        tooDeepFeedback: "Too deep for mini squat. Keep range smaller.",
        strongFeedback: "Excellent controlled range."
    )
}

private extension Array where Element == Double {
    var average: Double {
        guard !isEmpty else { return 0 }
        return reduce(0, +) / Double(count)
    }

    var averageOrNil: Double? {
        guard !isEmpty else { return nil }
        return average
    }
}
