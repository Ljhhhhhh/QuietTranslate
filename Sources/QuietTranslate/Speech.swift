import AVFoundation
import NaturalLanguage
import Combine

@MainActor
final class SpeechPlayer: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    enum Target { case source, translation }
    @Published private(set) var target: Target?
    @Published private(set) var error: String?
    private static weak var active: SpeechPlayer?
    private let synthesizer = AVSpeechSynthesizer()
    private var utterance: AVSpeechUtterance?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    static func language(for text: String, fallback: String = "en-US") -> String {
        NLLanguageRecognizer.dominantLanguage(for: text)?.rawValue ?? fallback
    }

    func toggle(text: String, target: Target, language: String? = nil) {
        let wasPlaying = self.target == target
        stop()
        guard !wasPlaying else { return }
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        Self.active?.stop()
        let language = language ?? Self.language(for: text)
        guard let voice = AVSpeechSynthesisVoice(language: language) else {
            error = "没有可用的朗读语音（\(language)）。请在系统设置的辅助功能中下载对应语言的语音。"
            return
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        self.utterance = utterance
        self.target = target
        Self.active = self
        synthesizer.speak(utterance)
    }

    func stop() {
        utterance = nil
        target = nil
        error = nil
        synthesizer.stopSpeaking(at: .immediate)
        if Self.active === self { Self.active = nil }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            // 旧朗读的迟到回调不能清除新朗读的状态。
            if self.utterance === utterance { self.stop() }
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            if self.utterance === utterance { self.stop() }
        }
    }
}
