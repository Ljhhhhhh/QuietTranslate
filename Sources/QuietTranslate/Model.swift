import SwiftUI

struct TranslationResult: Identifiable {
    let configuration: EngineConfiguration
    var id: String { configuration.id }
    var hasRequested = false
    var output = ""
    var phase = TranslationModel.Phase.idle
}

@MainActor
final class TranslationModel: ObservableObject {
    enum Phase { case idle, loading, done, failed(String) }
    @Published var source = "" { didSet { if source != oldValue { speech.stop() } } }
    @Published var direction = Direction.auto { didSet { if direction != oldValue { speech.stop() } } }
    let speech = SpeechPlayer()
    @Published var isPinned = false
    @Published var results: [TranslationResult] = []
    @Published private(set) var selectedEngineID: String?
    @Published var configurationError: String?

    var selectedResult: TranslationResult? { results.first { $0.id == selectedEngineID } }

    private var tasks: [String: Task<Void, Never>] = [:]
    private var requestIDs: [String: UUID] = [:]

    private var translatedSource = ""
    private var translatedDirection = Direction.auto
    private var settingsChanged: Bool {
        (try? Settings.loadEngines().popupEngines) != results.map(\.configuration)
    }

    init() { reset() }

    func translate() {
        reset()
        translatedSource = source
        translatedDirection = direction
        if !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           source.count <= Settings.maxInput, let first = results.first { start(first.configuration) }
    }

    func selectEngine(_ engine: String) {
        guard results.contains(where: { $0.id == engine }) else { return }
        if selectedEngineID != engine { speech.stop() }
        if source != translatedSource || direction != translatedDirection || settingsChanged {
            translate()
        }
        guard let result = results.first(where: { $0.id == engine }) else { return }
        selectedEngineID = engine
        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              source.count <= Settings.maxInput, !result.hasRequested else { return }
        start(result.configuration)
    }

    func retry(_ engine: String) {
        speech.stop()
        if source != translatedSource || direction != translatedDirection || settingsChanged {
            translate()
            selectEngine(engine)
            return
        }
        guard let index = results.firstIndex(where: { $0.id == engine }) else { return }
        let configuration = results[index].configuration
        cancel(engine)
        results[index] = TranslationResult(configuration: configuration)
        start(configuration)
    }

    private func start(_ engine: EngineConfiguration) {
        let text = source, direction = direction, id = UUID()
        requestIDs[engine.id] = id
        guard let index = results.firstIndex(where: { $0.id == engine.id }) else { return }
        results[index].phase = .loading
        results[index].hasRequested = true
        tasks[engine.id] = Task {
            do {
                try Task.checkCancellation()
                for try await chunk in Translator.stream(text, direction: direction, engine: engine) {
                    guard requestIDs[engine.id] == id,
                          let i = results.firstIndex(where: { $0.id == engine.id }) else { return }
                    results[i].output += chunk
                }
                guard requestIDs[engine.id] == id,
                      let i = results.firstIndex(where: { $0.id == engine.id }) else { return }
                results[i].phase = .done
            } catch is CancellationError {
            } catch {
                guard requestIDs[engine.id] == id,
                      let i = results.firstIndex(where: { $0.id == engine.id }) else { return }
                results[i].phase = .failed(error.localizedDescription)
            }
        }
    }

    func cancel(_ engine: String) {
        requestIDs[engine] = nil
        tasks.removeValue(forKey: engine)?.cancel()
        if let i = results.firstIndex(where: { $0.id == engine }), case .loading = results[i].phase {
            results[i].phase = .idle
        }
    }

    func cancel() {
        speech.stop()
        for engine in Array(tasks.keys) { cancel(engine) }
    }
    func reset() {
        cancel()
        do {
            results = try Settings.loadEngines().popupEngines.map { TranslationResult(configuration: $0) }
            selectedEngineID = results.first?.id
            configurationError = results.isEmpty ? "请先在设置中添加翻译引擎，填写服务地址和模型并保存。" : nil
        } catch {
            results = []
            selectedEngineID = nil
            configurationError = error.localizedDescription
        }
    }
    func fail(_ message: String) {
        reset()
        for i in results.indices { results[i].phase = .failed(message) }
    }
    func copy(_ engine: String) {
        guard let result = results.first(where: { $0.id == engine }), !result.output.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(result.output, forType: .string)
    }
}
