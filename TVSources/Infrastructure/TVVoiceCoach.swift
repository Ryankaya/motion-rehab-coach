import AVFoundation
import Foundation

final class TVVoiceCoach {
    var isEnabled = true

    private let synthesizer = AVSpeechSynthesizer()
    private var lastPhrase = ""
    private var lastSpokenAt = Date.distantPast
    private let minimumInterval: TimeInterval = 2.0

    func speak(_ phrase: String, force: Bool = false) {
        guard isEnabled else { return }

        let cleanedPhrase = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedPhrase.isEmpty else { return }

        let now = Date()
        if !force {
            if cleanedPhrase == lastPhrase, now.timeIntervalSince(lastSpokenAt) < 6 {
                return
            }
            guard now.timeIntervalSince(lastSpokenAt) >= minimumInterval else { return }
        }

        lastPhrase = cleanedPhrase
        lastSpokenAt = now

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let utterance = AVSpeechUtterance(string: cleanedPhrase)
            utterance.voice = AVSpeechSynthesisVoice(language: Locale.current.identifier)
                ?? AVSpeechSynthesisVoice(language: "en-US")
            utterance.rate = 0.5

            if force, self.synthesizer.isSpeaking {
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
}
