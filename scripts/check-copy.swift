// swiftc -parse-as-library Sources/QuietTranslate/{Settings,Translator,Speech,Phonetics,Model}.swift scripts/check-copy.swift -o /tmp/quiettranslate-copy-check
import AppKit

@main struct CopyChecks {
    @MainActor static func main() {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let model = TranslationModel()
        let first = EngineConfiguration(id: "first", name: "First", baseURL: "http://localhost", model: "test")
        let second = EngineConfiguration(id: "second", name: "Second", baseURL: "http://localhost", model: "test")
        model.results = [TranslationResult(configuration: first), TranslationResult(configuration: second)]
        pasteboard.setString("existing clipboard", forType: .string)
        let initialCount = pasteboard.changeCount
        assert(!model.copy("missing", to: pasteboard))
        assert(!model.copy(first.id, to: pasteboard))
        model.results[0].output = " \n\t "
        assert(!model.copy(first.id, to: pasteboard))
        assert(pasteboard.changeCount == initialCount, "Unavailable results must preserve the clipboard")

        let translation = "  第一段\n\nSecond paragraph\n    code()\n"
        model.results[0].output = translation
        for phase in [TranslationModel.Phase.loading, .idle, .failed("stream interrupted"), .done] {
            model.results[0].phase = phase
            assert(model.copy(first.id, to: pasteboard))
            assert(pasteboard.string(forType: .string) == translation, "Copy must retain exact formatting and exclude errors")
        }
        model.results[1].output = "Other engine"
        assert(model.copy(second.id, to: pasteboard))
        assert(pasteboard.string(forType: .string) == "Other engine")
        model.results = []
        let copiedCount = pasteboard.changeCount
        assert(!model.copy(second.id, to: pasteboard))
        assert(pasteboard.changeCount == copiedCount)
        print("Copy checks passed: empty results preserve clipboard, exact text, partial output, engine selection, cleared results. System clipboard untouched.")
    }
}
