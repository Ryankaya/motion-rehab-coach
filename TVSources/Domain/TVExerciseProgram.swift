import Foundation

enum TVExerciseProgram: String, CaseIterable, Identifiable {
    case squat
    case sitToStand
    case lunge
    case miniSquat
    case calfRaise

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .squat:
            return "Squat"
        case .sitToStand:
            return "Sit to Stand"
        case .lunge:
            return "Lunge"
        case .miniSquat:
            return "Mini Squat"
        case .calfRaise:
            return "Calf Raise"
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

    var startCue: String {
        switch self {
        case .squat:
            return "Squat session started. Lower with control and stand tall."
        case .sitToStand:
            return "Sit to stand session started. Reach hips back and keep knees aligned."
        case .lunge:
            return "Lunge session started. Keep chest up and front knee stable."
        case .miniSquat:
            return "Mini squat session started. Keep movement small and controlled."
        case .calfRaise:
            return "Calf raise session started. Rise on toes and lower slowly."
        }
    }

    var calibrationCue: String {
        switch self {
        case .calfRaise:
            return "Hold ankles and knees inside the green zone for calibration."
        default:
            return "Hold hips, knees, and ankles inside the green zone for calibration."
        }
    }

    var liveCueSequence: [String] {
        switch self {
        case .squat:
            return [
                "Keep knees over ankles.",
                "Sit hips back, then drive up through heels.",
                "Stay centered in the lower-body zone."
            ]
        case .sitToStand:
            return [
                "Keep feet planted and chest tall.",
                "Control the descent before standing again.",
                "Stay inside the lower-body guide zone."
            ]
        case .lunge:
            return [
                "Maintain balance and upright torso.",
                "Front knee tracks over mid-foot.",
                "Control step and return smoothly."
            ]
        case .miniSquat:
            return [
                "Keep range shallow and steady.",
                "Avoid knees collapsing inward.",
                "Stay centered in the guide zone."
            ]
        case .calfRaise:
            return [
                "Lift straight up through the ankles.",
                "Pause at top, then lower with control.",
                "Keep heels aligned in the zone."
            ]
        }
    }

    var autoFramingMode: TVFramingMode {
        let normalized = displayName.lowercased()
        if normalized.contains("shoulder") || normalized.contains("upper") || normalized.contains("arm") {
            return .upperBody
        }

        switch self {
        case .calfRaise:
            return .heelFocus
        case .lunge:
            return .kneeFocus
        case .squat, .sitToStand, .miniSquat:
            return .feetToHalfBody
        }
    }
}
