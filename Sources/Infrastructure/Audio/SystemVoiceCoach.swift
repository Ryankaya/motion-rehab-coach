import AVFoundation
import Foundation

final class SystemVoiceCoach: VoiceCoaching {
    var isEnabled = true

    private let synthesizer = AVSpeechSynthesizer()
    private let audioSession = AVAudioSession.sharedInstance()
    private var lastPhrase = ""
    private var lastSpokenAt = Date.distantPast
    private var isAudioSessionConfigured = false

    private let minimumNormalInterval: TimeInterval = 3
    private let minimumDuplicateInterval: TimeInterval = 8
    private let minimumHighPriorityInterval: TimeInterval = 1

    func announce(_ phrase: String, priority: VoicePriority = .normal) {
        guard isEnabled else { return }

        let cleanedPhrase = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedPhrase.isEmpty else { return }

        let now = Date()
        if cleanedPhrase == lastPhrase, now.timeIntervalSince(lastSpokenAt) < minimumDuplicateInterval {
            return
        }

        switch priority {
        case .high:
            guard now.timeIntervalSince(lastSpokenAt) >= minimumHighPriorityInterval else { return }
        case .normal:
            guard now.timeIntervalSince(lastSpokenAt) >= minimumNormalInterval else { return }
        }

        lastPhrase = cleanedPhrase
        lastSpokenAt = now

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.configureAudioSessionIfNeeded()

            let utterance = AVSpeechUtterance(string: cleanedPhrase)
            utterance.voice = AVSpeechSynthesisVoice(language: Locale.current.identifier)
                ?? AVSpeechSynthesisVoice(language: "en-US")
            utterance.rate = 0.5

            if priority == .high, self.synthesizer.isSpeaking {
                self.synthesizer.stopSpeaking(at: .word)
            }

            self.synthesizer.speak(utterance)
        }
    }

    func reset() {
        lastPhrase = ""
        lastSpokenAt = .distantPast

        DispatchQueue.main.async { [weak self] in
            self?.synthesizer.stopSpeaking(at: .immediate)
        }
    }

    private func configureAudioSessionIfNeeded() {
        guard !isAudioSessionConfigured else { return }
        do {
            try audioSession.setCategory(
                .playback,
                mode: .spokenAudio,
                options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers]
            )
            try audioSession.setActive(true, options: [])
            isAudioSessionConfigured = true
        } catch {
            // Keep coaching available without failing session flow if audio session setup fails.
        }
    }
}
