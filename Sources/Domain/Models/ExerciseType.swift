import Foundation

enum ExerciseType: String, Codable, CaseIterable, Identifiable {
    case squat

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .squat:
            return "Bodyweight Squat"
        }
    }
}
