import Foundation

enum BodyJoint: String, CaseIterable, Codable {
    case leftHip
    case rightHip
    case leftKnee
    case rightKnee
    case leftAnkle
    case rightAnkle
}

struct PoseFrame: Codable, Hashable {
    let timestamp: Date
    let joints: [String: PosePoint]

    func point(for joint: BodyJoint) -> PosePoint? {
        joints[joint.rawValue]
    }
}
