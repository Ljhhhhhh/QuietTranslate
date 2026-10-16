// Run in an isolated executable: swiftc -parse-as-library Sources/QuietTranslate/{Settings,Speech,Phonetics,Model}.swift scripts/check-engines.swift -o /tmp/quiettranslate-engine-check
import Foundation
import SwiftUI

// No network or Keychain access: drive request lifetime with controlled streams.
enum Translator {
    @MainActor static var calls: [(String, String)] = []
    @MainActor static var continuations: [AsyncThrowingStream<String, Error>.Continuation] = []
    @MainActor static func stream(_ text: String, direction: Direction, engine: EngineConfiguration) -> AsyncThrowingStream<String, Error> {
        calls.append((engine.id, text))
        return AsyncThrowingStream { continuations.append($0) }
    }
}

@MainActor enum MockPhonetics {
    static var continuations: [CheckedContinuation<Phonetics, Error>] = []
    static func lookup(_ text: String) async throws -> Phonetics {
        try await withCheckedThrowingContinuation { continuations.append($0) }
    }
}

@main struct EngineChecks {
    @MainActor static func settle() async {
        for _ in 0..<30 { await Task.yield() }
    }

    @MainActor static func main() async throws {
        let defaults = UserDefaults.standard
        let domain = ProcessInfo.processInfo.processName
        defaults.removePersistentDomain(forName: domain)
        defer { defaults.removePersistentDomain(forName: domain) }
        let fresh = try Settings.loadEngines()
        assert(fresh.engines.isEmpty && fresh.preferredID.isEmpty)
        let unconfigured = TranslationModel(phoneticLookup: MockPhonetics.lookup)
        unconfigured.source = "hello"
        unconfigured.translate()
        await settle()
        assert(unconfigured.results.isEmpty && unconfigured.configurationError != nil)
        assert(Translator.calls.isEmpty)
        do { try fresh.validate(); assertionFailure("Empty settings accepted") } catch {}
        defaults.set("legacy-model", forKey: "model")
        let incomplete = try Settings.loadEngines()
        assert(incomplete.engines.isEmpty)
        defaults.set("http://localhost:9998/v1", forKey: "baseURL")
        defaults.set("http://localhost:9997/v1", forKey: "cpaBaseURL")
        defaults.set("legacy-cpa", forKey: "cpaModel")
        defaults.set(true, forKey: "cpaEnabled")
        let migrated = try Settings.loadEngines()
        assert(migrated.preferredID == "local")
        assert(migrated.engines.count == 2)
        assert(migrated.engines[0].model == "legacy-model")
        assert(migrated.engines[1].showInPopup)

        let third = EngineConfiguration(id: "custom", name: "Custom", baseURL: "http://localhost:9999/v1", model: "test", showInPopup: false)
        var preferences = EnginePreferences(engines: migrated.engines + [third], preferredID: "cpa")
        assert(preferences.popupEngines.map(\.id) == ["cpa", "local"])
        preferences.preferredID = "custom"
        assert(preferences.popupEngines.first?.id == "custom")
        try preferences.validate()
        var invalid = preferences
        invalid.engines[0].baseURL = "file:///private/tmp"
        do { try invalid.validate(); assertionFailure("Invalid URL accepted") } catch {}
        invalid = preferences
        invalid.preferredID = "missing"
        do { try invalid.validate(); assertionFailure("Missing preference accepted") } catch {}
        invalid = preferences
        invalid.engines.append(third)
        do { try invalid.validate(); assertionFailure("Duplicate ID accepted") } catch {}
        invalid = preferences
        invalid.engines[0].model = " "
        do { try invalid.validate(); assertionFailure("Empty model accepted") } catch {}

        defaults.set(try JSONEncoder().encode(preferences), forKey: "enginePreferences")
        let restored = try Settings.loadEngines()
        assert(restored == preferences)
        let model = TranslationModel(phoneticLookup: MockPhonetics.lookup)
        model.source = "first"
        model.translate()
        await settle()
        assert(Translator.calls.map { $0.0 } == ["custom"])
        assert(model.selectedEngineID == "custom")
        model.selectEngine("local")
        await settle()
        assert(Translator.calls.map { $0.0 } == ["custom", "local"])
        Translator.continuations[1].yield("alternate")
        await settle()
        model.selectEngine("custom")
        model.selectEngine("local")
        model.selectEngine("local")
        await settle()
        assert(Translator.calls.count == 2)
        assert(model.selectedResult?.output == "alternate")
        model.cancel("local")
        model.retry("local")
        await settle()
        assert(model.selectedEngineID == "local")
        assert(Translator.calls.count == 3)
        let old = Translator.continuations
        model.source = "second"
        model.translate()
        await settle()
        old.forEach { $0.yield("stale"); $0.finish() }
        Translator.continuations.last?.yield("fresh")
        await settle()
        assert(model.results.first?.output == "fresh")
        assert(model.selectedEngineID == "custom")
        assert(model.results.dropFirst().allSatisfy { $0.output.isEmpty })
        model.cancel()
        Translator.continuations.last?.yield("after-close")
        await settle()
        assert(model.results.first?.output == "fresh")
        model.source = "third"
        model.selectEngine("local")
        await settle()
        assert(model.selectedEngineID == "local")
        assert(model.results.allSatisfy { $0.output.isEmpty })
        assert(Translator.calls.suffix(2).allSatisfy { $0.1 == "third" })
        model.cancel()
        let callsBeforeEmpty = Translator.calls.count
        model.source = " "
        model.selectEngine("custom")
        await settle()
        assert(Translator.calls.count == callsBeforeEmpty)
        assert(model.selectedResult?.output.isEmpty == true)
        let pendingPhonetics = MockPhonetics.continuations
        for pending in pendingPhonetics {
            pending.resume(returning: Phonetics(us: "test"))
        }
        await settle()
        assert(model.phonetics == nil)
        model.source = "hello"
        model.translate()
        await settle()
        MockPhonetics.continuations.last?.resume(returning: Phonetics(us: "həˈloʊ"))
        await settle()
        assert(model.phonetics?.us == "həˈloʊ")
        let lookups = MockPhonetics.continuations.count
        model.selectEngine("local")
        await settle()
        assert(MockPhonetics.continuations.count == lookups)
        assert(model.phonetics?.us == "həˈloʊ")
        model.source = "changed"
        assert(model.phonetics == nil)
        model.cancel()
        defaults.set(Data("broken".utf8), forKey: "enginePreferences")
        model.reset()
        assert(model.configurationError != nil && model.results.isEmpty)
        print("Engine checks passed: migration, persistence, selection, validation, lazy requests, cancellation, stale responses, corrupt settings.")
    }
}
