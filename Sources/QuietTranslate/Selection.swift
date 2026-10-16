import AppKit
import ApplicationServices

enum SelectionError: LocalizedError {
    case noPermission, unsupported, empty
    var errorDescription: String? {
        switch self {
        case .noPermission: "需要“辅助功能”权限才能读取选中文字。授权后重试。"
        case .unsupported: "当前应用不支持读取选区。可用输入翻译，自行粘贴文字。"
        case .empty: "没有选中文字"
        }
    }
}

/// 通过 Accessibility 读取前台应用选区，不碰剪贴板、不模拟按键。
enum Selection {
    static func requestPermission() {
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    /// 返回选中文字与选区矩形（屏幕坐标，左下原点）；取不到矩形时为 nil。
    static func read() throws -> (String, NSRect?) {
        guard AXIsProcessTrusted() else { requestPermission(); throw SelectionError.noPermission }
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
