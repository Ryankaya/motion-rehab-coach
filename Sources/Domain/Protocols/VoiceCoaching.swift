import Foundation

protocol VoiceCoaching: AnyObject {
    var isEnabled: Bool { get set }
    func announce(_ phrase: String, priority: VoicePriority)
    func reset()
}

enum VoicePriority {
    case high
    case normal
}
