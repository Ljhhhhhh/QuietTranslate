import SwiftUI

struct DirectionMenu: View {
    @ObservedObject var m: TranslationModel
    var body: some View {
        Picker("", selection: $m.direction) {
            ForEach(Direction.allCases) { Text($0.label).tag($0) }
        }
        .labelsHidden().pickerStyle(.menu).fixedSize()
        .onChange(of: m.direction) { _, _ in if !m.source.isEmpty { m.translate() } }
    }
}

struct StatusBar: View {
    @ObservedObject var m: TranslationModel
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2)
        }
    }
    private var color: Color {
        if case .failed = m.phase { return .red }
        if case .loading = m.phase { return .orange }
        return .green
    }
    private var label: String {
        if case .failed(let e) = m.phase { return e }
        if case .loading = m.phase { return "翻译中…" }
        return "本地模型"
    }
}

struct OutputText: View {
    @ObservedObject var m: TranslationModel
    var body: some View {
        ScrollView {
            Text(m.output.isEmpty ? " " : m.output)
                .font(.system(size: 17)).lineSpacing(3)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// 划词浮层：方向、译文、状态。
struct SelectionView: View {
    @ObservedObject var m: TranslationModel
    var close: () -> Void
    var retry: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                DirectionMenu(m: m)
                Spacer()
                Button(action: m.copy) { Image(systemName: "doc.on.doc") }.help("复制译文")
                    .disabled(m.output.isEmpty)
                Button(action: close) { Image(systemName: "xmark") }.help("关闭")
            }.buttonStyle(.borderless)
            OutputText(m: m).frame(maxHeight: 240)
            Divider()
            HStack {
                StatusBar(m: m)
                Spacer()
                if case .failed = m.phase { Button("重试", action: retry).controlSize(.small) }
            }
        }
        .padding(14).frame(width: 360)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.separator))
    }
}

/// 输入窗口：原文、分隔线、译文。Cmd+Return 提交，Return 换行（TextEditor 默认，输入法候选确认不受影响）。
struct InputView: View {
    @ObservedObject var m: TranslationModel
    var close: () -> Void
    @FocusState private var focused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("输入翻译").font(.system(size: 13, weight: .semibold))
                Spacer()
                DirectionMenu(m: m)
                Button(action: close) { Image(systemName: "xmark") }.buttonStyle(.borderless)
            }
            TextEditor(text: $m.source)
                .font(.system(size: 17)).scrollContentBackground(.hidden)
                .focused($focused).frame(height: 84)
            if m.source.count > Settings.maxInput {
                Text("已超过 \(Settings.maxInput) 字上限，翻译前请缩短").font(.caption).foregroundStyle(.red)
            }
            Divider()
            OutputText(m: m).frame(minHeight: 60, maxHeight: 220)
            HStack {
                StatusBar(m: m)
                Spacer()
                Button(action: m.copy) { Label("复制", systemImage: "doc.on.doc") }
                    .buttonStyle(.borderless).disabled(m.output.isEmpty)
                Button("⌘↩ 翻译", action: m.translate)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(m.source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(16).frame(width: 520)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.separator))
        .onAppear { focused = true }
    }
}

struct SettingsView: View {
    @State private var base = Settings.baseURL
    @State private var model = Settings.model
    @State private var key = Settings.apiKey
    @State private var status = ""
    var body: some View {
        Form {
            TextField("服务地址（base URL）", text: $base)
            TextField("模型", text: $model)
            SecureField("API Key（可选）", text: $key)
            Text("默认仅使用本机服务；请求只发送到上面的地址，无云端回退。").font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("保存并检查连接") {
                    Settings.baseURL = base; Settings.model = model; Settings.apiKey = key
                    status = "检查中…"
                    Task { status = await Translator.check() }
                }
                Text(status).font(.caption).foregroundStyle(.secondary)
            }
            Divider()
            Text("快捷键：⌃⌥D 划词翻译，⌃⌥A 输入翻译").font(.caption)
            Button("授权辅助功能") { Selection.requestPermission() }
        }
        .padding(20).frame(width: 460)
    }
}
