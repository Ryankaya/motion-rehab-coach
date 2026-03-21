import Foundation
import Vision

struct VisionPoseEstimator: PoseEstimating {
    private let minimumConfidence: Float = 0.2

    func estimatePose(in pixelBuffer: CVPixelBuffer) throws -> PoseFrame? {
        // Camera pipelines can produce different buffer orientations depending on device and session.
        // Keep the detector robust by trying a compact orientation set and choosing the richest result.
        let orientations: [CGImagePropertyOrientation] = [
            .up, .upMirrored, .leftMirrored, .right, .left, .rightMirrored
        ]
        var best: CandidatePose?

        for orientation in orientations {
            let request = VNDetectHumanBodyPoseRequest()
            let handler = VNImageRequestHandler(
                cvPixelBuffer: pixelBuffer,
                orientation: orientation,
                options: [:]
            )
            try handler.perform([request])

            guard let observation = request.results?.first else {
                continue
            }

            var joints: [String: PosePoint] = [:]
            var confidenceSum: Double = 0

            for joint in BodyJoint.allCases {
                let recognized = try observation.recognizedPoint(joint.visionName)
                guard recognized.confidence >= minimumConfidence else { continue }

                let confidence = Double(recognized.confidence)
                joints[joint.rawValue] = PosePoint(
                    x: Double(recognized.location.x),
                    y: Double(recognized.location.y),
                    confidence: confidence
                )
                confidenceSum += confidence
            }

            guard !joints.isEmpty else { continue }

            let candidate = CandidatePose(joints: joints, confidenceSum: confidenceSum)
            if let currentBest = best {
                if candidate.isBetter(than: currentBest) {
                    best = candidate
                }
            } else {
                best = candidate
            }
        }

        guard let best else { return nil }
        return PoseFrame(timestamp: Date(), joints: best.joints)
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

private struct CandidatePose {
    let joints: [String: PosePoint]
    let confidenceSum: Double

    func isBetter(than other: CandidatePose) -> Bool {
        if joints.count != other.joints.count {
            return joints.count > other.joints.count
        }
        return confidenceSum > other.confidenceSum
    }
}
