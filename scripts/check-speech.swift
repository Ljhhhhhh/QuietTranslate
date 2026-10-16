// swiftc -parse-as-library Sources/QuietTranslate/Speech.swift scripts/check-speech.swift -o /tmp/quiettranslate-speech-check
import Foundation

@main struct SpeechChecks {
    @MainActor static func main() {
        assert(SpeechPlayer.language(for: "Hello, how are you today?") == "en")
        assert(SpeechPlayer.language(for: "你好，今天的天气非常好。") == "zh-Hans")
        assert(SpeechPlayer.language(for: "123", fallback: "en-US") == "en-US")
        let player = SpeechPlayer()
        player.toggle(text: " \n ", target: .source)
        assert(player.target == nil && player.error == nil)
        player.stop()
        player.stop()
        assert(player.target == nil)
        print("Speech checks passed: language detection, fallback, empty input, idempotent stop. No audio played.")
    }
}
