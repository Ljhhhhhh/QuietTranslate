import AppKit
import ApplicationServices

enum SelectionError: LocalizedError {
    case noPermission, unsupported, empty, clipboardUnavailable
    var errorDescription: String? {
        switch self {
        case .noPermission: "需要“辅助功能”权限才能读取选中文字。授权后重试。"
        case .unsupported: "当前应用不支持读取选区。可用输入翻译，自行粘贴文字。"
        case .empty: "没有选中文字"
        case .clipboardUnavailable: "暂时无法保护剪贴板内容，请重试或使用输入翻译。"
        }
    }
}

/// 优先读取 Accessibility 选区，失败时尝试菜单栏复制，不模拟按键。
@MainActor
enum Selection {
    static func requestPermission() {
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    /// 返回选中文字与选区矩形（屏幕坐标，左下原点）；取不到矩形时为 nil。
    static func read() async throws -> (String, NSRect?) {
        guard AXIsProcessTrusted() else { requestPermission(); throw SelectionError.noPermission }
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { throw SelectionError.unsupported }
        do { return try readAccessibility() }
        catch {
            let element = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(element, 0.2)
            guard let menu = attribute(element, kAXMenuBarAttribute) else { throw error }
            guard let copy = copyMenuItem(in: menu as! AXUIElement) else { throw error }
            var interrupted = false
            guard let monitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown], handler: { _ in
                interrupted = true
            }) else { throw SelectionError.unsupported }
            defer { NSEvent.removeMonitor(monitor) }
            let text = try await copiedText(from: .general, isSourceActive: {
                !interrupted && NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier
            }) {
                AXUIElementPerformAction(copy, kAXPressAction as CFString) == .success
            }
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier else { throw CancellationError() }
            return (text, nil)
        }
    }

    private static func readAccessibility() throws -> (String, NSRect?) {
        let sys = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(sys, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let el = focused else { throw SelectionError.unsupported }
        let elem = el as! AXUIElement
        var txt: CFTypeRef?
        guard AXUIElementCopyAttributeValue(elem, kAXSelectedTextAttribute as CFString, &txt) == .success,
              let s = txt as? String else { throw SelectionError.unsupported }
        guard !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw SelectionError.empty }
        return (s, bounds(of: elem))
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    static func isCopyMenuItem(identifier: String?, title: String?, command: String?, modifiers: Int?) -> Bool {
        identifier == "copy:" ||
            (["Copy", "复制", "拷贝", "複製", "拷貝"].contains(title ?? "") && command?.lowercased() == "c" && modifiers == 0)
    }

    private static func copyMenuItem(in menu: AXUIElement) -> AXUIElement? {
        var pending = [(menu, 0)]
        var index = 0
        while index < pending.count && index < 256 {
            let (element, depth) = pending[index]
            index += 1
            if attribute(element, kAXRoleAttribute) as? String == kAXMenuItemRole,
               attribute(element, kAXEnabledAttribute) as? Bool == true,
               isCopyMenuItem(identifier: attribute(element, kAXIdentifierAttribute) as? String,
                              title: attribute(element, kAXTitleAttribute) as? String,
                              command: attribute(element, kAXMenuItemCmdCharAttribute) as? String,
                              modifiers: attribute(element, kAXMenuItemCmdModifiersAttribute) as? Int) {
                return element
            }
            if depth < 5, let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] {
                pending.append(contentsOf: children.prefix(256 - pending.count).map { ($0, depth + 1) })
            }
        }
        return nil
    }

    // shortcut: 剪贴板不提供写入来源，后台程序并发写入时仍有歧义；需严格隔离时改用应用专用取词接口。
    static func copiedText(from pasteboard: NSPasteboard, isSourceActive: () -> Bool = { true },
                           performCopy: () -> Bool) async throws -> String {
        try Task.checkCancellation()
        let initialCount = pasteboard.changeCount
        let items = pasteboard.pasteboardItems
        guard items != nil || (pasteboard.types ?? []).isEmpty else { throw SelectionError.clipboardUnavailable }
        let savedItems = try (items ?? []).map { item in
            let saved = NSPasteboardItem()
            for type in item.types {
                guard let data = item.data(forType: type), saved.setData(data, forType: type) else {
                    throw SelectionError.clipboardUnavailable
                }
            }
            return saved
        }
        guard pasteboard.changeCount == initialCount else { throw SelectionError.clipboardUnavailable }
        guard isSourceActive() else { throw CancellationError() }
        guard performCopy() else { throw SelectionError.unsupported }

        // 取消后仍短暂等待复制回写，前台和输入未变化时恢复原剪贴板。
        let deadline = ContinuousClock.now.advanced(by: .milliseconds(500))
        while true {
            // 切换应用后不接收或回滚新的剪贴板内容，以免覆盖用户刚完成的复制。
            guard isSourceActive() else { throw CancellationError() }
            let copiedCount = pasteboard.changeCount
            let text = copiedCount != initialCount ? pasteboard.string(forType: .string) : nil
            if copiedCount != initialCount, text != nil || ContinuousClock.now >= deadline {
                guard pasteboard.changeCount == copiedCount else { throw SelectionError.clipboardUnavailable }
                pasteboard.clearContents()
                let restored = savedItems.isEmpty || pasteboard.writeObjects(savedItems)
                guard restored else { throw SelectionError.clipboardUnavailable }
                try Task.checkCancellation()
                guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw SelectionError.empty }
                return text
            }
            if ContinuousClock.now >= deadline { break }
            await withCheckedContinuation { continuation in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) { continuation.resume() }
            }
        }
        try Task.checkCancellation()
        throw SelectionError.unsupported
    }

    private static func bounds(of elem: AXUIElement) -> NSRect? {
        var range: CFTypeRef?
        guard AXUIElementCopyAttributeValue(elem, kAXSelectedTextRangeAttribute as CFString, &range) == .success,
              let range else { return nil }
        var b: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(elem, kAXBoundsForRangeParameterizedAttribute as CFString, range, &b) == .success,
              let b else { return nil }
        var r = CGRect.zero
        guard AXValueGetValue(b as! AXValue, .cgRect, &r), r.width > 0 || r.height > 0 else { return nil }
        // AX 使用以主屏左上为原点的坐标，转换为 AppKit 坐标。
        let h = NSScreen.screens.first?.frame.height ?? 0
        return NSRect(x: r.minX, y: h - r.maxY, width: r.width, height: r.height)
    }
}
