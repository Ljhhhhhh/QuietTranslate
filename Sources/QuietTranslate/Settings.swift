import Foundation
import Security

struct EngineConfiguration: Codable, Identifiable, Equatable {
    var id: String = UUID().uuidString
    var name: String
    var baseURL: String
    var model: String
    var showInPopup = false
}

struct EnginePreferences: Codable, Equatable {
    var engines: [EngineConfiguration]
    var preferredID: String

    var popupEngines: [EngineConfiguration] {
        engines.filter { $0.id == preferredID } + engines.filter { $0.id != preferredID && $0.showInPopup }
    }

    func validate() throws {
        guard !engines.isEmpty, engines.contains(where: { $0.id == preferredID }),
              Set(engines.map(\.id)).count == engines.count else {
            throw Settings.error("请保留至少一个引擎，并选择首选引擎。")
        }
        for engine in engines {
            guard !engine.id.isEmpty, !engine.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !engine.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw Settings.error("每个引擎都需要填写名称和模型。")
            }
            guard let url = URL(string: engine.baseURL), let scheme = url.scheme,
                  ["http", "https"].contains(scheme), let host = url.host, !host.isEmpty,
                  url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else {
                throw Settings.error("“\(engine.name)”的服务地址无效，请填写 http 或 https base URL，凭据请填入 API Key。")
            }
        }
    }
}

enum Settings {
    private static let d = UserDefaults.standard
    static let maxInput = 5000
    static let timeout: TimeInterval = 60

    static func error(_ message: String) -> NSError {
        NSError(domain: "QuietTranslate.Settings", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }

    static func loadEngines() throws -> EnginePreferences {
        if d.object(forKey: "enginePreferences") != nil {
            do {
                guard let data = d.data(forKey: "enginePreferences") else { throw Self.error("配置格式无效") }
                let preferences = try JSONDecoder().decode(EnginePreferences.self, from: data)
                try preferences.validate()
                return preferences
            } catch {
                throw Self.error("无法读取引擎配置，原配置已保留。请检查本机配置后重新打开设置。")
            }
        }
        return EnginePreferences(engines: [
            EngineConfiguration(id: "local", name: "本地模型",
                                baseURL: d.string(forKey: "baseURL") ?? "http://127.0.0.1:8765/v1",
                                model: d.string(forKey: "model") ?? "hy-mt2-1.8b-q4", showInPopup: true),
            EngineConfiguration(id: "cpa", name: "CPA",
                                baseURL: d.string(forKey: "cpaBaseURL") ?? "http://127.0.0.1:18317/v1",
                                model: d.string(forKey: "cpaModel") ?? "gemini-2.5-flash",
                                showInPopup: d.bool(forKey: "cpaEnabled"))
        ], preferredID: "local")
    }

    /// Validate before touching credentials; commit configuration before cleaning up removed credentials.
    static func saveEngines(_ preferences: EnginePreferences, keys: [String: String], clearing: Set<String>) throws -> String {
        try preferences.validate()
        let old = try loadEngines()
        let data = try JSONEncoder().encode(preferences)
        for engine in preferences.engines {
            if clearing.contains(engine.id) {
                try saveKey("", for: engine.id)
            } else if let key = keys[engine.id], !key.isEmpty {
                try saveKey(key, for: engine.id)
            } else if engine.id == "local", let legacy = d.string(forKey: "apiKey"), !legacy.isEmpty {
                try saveKey(readKey(for: engine.id), for: engine.id)
            }
        }
        d.set(data, forKey: "enginePreferences")
        d.removeObject(forKey: "apiKey")
        do {
            for engine in old.engines where !preferences.engines.contains(where: { $0.id == engine.id }) {
                try saveKey("", for: engine.id)
            }
        } catch {
            return "配置已保存，但未能清理已删除引擎的钥匙串凭据：" + error.localizedDescription
        }
        return "已保存，下次翻译生效。"
    }

    private static func keyQuery(_ id: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "local.quiettranslate",
         kSecAttrAccount as String: id == "cpa" ? "cpa-api-key" : "engine-" + id + "-api-key"]
    }

    static func readKey(for id: String) throws -> String {
        var query = keyQuery(id)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return id == "local" ? d.string(forKey: "apiKey") ?? "" : "" }
        guard status == errSecSuccess, let data = result as? Data else {
            throw error("无法读取引擎凭据，请允许钥匙串访问，或在引擎设置中重新填写 API Key。")
        }
        return String(decoding: data, as: UTF8.self)
    }

    private static func saveKey(_ key: String, for id: String) throws {
        let query = keyQuery(id)
        let status: OSStatus
        if key.isEmpty {
            let deleted = SecItemDelete(query as CFDictionary)
            status = deleted == errSecItemNotFound ? errSecSuccess : deleted
        } else {
            let attributes = [kSecValueData as String: Data(key.utf8)]
            let updated = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            if updated == errSecItemNotFound {
                status = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
            } else { status = updated }
        }
        guard status == errSecSuccess else {
            throw error("无法保存引擎凭据，请检查钥匙串是否已解锁。")
        }
    }
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
