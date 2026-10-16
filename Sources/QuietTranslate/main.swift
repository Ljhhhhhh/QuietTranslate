import AppKit
import SwiftUI
import Carbon.HIToolbox

/// 浮层：不激活应用，因此不抢原应用键盘焦点。
final class FloatPanel: NSPanel {
    var keyable = false
    override var canBecomeKey: Bool { keyable }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let selModel = TranslationModel()
    let inModel = TranslationModel()
    var selPanel: FloatPanel?
    var inPanel: FloatPanel?
    var settingsWindow: NSWindow?
    var statusItem: NSStatusItem!
    var hotKeys: [HotKey] = []
    var prevApp: NSRunningApplication?
    var outsideMonitor: Any?

    func applicationDidFinishLaunching(_ n: Notification) {
        NSApp.setActivationPolicy(.accessory)
        // 菜单栏应用默认没有主菜单，需要 Edit 菜单才能在输入窗口使用 ⌘C/⌘V/⌘A/⌘Z。
        let main = NSMenu(), editItem = NSMenuItem(), edit = NSMenu(title: "Edit")
        for (t, a, k) in [("撤销", Selector(("undo:")), "z"), ("剪切", #selector(NSText.cut(_:)), "x"),
                          ("拷贝", #selector(NSText.copy(_:)), "c"), ("粘贴", #selector(NSText.paste(_:)), "v"),
                          ("全选", #selector(NSText.selectAll(_:)), "a")] {
            edit.addItem(withTitle: t, action: a, keyEquivalent: k)
        }
        editItem.submenu = edit; main.addItem(editItem); NSApp.mainMenu = main
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "character.bubble", accessibilityDescription: "QuietTranslate")
        let menu = NSMenu()
        for (t, a) in [("划词翻译  ⌃⌥D", #selector(selectionAction)), ("输入翻译  ⌃⌥A", #selector(inputAction)),
                       ("设置…", #selector(openSettings))] {
            menu.addItem(withTitle: t, action: a, keyEquivalent: "").target = self
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu

        let mods = controlKey | optionKey
        let a = HotKey(keyCode: kVK_ANSI_D, modifiers: mods) { [weak self] in self?.selectionAction() }
        let b = HotKey(keyCode: kVK_ANSI_A, modifiers: mods) { [weak self] in self?.inputAction() }
        hotKeys = [a, b].compactMap { $0 }
        if hotKeys.count < 2 { alert("快捷键 ⌃⌥D / ⌃⌥A 注册失败，可能与其他应用冲突；仍可使用菜单栏。") }
    }

    // MARK: 划词
    @objc func selectionAction() {
        if selPanel?.isVisible == true { closeSelection(); return }
        runSelection()
    }

    func runSelection() {
        selModel.cancel(); selModel.output = ""
        do {
            let (text, rect) = try Selection.read()
            selModel.source = text
            showSelection(near: rect)
            selModel.translate()
        } catch {
            selModel.source = ""
            showSelection(near: nil)
            selModel.fail(error.localizedDescription)
        }
    }

    func showSelection(near rect: NSRect?) {
        if selPanel == nil {
            let p = FloatPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.level = .floating; p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = true
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            p.hidesOnDeactivate = false
            let host = NSHostingView(rootView: SelectionView(m: selModel, close: { [weak self] in self?.closeSelection() },
                                                             retry: { [weak self] in self?.retrySelection() }))
            host.sizingOptions = [.intrinsicContentSize]
            p.contentView = host
            selPanel = p
        }
        guard let p = selPanel else { return }
        p.contentView?.layoutSubtreeIfNeeded()
        let size = p.contentView?.fittingSize ?? NSSize(width: 360, height: 160)
        p.setContentSize(size)
        let pt = rect.map { NSPoint(x: $0.minX, y: $0.minY - 8) } ?? NSEvent.mouseLocation
        p.setFrameOrigin(clamp(origin: NSPoint(x: pt.x, y: pt.y - size.height), size: size, anchor: pt))
        p.orderFrontRegardless()
        if let m = outsideMonitor { NSEvent.removeMonitor(m) }
        outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.closeSelection() }
        }
    }

    /// 重试：已有原文则直接重译，否则重新取词。
    func retrySelection() {
        if selModel.source.isEmpty { runSelection() } else { selModel.translate() }
    }

    func closeSelection() {
        selModel.cancel()
        selPanel?.orderOut(nil)
        if let m = outsideMonitor { NSEvent.removeMonitor(m); outsideMonitor = nil }
    }

    /// 将窗口限制在所在屏幕可见区域内；下方放不下则翻到锚点上方。
    func clamp(origin: NSPoint, size: NSSize, anchor: NSPoint) -> NSPoint {
        let screen = NSScreen.screens.first { $0.frame.contains(anchor) } ?? NSScreen.main ?? NSScreen.screens[0]
        let v = screen.visibleFrame
        var o = origin
        if o.y < v.minY { o.y = anchor.y + 28 }
        o.x = min(max(o.x, v.minX + 8), v.maxX - size.width - 8)
        o.y = min(max(o.y, v.minY + 8), v.maxY - size.height - 8)
        return o
    }

    // MARK: 输入
    @objc func inputAction() {
        if inPanel?.isVisible == true { closeInput(); return }
        closeSelection()
        prevApp = NSWorkspace.shared.frontmostApplication
        if inPanel == nil {
            let p = FloatPanel(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
            p.keyable = true
            p.level = .floating; p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = true
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            p.hidesOnDeactivate = false
            let host = NSHostingView(rootView: InputView(m: inModel, close: { [weak self] in self?.closeInput() }))
            host.sizingOptions = [.intrinsicContentSize]
            p.contentView = host
            inPanel = p
        }
        guard let p = inPanel else { return }
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main!
        p.contentView?.layoutSubtreeIfNeeded()
        let size = p.contentView?.fittingSize ?? NSSize(width: 520, height: 320)
        p.setContentSize(size)
        let v = screen.visibleFrame
        p.setFrameOrigin(NSPoint(x: v.midX - size.width / 2, y: v.midY + v.height * 0.1 - size.height / 2))
        NSApp.activate(ignoringOtherApps: true)
        p.makeKeyAndOrderFront(nil)
        // Esc：仅在输入窗口为 key window 时由本应用处理，不会传给原应用。
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            if e.keyCode == UInt16(kVK_Escape), e.window === self?.inPanel, !((e.window?.firstResponder as? NSTextView)?.hasMarkedText() ?? false) {
                self?.closeInput(); return nil
            }
            return e
        }
    }
    var escMonitor: Any?

    func closeInput() {
        inModel.cancel()
        inPanel?.orderOut(nil)
        if let m = escMonitor { NSEvent.removeMonitor(m); escMonitor = nil }
        // 只有当前台仍是本应用时才恢复原应用，避免抢走用户新切换的焦点。
        if NSApp.isActive { prevApp?.activate() }
        prevApp = nil
    }

    // MARK: 设置
    @objc func openSettings() {
        if settingsWindow == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
            w.title = "QuietTranslate 设置"; w.styleMask = [.titled, .closable]
            settingsWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.center()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func alert(_ s: String) {
        let a = NSAlert(); a.messageText = s; a.runModal()
    }
}

let app = NSApplication.shared
let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
app.run()
