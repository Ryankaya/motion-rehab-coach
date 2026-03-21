import Foundation

enum ExerciseType: String, Codable, CaseIterable, Identifiable {
    case squat
    case sitToStand
    case lunge
    case miniSquat
    case calfRaise

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .squat:
            return "Bodyweight Squat"
        case .sitToStand:
            return "Sit to Stand"
        case .lunge:
            return "Forward Lunge"
        case .miniSquat:
            return "Mini Squat"
        case .calfRaise:
            return "Calf Raise"
        }
    }

    var subtitle: String {
        switch self {
        case .squat:
            return "Build lower-body control and depth."
        case .sitToStand:
            return "Train safe chair transfers and leg strength."
        case .lunge:
            return "Improve unilateral stability and knee tracking."
        case .miniSquat:
            return "Low-impact range for early-stage rehab."
        case .calfRaise:
            return "Strengthen calves and ankle control."
        }
    }

    var systemImage: String {
        switch self {
        case .squat:
            return "figure.strengthtraining.traditional"
        case .sitToStand:
            return "chair.fill"
        case .lunge:
            return "figure.walk.motion"
        case .miniSquat:
            return "figure.cooldown"
        case .calfRaise:
            return "figure.stand"
        }
    }

    var primaryMetricTitle: String {
        switch self {
        case .calfRaise:
            return "Ankle Lift"
        case .squat, .sitToStand, .lunge, .miniSquat:
            return "Knee Angle"
        }
    }

    var primaryMetricUnit: String {
        switch self {
        case .calfRaise:
            return "%"
        case .squat, .sitToStand, .lunge, .miniSquat:
            return "°"
        }
    }

    var sessionStartCue: String {
        switch self {
        case .squat:
            return "Squat session started. Lower with control and stand tall."
        case .sitToStand:
            return "Sit-to-stand session started. Sit back and stand with balance."
        case .lunge:
            return "Lunge session started. Keep your torso upright and step with control."
        case .miniSquat:
            return "Mini squat session started. Keep movement small, smooth, and steady."
        case .calfRaise:
            return "Calf raise session started. Rise onto your toes and lower slowly."
        }
    }
}
