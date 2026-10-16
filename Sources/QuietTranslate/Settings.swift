import Foundation

/// 普通配置保存在 UserDefaults；首版默认只指向本机回环地址。
enum Settings {
    private static let d = UserDefaults.standard
    static let maxInput = 5000

    /// base URL（含 /v1），请求时追加 /chat/completions。
    static var baseURL: String {
        get { d.string(forKey: "baseURL") ?? "http://127.0.0.1:8765/v1" }
        set { d.set(newValue, forKey: "baseURL") }
    }
    static var model: String {
        get { d.string(forKey: "model") ?? "hy-mt2-1.8b-q4" }
        set { d.set(newValue, forKey: "model") }
    }
    /// 仅服务需要时填写；为空则不发送 Authorization。
    static var apiKey: String {
        get { d.string(forKey: "apiKey") ?? "" }
        set { d.set(newValue, forKey: "apiKey") }
    }
    static var timeout: TimeInterval { 60 }
}

enum Direction: String, CaseIterable, Identifiable {
    case auto, toChinese, toEnglish
    var id: String { rawValue }
    var label: String {
        switch self {
        case .auto: "自动 中⇄英"
        case .toChinese: "→ 简体中文"
        case .toEnglish: "→ 英语"
        }
    }
    /// 自动模式：含 CJK 则译成英语，否则译成中文。
    func target(for text: String) -> String {
        switch self {
        case .toChinese: return "Simplified Chinese"
        case .toEnglish: return "English"
        case .auto:
            let cjk = text.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) }
            return cjk ? "English" : "Simplified Chinese"
        }
    }
}
