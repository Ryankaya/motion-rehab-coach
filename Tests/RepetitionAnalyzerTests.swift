import XCTest
@testable import motion_rehab_coach

final class RepetitionAnalyzerTests: XCTestCase {
    func testCountsRepForCompleteDepthCycle() {
        let analyzer = RepetitionAnalyzer()

        let sequence: [Double] = [170, 155, 125, 98, 88, 105, 138, 165, 170]

        var latest: RepetitionSnapshot?
        for angle in sequence {
            latest = analyzer.process(frame(withKneeAngle: angle))
        }

        XCTAssertEqual(latest?.repetitionCount, 1)
        XCTAssertGreaterThanOrEqual(latest?.qualityScore ?? 0, 80)
    }

    func testDoesNotCountShallowMovementAsRep() {
        let analyzer = RepetitionAnalyzer()

        let sequence: [Double] = [170, 155, 140, 132, 145, 165]

        var latest: RepetitionSnapshot?
        for angle in sequence {
            latest = analyzer.process(frame(withKneeAngle: angle))
        }

        XCTAssertEqual(latest?.repetitionCount, 0)
    }

    private func frame(withKneeAngle angle: Double) -> PoseFrame {
        let radians = angle * .pi / 180

        let leftHip = PosePoint(x: 0.40, y: 0.80, confidence: 1)
        let leftKnee = PosePoint(x: 0.40, y: 0.55, confidence: 1)
        let leftAnkle = PosePoint(
            x: 0.40 + (sin(radians) * 0.20),
            y: 0.55 + (cos(radians) * 0.20),
            confidence: 1
        )

        let rightHip = PosePoint(x: 0.60, y: 0.80, confidence: 1)
        let rightKnee = PosePoint(x: 0.60, y: 0.55, confidence: 1)
        let rightAnkle = PosePoint(
            x: 0.60 + (sin(radians) * 0.20),
            y: 0.55 + (cos(radians) * 0.20),
            confidence: 1
        )

        return PoseFrame(
            timestamp: Date(),
            joints: [
                BodyJoint.leftHip.rawValue: leftHip,
                BodyJoint.leftKnee.rawValue: leftKnee,
                BodyJoint.leftAnkle.rawValue: leftAnkle,
                BodyJoint.rightHip.rawValue: rightHip,
                BodyJoint.rightKnee.rawValue: rightKnee,
                BodyJoint.rightAnkle.rawValue: rightAnkle
            ]
        )
    }
}
