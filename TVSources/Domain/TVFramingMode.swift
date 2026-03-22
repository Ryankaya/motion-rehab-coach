import Foundation

enum TVFramingMode: String, CaseIterable, Identifiable {
    case fullBody
    case feetToHalfBody
    case kneeFocus
    case heelFocus

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fullBody:
            return "Full Body"
        case .feetToHalfBody:
            return "Feet to Half Body"
        case .kneeFocus:
            return "Knee Focus"
        case .heelFocus:
            return "Heel Focus"
        }
    }

    var subtitle: String {
        switch self {
        case .fullBody:
            return "Head to feet visible."
        case .feetToHalfBody:
            return "Best for most lower-body rehab."
        case .kneeFocus:
            return "Extra detail for knee tracking."
        case .heelFocus:
            return "Maximize heel and ankle visibility."
        }
    }
}
