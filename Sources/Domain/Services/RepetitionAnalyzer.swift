import Foundation

struct RepetitionSnapshot {
    let repetitionCount: Int
    let currentKneeAngle: Double?
    let qualityScore: Double
    let feedback: String
}

final class RepetitionAnalyzer {
    private let lowDepthThreshold: Double = 100
    private let standingThreshold: Double = 160

    private var repetitionCount = 0
    private var reachedDepth = false
    private var currentRepMinAngle = 180.0
    private var repQualityScores: [Double] = []

    func reset() {
        repetitionCount = 0
        reachedDepth = false
        currentRepMinAngle = 180.0
        repQualityScores.removeAll(keepingCapacity: true)
    }

    func process(_ frame: PoseFrame) -> RepetitionSnapshot? {
        guard let kneeAngle = averageKneeAngle(from: frame) else {
            return RepetitionSnapshot(
                repetitionCount: repetitionCount,
                currentKneeAngle: nil,
                qualityScore: qualityScore,
                feedback: "Move into camera frame"
            )
        }

        if kneeAngle < lowDepthThreshold {
            reachedDepth = true
            currentRepMinAngle = min(currentRepMinAngle, kneeAngle)
        }

        if reachedDepth && kneeAngle > standingThreshold {
            repetitionCount += 1
            repQualityScores.append(scoreForRep(minAngle: currentRepMinAngle))
            reachedDepth = false
            currentRepMinAngle = 180.0
        }

        return RepetitionSnapshot(
            repetitionCount: repetitionCount,
            currentKneeAngle: kneeAngle,
            qualityScore: qualityScore,
            feedback: feedback(for: kneeAngle)
        )
    }

    var latestRepetitionCount: Int { repetitionCount }
    var qualityScore: Double { repQualityScores.average }

    private func feedback(for kneeAngle: Double) -> String {
        if kneeAngle > 145 {
            return "Start lowering with control"
        }
        if kneeAngle > 110 {
            return "Go slightly deeper"
        }
        if kneeAngle < 70 {
            return "Too deep, stabilize and slow down"
        }
        return "Great depth and control"
    }

    private func averageKneeAngle(from frame: PoseFrame) -> Double? {
        var angles: [Double] = []

        if let left = kneeAngle(hip: .leftHip, knee: .leftKnee, ankle: .leftAnkle, frame: frame) {
            angles.append(left)
        }

        if let right = kneeAngle(hip: .rightHip, knee: .rightKnee, ankle: .rightAnkle, frame: frame) {
            angles.append(right)
        }

        return angles.average
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

    private func scoreForRep(minAngle: Double) -> Double {
        switch minAngle {
        case ..<95:
            return 95
        case ..<110:
            return 80
        case ..<125:
            return 60
        default:
            return 35
        }
    }
}

private extension Array where Element == Double {
    var average: Double {
        guard !isEmpty else { return 0 }
        return reduce(0, +) / Double(count)
    }
}
