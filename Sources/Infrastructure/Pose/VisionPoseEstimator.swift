import Foundation
import Vision

struct VisionPoseEstimator: PoseEstimating {
    private let minimumConfidence: Float = 0.25

    func estimatePose(in pixelBuffer: CVPixelBuffer) throws -> PoseFrame? {
        let request = VNDetectHumanBodyPoseRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .leftMirrored, options: [:])

        try handler.perform([request])

        guard let observation = request.results?.first else {
            return nil
        }

        var joints: [String: PosePoint] = [:]

        for joint in BodyJoint.allCases {
            let recognized = try observation.recognizedPoint(joint.visionName)
            guard recognized.confidence >= minimumConfidence else { continue }

            joints[joint.rawValue] = PosePoint(
                x: Double(recognized.location.x),
                y: Double(recognized.location.y),
                confidence: Double(recognized.confidence)
            )
        }

        return PoseFrame(timestamp: Date(), joints: joints)
    }
}

private extension BodyJoint {
    var visionName: VNHumanBodyPoseObservation.JointName {
        switch self {
        case .leftHip: return .leftHip
        case .rightHip: return .rightHip
        case .leftKnee: return .leftKnee
        case .rightKnee: return .rightKnee
        case .leftAnkle: return .leftAnkle
        case .rightAnkle: return .rightAnkle
        }
    }
}
