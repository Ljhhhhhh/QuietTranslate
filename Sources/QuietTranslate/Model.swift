import SwiftUI

/// 单个翻译窗口的状态；requestID 保证旧请求的迟到结果不会覆盖新内容。
@MainActor
final class TranslationModel: ObservableObject {
    enum Phase { case idle, loading, done, failed(String) }
    @Published var source = ""
    @Published var output = ""
    @Published var phase = Phase.idle
    @Published var direction = Direction.auto

    private var requestID = 0
    private var task: Task<Void, Never>?

    func translate() {
        cancel()
        let text = source
        requestID += 1
        let id = requestID
        output = ""
        phase = .loading
        task = Task {
            do {
                for try await chunk in Translator.stream(text, direction: direction) {
                    guard id == requestID else { return }
                    output += chunk
                }
                guard id == requestID else { return }
                phase = .done
            } catch is CancellationError {
            } catch {
                guard id == requestID else { return }
                phase = .failed(error.localizedDescription)
            }
        }
    }

    /// 取消在途请求并使其结果失效。
    func cancel() {
        requestID += 1
        task?.cancel()
        task = nil
        if case .loading = phase { phase = .idle }
    }

    func fail(_ msg: String) { cancel(); output = ""; phase = .failed(msg) }

    func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(output, forType: .string)
    }
}
