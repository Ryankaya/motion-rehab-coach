import XCTest
@testable import motion_rehab_coach

final class RepetitionAnalyzerTests: XCTestCase {
    func testCountsRepForCompleteDepthCycle() {
        let analyzer = RepetitionAnalyzer(exerciseType: .squat)

        let sequence: [Double] = [170, 155, 125, 98, 88, 105, 138, 165, 170]

        var latest: RepetitionSnapshot?
        for angle in sequence {
            latest = analyzer.process(frame(leftKneeAngle: angle, rightKneeAngle: angle))
        }

        XCTAssertEqual(latest?.repetitionCount, 1)
        XCTAssertGreaterThanOrEqual(latest?.qualityScore ?? 0, 80)
    }

    func testDoesNotCountShallowMovementAsRep() {
        let analyzer = RepetitionAnalyzer(exerciseType: .squat)

        let sequence: [Double] = [170, 155, 140, 132, 145, 165]

        var latest: RepetitionSnapshot?
        for angle in sequence {
            latest = analyzer.process(frame(leftKneeAngle: angle, rightKneeAngle: angle))
        }

        XCTAssertEqual(latest?.repetitionCount, 0)
    }

    func testCountsLungeRepWhenDepthAndReturnAreCompleted() {
        let analyzer = RepetitionAnalyzer(exerciseType: .lunge)

        let sequence: [(Double, Double)] = [
            (170, 170),
            (162, 148),
            (151, 121),
            (146, 98),
            (152, 112),
            (164, 160)
        ]

        var latest: RepetitionSnapshot?
        for (left, right) in sequence {
            latest = analyzer.process(frame(leftKneeAngle: left, rightKneeAngle: right))
        }

        XCTAssertEqual(latest?.repetitionCount, 1)
        XCTAssertGreaterThan(latest?.qualityScore ?? 0, 0)
    }

    func testCountsCalfRaiseRepForLiftAndLowerCycle() {
        let analyzer = RepetitionAnalyzer(exerciseType: .calfRaise)

        let sequence: [Double] = [0.000, 0.004, 0.015, 0.028, 0.018, 0.006]

        var latest: RepetitionSnapshot?
        for rise in sequence {
            latest = analyzer.process(
                frame(
                    leftKneeAngle: 170,
                    rightKneeAngle: 170,
                    leftAnkleYOffset: rise,
                    rightAnkleYOffset: rise
                )
            )
        }

        XCTAssertEqual(latest?.repetitionCount, 1)
        XCTAssertGreaterThan(latest?.qualityScore ?? 0, 0)
    }

    private func frame(
        leftKneeAngle: Double,
        rightKneeAngle: Double,
        leftAnkleYOffset: Double = 0,
        rightAnkleYOffset: Double = 0
    ) -> PoseFrame {
        let leftRadians = leftKneeAngle * .pi / 180
        let rightRadians = rightKneeAngle * .pi / 180

        let leftHip = PosePoint(x: 0.40, y: 0.80, confidence: 1)
        let leftKnee = PosePoint(x: 0.40, y: 0.55, confidence: 1)
        let leftAnkle = PosePoint(
            x: 0.40 + (sin(leftRadians) * 0.20),
            y: (0.55 + (cos(leftRadians) * 0.20)) + leftAnkleYOffset,
            confidence: 1
        )

        let rightHip = PosePoint(x: 0.60, y: 0.80, confidence: 1)
        let rightKnee = PosePoint(x: 0.60, y: 0.55, confidence: 1)
        let rightAnkle = PosePoint(
            x: 0.60 + (sin(rightRadians) * 0.20),
            y: (0.55 + (cos(rightRadians) * 0.20)) + rightAnkleYOffset,
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
