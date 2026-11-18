import AppKit
import ApplicationServices
import SwiftUI
import Carbon.HIToolbox
import Sparkle

/// 浮层：不激活应用，因此不抢原应用键盘焦点。
final class FloatPanel: NSPanel {
    var keyable = false
    var isResizingFromHandle = false
    private(set) var interactionVersion = 0
    override var canBecomeKey: Bool { keyable }

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel:
            interactionVersion &+= 1
        default: break
        }
        super.sendEvent(event)
    }

    override func resignKey() {
        interactionVersion &+= 1
        super.resignKey()
    }

    func isInteracting(at point: NSPoint) -> Bool {
        // 系统缩放热区延伸到窗口外，边缘按下不应触发外部点击关闭。
        isResizingFromHandle || inLiveResize || frame.insetBy(dx: -8, dy: -8).contains(point)
    }

    static func resizedFrame(_ initial: NSRect, delta: NSPoint, fromLeft: Bool, minimum: NSSize) -> NSRect {
        let width = max(minimum.width, initial.width + (fromLeft ? -delta.x : delta.x))
        let height = max(minimum.height, initial.height - delta.y)
        return NSRect(x: fromLeft ? initial.maxX - width : initial.minX,
                      y: initial.maxY - height, width: width, height: height)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    let selModel = TranslationModel()
    let inModel = TranslationModel()
    var selPanel: FloatPanel?
    var inPanel: FloatPanel?
    var settingsWindow: NSWindow?
    var statusItem: NSStatusItem!
    var hotKeys: [HotKey] = []
    var prevApp: NSRunningApplication?
    var outsideMonitor: Any?
    var localPanelMonitor: Any?
    private var selectionEscapeTap: CFMachPort?
    private var selectionEscapePressed = false
    var selectionTask: Task<Void, Never>?
    var selectionRequestID: UUID?
    private let selectionFrameName = "QuietTranslate.SelectionPanel"
    private let inputFrameName = "QuietTranslate.InputPanel"
    let updaterController = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if inPanel?.isVisible != true { inputAction() }
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        stopWatchingSelectionEscape()
        selPanel?.saveFrame(usingName: selectionFrameName)
        inPanel?.saveFrame(usingName: inputFrameName)
    }

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
        statusItem.button?.image = BrandIcon.image(size: 18, monochrome: true)
        let menu = NSMenu()
        for (t, a) in [("划词翻译  ⌥D", #selector(selectionAction)), ("输入翻译  ⌥T", #selector(inputAction)),
                       ("设置…", #selector(openSettings))] {
            menu.addItem(withTitle: t, action: a, keyEquivalent: "").target = self
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "检查更新…", action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)),
                     keyEquivalent: "").target = updaterController
        menu.addItem(withTitle: "自动检查更新", action: #selector(toggleAutomaticUpdates), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
        updaterController.startUpdater()

        let mods = optionKey
        let a = HotKey(keyCode: kVK_ANSI_D, modifiers: mods) { [weak self] in self?.selectionAction() }
        let b = HotKey(keyCode: kVK_ANSI_T, modifiers: mods) { [weak self] in self?.inputAction() }
        hotKeys = [a, b].compactMap { $0 }
        if hotKeys.count < 2 { alert("快捷键 ⌥D / ⌥T 注册失败，可能与其他应用冲突；仍可使用菜单栏。") }
        outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            let location = NSEvent.mouseLocation
            Task { @MainActor in
                guard let self else { return }
                if let panel = self.selPanel, panel.isVisible, !self.selModel.isPinned,
                   !panel.isInteracting(at: location) { self.closeSelection() }
                if let panel = self.inPanel, panel.isVisible, !self.inModel.isPinned,
                   !panel.isInteracting(at: location) { self.closeInput(restoreFocus: false) }
            }
        }
        localPanelMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown {
                guard event.keyCode == UInt16(kVK_Escape),
                      event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty,
                      let panel = event.window as? FloatPanel, panel.isKeyWindow, panel.isVisible,
                      !((panel.firstResponder as? NSTextInputClient)?.hasMarkedText() ?? false) else { return event }
                if event.isARepeat { return nil }
                if panel === self.inPanel { self.closeInput() }
                else if panel === self.selPanel { self.closeSelection() }
                else { return event }
                return nil
            }
            if let window = event.window,
               window === self.settingsWindow || window === self.selPanel || window === self.inPanel {
                let location = NSEvent.mouseLocation
                if let panel = self.selPanel, panel.isVisible, window !== panel, !self.selModel.isPinned,
                   !panel.isInteracting(at: location) {
                    self.closeSelection()
                }
                if let panel = self.inPanel, panel.isVisible, window !== panel, !self.inModel.isPinned,
                   !panel.isInteracting(at: location) {
                    self.closeInput(restoreFocus: false)
                }
            }
            return event
        }
        _ = requireConfiguration()
    }

    private func requireConfiguration() -> Bool {
        guard let preferences = try? Settings.loadEngines(), !preferences.engines.isEmpty else {
            openSettings()
            return false
        }
        return true
    }

    @objc func toggleAutomaticUpdates(_ sender: NSMenuItem) {
        updaterController.updater.automaticallyChecksForUpdates.toggle()
    }

    @objc func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(toggleAutomaticUpdates) {
            menuItem.state = updaterController.updater.automaticallyChecksForUpdates ? .on : .off
        }
        return true
    }

    // MARK: 划词
    @objc func selectionAction() {
        if selectionRequestID != nil { closeSelection(); return }
        if selPanel?.isVisible == true {
            if selModel.isPinned { selPanel?.orderFrontRegardless() } else { closeSelection() }
            return
        }
        runSelection()
    }

    func runSelection() {
        guard requireConfiguration() else { return }
        let previousTask = selectionTask
        let sourcePID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        previousTask?.cancel()
        let id = UUID()
        selectionRequestID = id
        selModel.reset()
        selectionTask = Task {
            await previousTask?.value
            defer {
                if selectionRequestID == id { selectionRequestID = nil; selectionTask = nil }
            }
            do {
                try Task.checkCancellation()
                guard NSWorkspace.shared.frontmostApplication?.processIdentifier == sourcePID else { return }
                let (text, rect) = try await Selection.read()
                try Task.checkCancellation()
                guard selectionRequestID == id else { return }
                selModel.source = text
                showSelection(near: rect, sourcePID: sourcePID)
                selModel.translate()
            } catch is CancellationError {
            } catch {
                guard !Task.isCancelled, selectionRequestID == id else { return }
                selModel.source = ""
                showSelection(near: nil, sourcePID: sourcePID)
                selModel.fail(error.localizedDescription)
            }
        }
    }

    func showSelection(near rect: NSRect?, sourcePID: pid_t?) {
        var shouldPositionNearSelection = false
        if selPanel == nil {
            let p = FloatPanel(contentRect: NSRect(x: 0, y: 0, width: 760, height: 360),
                               styleMask: [.borderless, .resizable, .nonactivatingPanel], backing: .buffered, defer: false)
            p.contentMinSize = NSSize(width: 680, height: 320)
            p.isMovableByWindowBackground = false
            p.level = .floating; p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = true
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            p.hidesOnDeactivate = false
            p.keyable = true
            p.becomesKeyOnlyIfNeeded = true
            p.setFrameAutosaveName(selectionFrameName)
            shouldPositionNearSelection = !p.setFrameUsingName(selectionFrameName)
            let host = NSHostingView(rootView: SelectionView(m: selModel, close: { [weak self] in self?.closeSelection() },
                                                             retry: { [weak self] in self?.retrySelection() },
                                                             openSettings: { [weak self] in self?.openSettings() }))
            host.sizingOptions = []
            p.contentView = host
            selPanel = p
        }
        guard let p = selPanel else { return }
        if shouldPositionNearSelection {
            let size = p.frame.size
            let pt = rect.map { NSPoint(x: $0.minX, y: $0.minY - 8) } ?? NSEvent.mouseLocation
            p.setFrameOrigin(clamp(origin: NSPoint(x: pt.x, y: pt.y - size.height), size: size, anchor: pt))
        }
        p.orderFrontRegardless()
        watchSelectionEscape(sourcePID: sourcePID)
    }

    private func watchSelectionEscape(sourcePID: pid_t?) {
        stopWatchingSelectionEscape()
        guard let sourcePID, sourcePID != ProcessInfo.processInfo.processIdentifier,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == sourcePID,
              AXIsProcessTrusted() else { return }
        let events: CGEventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        guard let tap = CGEvent.tapCreateForPid(pid: sourcePID, place: .headInsertEventTap, options: .defaultTap,
                                               eventsOfInterest: events, callback: { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            let delegate = Unmanaged<AppDelegate>.fromOpaque(context).takeUnretainedValue()
            return MainActor.assumeIsolated { delegate.handleSelectionEscape(type: type, event: event) }
        }, userInfo: Unmanaged.passUnretained(self).toOpaque()),
              let source = CFMachPortCreateRunLoopSource(nil, tap, 0) else { return }
        selectionEscapeTap = tap
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    }

    private func handleSelectionEscape(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        guard let tap = selectionEscapeTap else { return Unmanaged.passUnretained(event) }
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            selectionEscapePressed = false
            if type == .tapDisabledByTimeout { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard event.getIntegerValueField(.keyboardEventKeycode) == Int64(kVK_Escape) else {
            return Unmanaged.passUnretained(event)
        }
        if type == .keyDown {
            if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
                selectionEscapePressed = event.flags.intersection([.maskCommand, .maskAlternate, .maskControl, .maskShift]).isEmpty
            }
            return selectionEscapePressed ? nil : Unmanaged.passUnretained(event)
        }
        guard type == .keyUp, selectionEscapePressed else { return Unmanaged.passUnretained(event) }
        selectionEscapePressed = false
        // 等到松键再移除拦截，避免长按产生的重复按键传给取词应用。
        DispatchQueue.main.async { [weak self] in
            guard let self, self.selectionEscapeTap === tap else { return }
            self.closeSelection()
        }
        return nil
    }

    private func stopWatchingSelectionEscape() {
        if let selectionEscapeTap { CFMachPortInvalidate(selectionEscapeTap) }
        selectionEscapeTap = nil
        selectionEscapePressed = false
    }

    /// 重试：已有原文则直接重译，否则重新取词。
    func retrySelection() {
        if selModel.source.isEmpty { runSelection() } else { selModel.translate() }
    }

    func closeSelection() {
        stopWatchingSelectionEscape()
        selectionRequestID = nil
        selectionTask?.cancel()
        selModel.cancel()
        selPanel?.makeFirstResponder(nil)
        selPanel?.saveFrame(usingName: selectionFrameName)
        selPanel?.orderOut(nil)
        selModel.source = ""
        selModel.isPinned = false
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
        guard requireConfiguration() else { return }
        if inPanel?.isVisible == true {
            if inModel.isPinned {
                NSApp.activate(ignoringOtherApps: true)
                inPanel?.makeKeyAndOrderFront(nil)
            } else { closeInput() }
            return
        }
        if !selModel.isPinned { closeSelection() }
        inModel.reset()
        prevApp = NSWorkspace.shared.frontmostApplication
        var shouldCenter = false
        if inPanel == nil {
            let p = FloatPanel(contentRect: NSRect(x: 0, y: 0, width: 760, height: 360),
                               styleMask: [.borderless, .resizable], backing: .buffered, defer: false)
            p.contentMinSize = NSSize(width: 680, height: 320)
            p.isMovableByWindowBackground = false
            p.keyable = true
            p.level = .floating; p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = true
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            p.hidesOnDeactivate = false
            p.setFrameAutosaveName(inputFrameName)
            shouldCenter = !p.setFrameUsingName(inputFrameName)
            let host = NSHostingView(rootView: InputView(m: inModel, close: { [weak self] in self?.closeInput() },
                                                       openSettings: { [weak self] in self?.openSettings() }))
            host.sizingOptions = []
            p.contentView = host
            inPanel = p
        }
        guard let p = inPanel else { return }
        if shouldCenter {
            let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main!
            let size = p.frame.size
            let v = screen.visibleFrame
            p.setFrameOrigin(NSPoint(x: v.midX - size.width / 2, y: v.midY + v.height * 0.1 - size.height / 2))
        }
        // 首次打开先挂载 SwiftUI 编辑器，确保 initialFirstResponder 已就绪。
        p.contentView?.layoutSubtreeIfNeeded()
        NSApp.activate(ignoringOtherApps: true)
        p.makeKeyAndOrderFront(nil)
        p.makeFirstResponder(p.initialFirstResponder)
        DispatchQueue.main.async { [weak p] in
            guard let p, p.isVisible, p.isKeyWindow, NSApp.isActive else { return }
            p.contentView?.layoutSubtreeIfNeeded()
            p.makeFirstResponder(p.initialFirstResponder)
        }
    }

    func closeInput(restoreFocus: Bool = true) {
        inModel.cancel()
        inPanel?.makeFirstResponder(nil)
        inPanel?.saveFrame(usingName: inputFrameName)
        inPanel?.orderOut(nil)
        inModel.source = ""
        // 只有当前台仍是本应用时才恢复原应用，避免抢走用户新切换的焦点。
        if restoreFocus && NSApp.isActive { prevApp?.activate() }
        prevApp = nil
        inModel.isPinned = false
    }

    // MARK: 设置
    @objc func openSettings() {
        closeSelection()
        closeInput(restoreFocus: false)
        if settingsWindow == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
            w.title = "QuietTranslate 设置"; w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
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
