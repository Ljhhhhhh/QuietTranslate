import SwiftUI
import AppKit

private enum Celadon {
    static let accent = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 0.10, green: 0.68, blue: 0.69, alpha: 1)
            : NSColor(srgbRed: 0.03, green: 0.35, blue: 0.36, alpha: 1)
    })
    static let surface = Color(red: 0.99, green: 0.985, blue: 0.97)
    static let source = Color(red: 0.95, green: 0.97, blue: 0.96)
    static let strip = Color(red: 0.88, green: 0.96, blue: 0.91)
    static let ink = Color(red: 0.13, green: 0.18, blue: 0.16)
    static let muted = Color(red: 0.40, green: 0.46, blue: 0.44)
    static let edge = Color(red: 0.82, green: 0.86, blue: 0.83)
}

private struct PointerCursor: ViewModifier {
    @Environment(\.isEnabled) private var isEnabled

    func body(content: Content) -> some View {
        content.onContinuousHover { phase in
            switch phase {
            case .active:
                (isEnabled ? NSCursor.pointingHand : NSCursor.arrow).set()
            case .ended:
                NSCursor.arrow.set()
            }
        }
    }
}

private struct PanelControlFeedback: ViewModifier {
    var isPressed = false
    var disabledOpacity: Double = 0.4
    @State private var isHovered = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .modifier(PointerCursor())
            .background(Celadon.accent.opacity(isEnabled ? (isPressed ? 0.24 : (isHovered ? 0.12 : 0)) : 0),
                        in: RoundedRectangle(cornerRadius: 7))
            .opacity(isEnabled ? 1 : disabledOpacity)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovered)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.08), value: isPressed)
            .onHover { isHovered = $0 }
    }
}

private struct PanelButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(4)
            .contentShape(Rectangle())
            .modifier(PanelControlFeedback(isPressed: configuration.isPressed))
    }
}

private struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ view: NSView, context: Context) {}

    private final class DragView: NSView {
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
    }
}

private struct WindowResizeHandle: NSViewRepresentable {
    var fromLeft: Bool

    func makeNSView(context: Context) -> HandleView {
        let view = HandleView()
        view.fromLeft = fromLeft
        view.setAccessibilityLabel(fromLeft ? "左下角调整窗口大小" : "右下角调整窗口大小")
        return view
    }
    func updateNSView(_ view: HandleView, context: Context) {}

    final class HandleView: NSView {
        var fromLeft = false

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override var mouseDownCanMoveWindow: Bool { false }
        override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }

        override func mouseDown(with event: NSEvent) {
            guard let panel = window as? FloatPanel else { return }
            let initial = panel.frame
            let start = panel.convertPoint(toScreen: event.locationInWindow)
            panel.isResizingFromHandle = true
            defer { panel.isResizingFromHandle = false }
            while let next = panel.nextEvent(matching: [.leftMouseDragged, .leftMouseUp],
                                             until: .distantFuture, inMode: .eventTracking, dequeue: true) {
                let point = panel.convertPoint(toScreen: next.locationInWindow)
                let delta = NSPoint(x: point.x - start.x, y: point.y - start.y)
                panel.setFrame(FloatPanel.resizedFrame(initial, delta: delta, fromLeft: fromLeft,
                                                       minimum: panel.contentMinSize), display: true)
                if next.type == .leftMouseUp { break }
            }
        }
    }
}

struct DirectionMenu: View {
    @ObservedObject var m: TranslationModel
    @State private var isPresented = false
    private var toEnglish: Bool { m.direction.target(for: m.source) == "English" }

    private func title(for direction: Direction) -> String {
        switch direction {
        case .auto: "自动 · 中英互译"
        case .toChinese: "英语 → 简体中文"
        case .toEnglish: "简体中文 → 英语"
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            Button {
                isPresented.toggle()
            } label: {
                HStack(spacing: 8) {
                    Text(title(for: m.direction))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                }
                .fontWeight(.medium)
                .foregroundStyle(Celadon.muted)
                .padding(.horizontal, 12).padding(.vertical, 7)
            }
            .buttonStyle(.plain)
            .modifier(PanelControlFeedback(isPressed: isPresented))
            .overlay(Capsule().strokeBorder(Celadon.edge, lineWidth: 0.7))
            .clipShape(Capsule())
            .contentShape(Capsule())
            .accessibilityLabel("翻译方向")
            .accessibilityValue(title(for: m.direction))
            .help(toEnglish ? "当前译为英语" : "当前译为简体中文")
            .popover(isPresented: $isPresented, arrowEdge: .bottom) {
                VStack(spacing: 2) {
                    ForEach(Direction.allCases) { direction in
                        Button {
                            isPresented = false
                            m.direction = direction
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 13, weight: .semibold))
                                    .opacity(m.direction == direction ? 1 : 0)
                                    .accessibilityHidden(true)
                                Text(title(for: direction))
                                Spacer(minLength: 0)
                            }
                            .foregroundStyle(m.direction == direction ? Celadon.accent : Celadon.ink)
                            .padding(.horizontal, 10).padding(.vertical, 10)
                            .contentShape(Rectangle())
                            .background(m.direction == direction ? Celadon.strip : .clear,
                                        in: RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                        .modifier(PanelControlFeedback())
                        .accessibilityAddTraits(m.direction == direction ? [.isSelected] : [])
                    }
                }
                .font(.system(size: 13))
                .padding(6).frame(width: 252)
                .background(Celadon.surface)
                .onExitCommand { isPresented = false }
            }
        }
        .font(.system(size: 12))
        .fixedSize()
        .onChange(of: m.direction) { _, _ in
            if !m.source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { m.translate() }
        }
    }
}

// NSTextView 先处理输入法组合；只有未组合的 Return 才提交。
private final class SourceTextView: NSTextView {
    var submit: () -> Void = {}

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        // 组合输入先于 SwiftUI 绑定更新，占位提示必须读取原生编辑状态。
        guard string.isEmpty, !hasMarkedText() else { return }
        ("输入或粘贴文字…" as NSString).draw(at: textContainerOrigin, withAttributes: [
            .font: font ?? NSFont.systemFont(ofSize: 17),
            .foregroundColor: NSColor(Celadon.muted)
        ])
    }

    override func didChangeText() {
        super.didChangeText()
        needsDisplay = true
    }

    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
        needsDisplay = true
    }

    override func unmarkText() {
        super.unmarkText()
        needsDisplay = true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.initialFirstResponder = self
    }
    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if (event.keyCode == 36 || event.keyCode == 76), !hasMarkedText(),
           modifiers.intersection([.shift, .command, .control, .option]).isEmpty {
            submit()
        } else if (event.keyCode == 36 || event.keyCode == 76), !hasMarkedText(),
                  (modifiers == .shift || modifiers == .command) {
            insertNewline(nil)
        } else {
            super.keyDown(with: event)
        }
    }
}

private struct SourceEditor: NSViewRepresentable {
    @Binding var text: String
    var submit: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        let editor = SourceTextView()
        scroll.hasVerticalScroller = false
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        editor.drawsBackground = false
        editor.isRichText = false
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.font = .systemFont(ofSize: 17)
        editor.textColor = NSColor(Celadon.ink)
        editor.insertionPointColor = NSColor(Celadon.accent)
        editor.textContainerInset = NSSize(width: 0, height: 4)
        editor.textContainer?.lineFragmentPadding = 0
        editor.isHorizontallyResizable = false
        editor.isVerticallyResizable = true
        editor.autoresizingMask = [.width]
        editor.textContainer?.widthTracksTextView = true
        editor.delegate = context.coordinator
        editor.setAccessibilityLabel("待翻译的原文")
        scroll.documentView = editor
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let editor = scroll.documentView as? SourceTextView else { return }
        editor.submit = submit
        if editor.string != text, !editor.hasMarkedText() {
            editor.string = text
            editor.needsDisplay = true
        }
    }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SourceEditor
        init(_ parent: SourceEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? NSTextView else { return }
            parent.text = editor.string
        }
    }
}

// 系统“始终显示滚动条”时，scrollIndicators 仍会画出滚动条。
private struct HiddenScrollers: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { Hider() }
    func updateNSView(_ view: NSView, context: Context) {}
    private final class Hider: NSView {
        override func viewDidMoveToSuperview() { super.viewDidMoveToSuperview(); hide() }
        override func layout() { super.layout(); hide() }
        private func hide() {
            guard let scroll = enclosingScrollView else { return }
            if scroll.hasVerticalScroller { scroll.hasVerticalScroller = false }
            if scroll.hasHorizontalScroller { scroll.hasHorizontalScroller = false }
        }
    }
}

struct OutputText: View {
    let result: TranslationResult
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if !result.output.isEmpty {
                    Text(result.output).font(.system(size: 19)).lineSpacing(7).textSelection(.enabled)
                } else if case .loading = result.phase {
                    Text("译文即将显示在这里…").foregroundStyle(Celadon.muted)
                } else if case .idle = result.phase {
                    Text("译文将显示在这里").foregroundStyle(Celadon.muted)
                }
                if case .failed(let message) = result.phase {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .font(.system(size: 13)).textSelection(.enabled)
                        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .font(.system(size: 14))
            .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4)
            .background(HiddenScrollers())
        }
        .scrollIndicators(.hidden)
    }
}

private struct EngineSwitcher: View {
    @ObservedObject var m: TranslationModel

    var body: some View {
        ScrollView(.horizontal) {
            segments
        }
        .scrollIndicators(.automatic)
        .frame(height: 36)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("翻译引擎")
    }

    private var segments: some View {
        HStack(spacing: 12) {
            ForEach(m.results) { result in
                Button { m.selectEngine(result.id) } label: {
                    HStack(spacing: 5) {
                        Text(result.configuration.name).lineLimit(1)
                        if case .loading = result.phase {
                            ProgressView().controlSize(.mini)
                        } else if case .failed = result.phase {
                            Image(systemName: "exclamationmark.circle")
                                .accessibilityLabel("翻译失败")
                        }
                    }
                    .font(.system(size: 13, weight: m.selectedEngineID == result.id ? .semibold : .regular))
                    .foregroundStyle(m.selectedEngineID == result.id ? Celadon.accent : Celadon.muted)
                    .padding(.horizontal, 4).frame(height: 32)
                    .overlay(alignment: .bottom) {
                        if m.selectedEngineID == result.id {
                            Capsule().fill(Celadon.accent).frame(height: 2)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .modifier(PanelControlFeedback())
                .help(result.configuration.name)
                .accessibilityLabel(result.configuration.name + (result.id == m.results.first?.id ? "，首选引擎" : ""))
                .accessibilityValue(m.selectedEngineID == result.id ? "已选中" : "未选中")
                .accessibilityAddTraits(m.selectedEngineID == result.id ? [.isSelected] : [])
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}

private struct TranslationPanel: View {
    @ObservedObject var m: TranslationModel
    var close: () -> Void
    var retry: () -> Void
    var openSettings: () -> Void

    private var canTranslate: Bool {
        !m.source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && m.source.count <= Settings.maxInput
    }
    private func submit() { if canTranslate { m.translate() } }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Celadon.edge.opacity(0.5))
            HStack(spacing: 0) {
                sourcePane
                Divider().overlay(Celadon.edge.opacity(0.5))
                translationPane
            }
        }
        .buttonStyle(PanelButtonStyle()).tint(Celadon.accent).foregroundStyle(Celadon.ink)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Celadon.surface)
        .overlay(alignment: .bottomLeading) {
            WindowResizeHandle(fromLeft: true).frame(width: 28, height: 12)
                .help("拖动调整窗口大小")
        }
        .overlay(alignment: .bottomTrailing) {
            WindowResizeHandle(fromLeft: false).frame(width: 28, height: 12)
                .help("拖动调整窗口大小")
        }
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Celadon.edge, lineWidth: 0.7))
        .environment(\.colorScheme, .light)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(nsImage: BrandIcon.image(size: 20))
                .accessibilityHidden(true).allowsHitTesting(false)
            Text("QuietTranslate").font(.system(size: 13, weight: .medium))
                .allowsHitTesting(false)
            Spacer()
            Button(action: openSettings) {
                Image(systemName: "gearshape").frame(width: 24, height: 24)
            }
            .foregroundStyle(Celadon.muted).help("管理翻译引擎").accessibilityLabel("管理翻译引擎")
            Button { m.isPinned.toggle() } label: {
                Image(systemName: m.isPinned ? "pin.fill" : "pin")
                    .frame(width: 24, height: 24)
                    .background(m.isPinned ? Celadon.strip : Color.clear, in: RoundedRectangle(cornerRadius: 7))
            }
            .foregroundStyle(m.isPinned ? Celadon.accent : Celadon.muted)
            .help(m.isPinned ? "取消钉住窗口" : "钉住窗口：点击外部时保持显示")
            .accessibilityLabel(m.isPinned ? "取消钉住窗口" : "钉住窗口")
            .accessibilityValue(m.isPinned ? "已钉住" : "未钉住")
            Button(action: close) {
                Image(systemName: "xmark").frame(width: 24, height: 24)
            }
            .foregroundStyle(Celadon.muted).help("关闭").accessibilityLabel("关闭翻译窗口")
        }
        .font(.system(size: 13))
        .padding(.horizontal, 20).padding(.vertical, 6)
        .background(WindowDragArea())
    }

    private var sourcePane: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                Text("原文").font(.system(size: 13)).foregroundStyle(Celadon.muted)
                DirectionMenu(m: m)
                Spacer(minLength: 0)
            }
            .frame(height: 36)
            if m.source.count > Settings.maxInput {
                Text("原文过长（上限 \(Settings.maxInput) 字）")
                    .font(.system(size: 12)).foregroundStyle(.red)
            }
            SourceEditor(text: $m.source, submit: submit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack(spacing: 8) {
                Text("Shift + Return 换行")
                    .font(.system(size: 11)).foregroundStyle(Celadon.muted)
                Spacer(minLength: 0)
                Button(action: submit) {
                    HStack(spacing: 6) {
                        Text("翻译")
                        Image(systemName: "return").accessibilityHidden(true)
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(canTranslate ? Color.white : Celadon.ink)
                    .padding(.horizontal, 14).frame(height: 32)
                    .background(Celadon.accent.opacity(canTranslate ? 1 : 0.2), in: RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .modifier(PanelControlFeedback(disabledOpacity: 1))
                .disabled(!canTranslate)
                .help("Return 翻译；Shift + Return 或 ⌘ Return 换行")
                .accessibilityLabel("翻译原文")
            }
            .frame(height: 32)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Celadon.source)
    }

    private var translationPane: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                Text("译文").font(.system(size: 13)).foregroundStyle(Celadon.muted)
                EngineSwitcher(m: m)
                    .frame(minWidth: 0, maxWidth: .infinity)
                if let result = m.selectedResult {
                    Button { m.copy(result.id) } label: {
                        Label("复制", systemImage: "doc.on.doc")
                            .font(.system(size: 12)).fixedSize()
                    }
                    .foregroundStyle(Celadon.muted)
                    .disabled(result.output.isEmpty)
                    .help("复制当前译文")
                    .accessibilityLabel("复制" + result.configuration.name + "译文")
                }
            }
            .frame(height: 36)
            if let error = m.configurationError {
                VStack(alignment: .leading, spacing: 12) {
                    Text(error).font(.system(size: 13)).foregroundStyle(.red).textSelection(.enabled)
                    Button("设置", action: openSettings)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else if let result = m.selectedResult {
                OutputText(result: result)
                    .id(result.id)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                HStack(spacing: 8) {
                    Text(result.configuration.model)
                        .foregroundStyle(Celadon.muted).lineLimit(1).truncationMode(.middle)
                        .help(result.configuration.model)
                    Spacer(minLength: 0)
                    if case .loading = result.phase {
                        Button("停止") { m.cancel(result.id) }
                    } else if case .failed = result.phase {
                        Button("设置", action: openSettings)
                        Button("重试") {
                            if m.source.isEmpty { retry() } else { m.retry(result.id) }
                        }
                    } else if case .idle = result.phase, result.hasRequested {
                        Button("重新翻译") { m.retry(result.id) }
                    }
                }
                .font(.system(size: 11)).foregroundStyle(Celadon.accent)
                .frame(height: 32)
            } else {
                Spacer(minLength: 0)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct SelectionView: View {
    @ObservedObject var m: TranslationModel
    var close: () -> Void
    var retry: () -> Void
    var openSettings: () -> Void
    var body: some View { TranslationPanel(m: m, close: close, retry: retry, openSettings: openSettings) }
}

struct InputView: View {
    @ObservedObject var m: TranslationModel
    var close: () -> Void
    var openSettings: () -> Void
    var body: some View { TranslationPanel(m: m, close: close, retry: m.translate, openSettings: openSettings) }
}

struct SettingsView: View {
    @State private var preferences: EnginePreferences
    @State private var selectedID: String?
    @State private var showingShortcuts = false
    @State private var keys: [String: String] = [:]
    @State private var clearing: Set<String> = []
    @State private var status = ""
    @State private var busy = false
    @State private var confirmingDelete = false
    private let loadFailure: String?

    init() {
        do {
            let saved = try Settings.loadEngines()
            _preferences = State(initialValue: saved)
            _selectedID = State(initialValue: saved.preferredID)
            loadFailure = nil
        } catch {
            _preferences = State(initialValue: EnginePreferences(engines: [], preferredID: ""))
            loadFailure = error.localizedDescription
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                sidebar
                Divider()
                if showingShortcuts {
                    shortcuts
                } else if let loadFailure {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("无法读取设置", systemImage: "exclamationmark.triangle")
                            .font(.title3.weight(.semibold))
                        Text(loadFailure).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                    .padding(32).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    engineSettings.disabled(busy)
                }
            }
            Divider()
            HStack(spacing: 16) {
                Text(status.isEmpty ? "保存后，下次翻译生效。" : status)
                    .font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.updatesFrequently)
                Spacer(minLength: 0)
                if busy { ProgressView().controlSize(.small) }
                Button("保存设置", action: save)
                    .buttonStyle(.borderedProminent)
                    .modifier(PointerCursor())
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(busy || loadFailure != nil)
            }
            .padding(.horizontal, 24).padding(.vertical, 16)
            .background(.background)
        }
        .frame(width: 860, height: 740)
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(Celadon.accent)
        .alert("删除这个引擎？", isPresented: $confirmingDelete) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive, action: deleteEngine)
        } message: {
            Text("保存后移除该引擎及其凭据。删除首选引擎时，将使用列表中的第一个引擎。")
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 9) {
                Image(nsImage: BrandIcon.image(size: 28))
                    .accessibilityHidden(true)
                Text("QuietTranslate").font(.system(size: 13, weight: .semibold))
            }
            .padding(.horizontal, 8).padding(.top, 24).padding(.bottom, 24)
            navigationButton("翻译引擎", icon: "square.stack.3d.up", selected: !showingShortcuts) {
                showingShortcuts = false
            }
            navigationButton("快捷键与权限", icon: "command", selected: showingShortcuts) {
                showingShortcuts = true
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .frame(width: 184)
        .background(.regularMaterial)
    }

    private func navigationButton(_ title: String, icon: String, selected: Bool,
                                  action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 13, weight: selected ? .semibold : .regular))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12).padding(.vertical, 11)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(selected ? Celadon.accent : Color.primary)
        .background(selected ? Celadon.accent.opacity(0.10) : .clear,
                    in: RoundedRectangle(cornerRadius: 8))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .modifier(PointerCursor())
    }

    private var engineSettings: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("翻译引擎").font(.system(size: 25, weight: .semibold))
                Text("选择自动翻译的引擎，管理其他翻译选择。")
                    .font(.callout).foregroundStyle(.secondary)
            }
            .padding(.bottom, 22)
            HStack(spacing: 10) {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(preferences.engines) { engine in
                            Button { selectedID = engine.id } label: {
                                HStack(spacing: 5) {
                                    Text(engine.name.isEmpty ? "未命名引擎" : engine.name)
                                        .lineLimit(1)
                                    if engine.id == preferences.preferredID {
                                        Text("· 首选")
                                    }
                                }
                                .font(.callout)
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .background(engine.id == selectedID ? Celadon.accent.opacity(0.10) : Color(nsColor: .controlBackgroundColor),
                                            in: RoundedRectangle(cornerRadius: 8))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 8)
                                        .strokeBorder(engine.id == selectedID ? Celadon.accent : Color(nsColor: .separatorColor), lineWidth: 1)
                                }
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(engine.id == selectedID ? Celadon.accent : Color.primary)
                            .accessibilityAddTraits(engine.id == selectedID ? .isSelected : [])
                            .modifier(PointerCursor())
                        }
                    }.padding(3)
                }
                .scrollIndicators(.hidden)
                .frame(height: 44)
                Button(action: addEngine) { Label("添加引擎", systemImage: "plus") }
                    .buttonStyle(.borderless).modifier(PointerCursor())
            }
            .padding(.bottom, 22)
            if let index = preferences.engines.firstIndex(where: { $0.id == selectedID }) {
                ScrollView {
                    engineEditor(index).id(preferences.engines[index].id)
                        .padding(3)
                }
            } else {
                Text("选择一个引擎进行配置")
                    .foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(.horizontal, 29).padding(.top, 28).padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func engineEditor(_ index: Int) -> some View {
        let engine = preferences.engines[index]
        let preferred = engine.id == preferences.preferredID
        return VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 10) {
                Image(systemName: "server.rack")
                    .foregroundStyle(Celadon.accent)
                    .frame(width: 34, height: 34)
                    .background(Celadon.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityHidden(true)
                Text(engine.name.isEmpty ? "未命名引擎" : engine.name)
                    .font(.headline).lineLimit(2)
                Spacer(minLength: 0)
                Text(preferred ? "自动翻译" : (engine.showInPopup ? "首次选中时翻译" : "未加入弹窗"))
                    .font(.caption).foregroundStyle(Celadon.accent)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Celadon.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 5))
            }
            VStack(alignment: .leading, spacing: 14) {
                settingsField("引擎名称", text: $preferences.engines[index].name, prompt: "为引擎命名")
                settingsField("服务地址", text: $preferences.engines[index].baseURL,
                              prompt: "http://127.0.0.1:端口/v1")
                HStack(alignment: .bottom, spacing: 14) {
                    settingsField("模型名称", text: $preferences.engines[index].model, prompt: "服务中的模型 ID")
                    Button { check(engine) } label: { Label("检查连接", systemImage: "network") }
                        .controlSize(.large).modifier(PointerCursor())
                }
                Text("OpenAI 兼容基础地址，通常以 /v1 结尾，不含 /chat/completions。检查连接会查询模型列表。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label(preferred ? "首选引擎 · 自动翻译" : "打开翻译窗口时自动翻译", systemImage: preferred ? "star.fill" : "star")
                        .foregroundStyle(preferred ? Celadon.accent : Color.primary)
                    Spacer(minLength: 0)
                    if !preferred {
                        Button("设为首选") { preferences.preferredID = engine.id }
                            .modifier(PointerCursor())
                    }
                }
                Toggle("在翻译窗口中提供此引擎", isOn: Binding(
                    get: { preferred || preferences.engines[index].showInPopup },
                    set: { preferences.engines[index].showInPopup = $0 }))
                    .toggleStyle(.checkbox)
                    .disabled(preferred).modifier(PointerCursor())
                Text("首选引擎始终显示。其他引擎在首次选中时翻译。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .font(.callout)
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5) }
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text("API Key").font(.callout.weight(.medium))
                    Text("可选").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button(clearing.contains(engine.id) ? "撤销清除" : "清除已存密钥") {
                        if clearing.contains(engine.id) { clearing.remove(engine.id) }
                        else { clearing.insert(engine.id) }
                    }
                    .buttonStyle(.borderless).modifier(PointerCursor())
                }
                SecureField("新的 API Key", text: Binding(
                    get: { keys[engine.id] ?? "" }, set: { keys[engine.id] = $0 }),
                            prompt: Text("留空保留已有密钥"))
                    .textFieldStyle(.roundedBorder).controlSize(.large)
                    .disabled(clearing.contains(engine.id))
                Text(clearing.contains(engine.id) ? "保存后清除该引擎的密钥；保存前可撤销。" : "密钥保存在 macOS 钥匙串中。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack(alignment: .top, spacing: 14) {
                Button("删除此引擎", role: .destructive) { confirmingDelete = true }
                    .buttonStyle(.borderless).modifier(PointerCursor())
                    .disabled(preferences.engines.count <= 1)
                Spacer(minLength: 0)
                Text("翻译文本会发送至所填服务；网关可能继续转发到上游模型。")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: 330, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func settingsField(_ title: String, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.callout)
            TextField(title, text: text, prompt: Text(prompt))
                .textFieldStyle(.roundedBorder).controlSize(.large)
                .labelsHidden()
        }
    }

    private var shortcuts: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("快捷键与权限").font(.system(size: 25, weight: .semibold))
                    Text("随时唤起翻译，继续手边的工作。")
                        .font(.callout).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 18) {
                    HStack { Text("划词翻译"); Spacer(); Text("⌥ D").font(.system(.body, design: .monospaced)) }
                    Divider()
                    HStack { Text("输入翻译"); Spacer(); Text("⌥ T").font(.system(.body, design: .monospaced)) }
                }
                .padding(20)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 12) {
                    Text("辅助功能权限").font(.headline)
                    Text("划词翻译需要此权限，用于读取其他应用中选中的文字。输入翻译可独立使用。")
                        .font(.callout).foregroundStyle(.secondary)
                    Button("授权辅助功能") { Selection.requestPermission() }
                        .modifier(PointerCursor())
                }
            }
            .padding(32).frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func addEngine() {
        let engine = EngineConfiguration(name: "自定义引擎", baseURL: "", model: "")
        preferences.engines.append(engine)
        selectedID = engine.id
        status = "填写服务地址与模型后保存。"
    }

    private func deleteEngine() {
        guard let selectedID, preferences.engines.count > 1 else { return }
        preferences.engines.removeAll { $0.id == selectedID }
        keys[selectedID] = nil
        clearing.remove(selectedID)
        if preferences.preferredID == selectedID { preferences.preferredID = preferences.engines[0].id }
        self.selectedID = preferences.preferredID
        status = "引擎已从列表移除，保存后生效。"
    }

    private func save() {
        var saved = preferences
        for i in saved.engines.indices {
            saved.engines[i].name = saved.engines[i].name.trimmingCharacters(in: .whitespacesAndNewlines)
            saved.engines[i].baseURL = saved.engines[i].baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            saved.engines[i].model = saved.engines[i].model.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        do { try saved.validate() } catch { status = error.localizedDescription; return }
        let savedKeys = keys, cleared = clearing
        busy = true
        Task {
            do {
                status = try await Task.detached { try Settings.saveEngines(saved, keys: savedKeys, clearing: cleared) }.value
                preferences = saved
                keys = [:]
                clearing = []
            } catch { status = error.localizedDescription }
            busy = false
        }
    }

    private func check(_ engine: EngineConfiguration) {
        do { try EnginePreferences(engines: [engine], preferredID: engine.id).validate() }
        catch { status = error.localizedDescription; return }
        let key = clearing.contains(engine.id) ? "" : keys[engine.id].flatMap { $0.isEmpty ? nil : $0 }
        busy = true
        status = engine.name + "：检查中…"
        Task {
            status = engine.name + "：" + (await Translator.check(engine, keyOverride: key))
            busy = false
        }
    }
}
