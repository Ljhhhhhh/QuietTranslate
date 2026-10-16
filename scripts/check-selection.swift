// swiftc -parse-as-library Sources/QuietTranslate/Selection.swift scripts/check-selection.swift -o /tmp/quiettranslate-selection-check
import AppKit

@main struct SelectionChecks {
    @MainActor static func main() async throws {
        assert(Selection.isCopyMenuItem(identifier: "copy:", title: nil, command: nil, modifiers: nil))
        assert(Selection.isCopyMenuItem(identifier: nil, title: "复制", command: "C", modifiers: 0))
        assert(Selection.isCopyMenuItem(identifier: nil, title: "Copy", command: "c", modifiers: 0))
        assert(!Selection.isCopyMenuItem(identifier: nil, title: "Copy Link", command: "C", modifiers: 0))
        assert(!Selection.isCopyMenuItem(identifier: nil, title: "复制", command: "C", modifiers: 1))

        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let richType = NSPasteboard.PasteboardType("local.quiettranslate.check")
        let original = NSPasteboardItem()
        original.setString("original", forType: .string)
        original.setData(Data([0, 1, 255]), forType: richType)
        board.writeObjects([original])
        let count = board.changeCount
        do {
            _ = try await Selection.copiedText(from: board) { true }
            assertionFailure("Unchanged clipboard must not become selected text")
        } catch {}
        assert(board.changeCount == count)

        let text = try await Selection.copiedText(from: board) {
            board.clearContents()
            return board.setString("selected text", forType: .string)
        }
        assert(text == "selected text")
        assert(board.string(forType: .string) == "original")
        assert(board.data(forType: richType) == Data([0, 1, 255]))

        do {
            _ = try await Selection.copiedText(from: board) {
                board.clearContents()
                return board.setData(Data([42]), forType: richType)
            }
            assertionFailure("Non-text clipboard must fail")
        } catch {}
        assert(board.string(forType: .string) == "original")
        assert(board.data(forType: richType) == Data([0, 1, 255]))

        let pending = Task { @MainActor in
            try await Selection.copiedText(from: board) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
                    board.clearContents()
                    board.setString("late copy", forType: .string)
                }
                return true
            }
        }
        try await Task.sleep(for: .milliseconds(10))
        pending.cancel()
        do {
            _ = try await pending.value
            assertionFailure("Cancelled selection must not return a result")
        } catch is CancellationError {}
        assert(board.string(forType: .string) == "original")
        assert(board.data(forType: richType) == Data([0, 1, 255]))
        print("Selection checks passed (isolated pasteboard; no app interaction)")
    }
}
