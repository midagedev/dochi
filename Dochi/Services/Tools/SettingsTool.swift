import Foundation
import os

// MARK: - Settings Key Definitions

private enum SettingKey: String, CaseIterable {
    case wakeWordEnabled
    case wakeWord
    case llmProvider
    case llmModel
    case supertonicVoice
    case ttsSpeed
    case ttsDiffusionSteps
    case chatFontSize
    case sttSilenceTimeout
    case contextAutoCompress
    case contextMaxSize
    case activeAgentName
    case interactionMode
    case fallbackLLMProvider
    case fallbackLLMModel

    var typeHint: String {
        switch self {
        case .wakeWordEnabled, .contextAutoCompress:
            return "Bool"
        case .chatFontSize, .ttsSpeed, .sttSilenceTimeout:
            return "Double"
        case .ttsDiffusionSteps, .contextMaxSize:
            return "Int"
        case .wakeWord, .llmProvider, .llmModel, .supertonicVoice,
             .activeAgentName, .interactionMode, .fallbackLLMProvider,
             .fallbackLLMModel:
            return "String"
        }
    }
}

private enum APIKeyAccount: String, CaseIterable {
    case tavilyApiKey = "tavily_api_key"
    case falApiKey = "fal_api_key"

    var displayName: String {
        switch self {
        case .tavilyApiKey: return "tavily_api_key"
        case .falApiKey: return "fal_api_key"
        }
    }
}

private func maskAPIKey(_ value: String) -> String {
    guard value.count > 4 else { return "****" }
    return String(value.prefix(4)) + "****"
}

// MARK: - settings.list

@MainActor
final class SettingsListTool: BuiltInToolProtocol {
    let name = "settings.list"
    let category: ToolCategory = .sensitive
    let description = "앱 설정 목록과 현재 값을 조회합니다."
    let isBaseline = false

    private let settings: AppSettings
    private let keychainService: KeychainServiceProtocol

    init(settings: AppSettings, keychainService: KeychainServiceProtocol) {
        self.settings = settings
        self.keychainService = keychainService
    }

    var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [String: Any]()
        ]
    }

    func execute(arguments: [String: Any]) async -> ToolResult {
        var lines: [String] = []

        for key in SettingKey.allCases {
            let value = readSettingValue(key)
            lines.append("- \(key.rawValue): \(value) (\(key.typeHint))")
        }

        lines.append("")
        lines.append("[API Keys]")
        for account in APIKeyAccount.allCases {
            let stored = keychainService.load(account: account.rawValue)
            let display = stored.map { maskAPIKey($0) } ?? "(미설정)"
            lines.append("- \(account.displayName): \(display) (String)")
        }

        Log.tool.info("Listed all settings")
        return ToolResult(
            toolCallId: "",
            content: "설정 목록:\n\(lines.joined(separator: "\n"))"
        )
    }

    private func readSettingValue(_ key: SettingKey) -> String {
        switch key {
        case .wakeWordEnabled: return String(settings.wakeWordEnabled)
        case .wakeWord: return settings.wakeWord
        case .llmProvider: return settings.llmProvider
        case .llmModel: return settings.llmModel
        case .supertonicVoice: return settings.supertonicVoice
        case .ttsSpeed: return String(settings.ttsSpeed)
        case .ttsDiffusionSteps: return String(settings.ttsDiffusionSteps)
        case .chatFontSize: return String(settings.chatFontSize)
        case .sttSilenceTimeout: return String(settings.sttSilenceTimeout)
        case .contextAutoCompress: return String(settings.contextAutoCompress)
        case .contextMaxSize: return String(settings.contextMaxSize)
        case .activeAgentName: return settings.activeAgentName
        case .interactionMode: return settings.interactionMode
        case .fallbackLLMProvider: return settings.fallbackLLMProvider.isEmpty ? "(미설정)" : settings.fallbackLLMProvider
        case .fallbackLLMModel: return settings.fallbackLLMModel.isEmpty ? "(미설정)" : settings.fallbackLLMModel
        }
    }
}

// MARK: - settings.get

@MainActor
final class SettingsGetTool: BuiltInToolProtocol {
    let name = "settings.get"
    let category: ToolCategory = .sensitive
    let description = "지정한 설정 키의 현재 값을 조회합니다."
    let isBaseline = false

    private let settings: AppSettings
    private let keychainService: KeychainServiceProtocol

    init(settings: AppSettings, keychainService: KeychainServiceProtocol) {
        self.settings = settings
        self.keychainService = keychainService
    }

    var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "key": ["type": "string", "description": "조회할 설정 키"]
            ],
            "required": ["key"]
        ]
    }

    func execute(arguments: [String: Any]) async -> ToolResult {
        guard let key = arguments["key"] as? String, !key.isEmpty else {
            return ToolResult(toolCallId: "", content: "오류: key는 필수입니다.", isError: true)
        }

        // Check API keys first
        if let account = APIKeyAccount.allCases.first(where: { $0.rawValue == key }) {
            let stored = keychainService.load(account: account.rawValue)
            let display = stored.map { maskAPIKey($0) } ?? "(미설정)"
            Log.tool.info("Get setting (API key): \(key)")
            return ToolResult(toolCallId: "", content: "\(key) = \(display)")
        }

        guard let settingKey = SettingKey(rawValue: key) else {
            let allKeys = SettingKey.allCases.map(\.rawValue) + APIKeyAccount.allCases.map(\.rawValue)
            return ToolResult(
                toolCallId: "",
                content: "오류: 알 수 없는 설정 키 '\(key)'. 사용 가능한 키: \(allKeys.joined(separator: ", "))",
                isError: true
            )
        }

        let value = readSettingValue(settingKey)
        Log.tool.info("Get setting: \(key) = \(value)")
        return ToolResult(toolCallId: "", content: "\(key) = \(value)")
    }

    private func readSettingValue(_ key: SettingKey) -> String {
        switch key {
        case .wakeWordEnabled: return String(settings.wakeWordEnabled)
        case .wakeWord: return settings.wakeWord
        case .llmProvider: return settings.llmProvider
        case .llmModel: return settings.llmModel
        case .supertonicVoice: return settings.supertonicVoice
        case .ttsSpeed: return String(settings.ttsSpeed)
        case .ttsDiffusionSteps: return String(settings.ttsDiffusionSteps)
        case .chatFontSize: return String(settings.chatFontSize)
        case .sttSilenceTimeout: return String(settings.sttSilenceTimeout)
        case .contextAutoCompress: return String(settings.contextAutoCompress)
        case .contextMaxSize: return String(settings.contextMaxSize)
        case .activeAgentName: return settings.activeAgentName
        case .interactionMode: return settings.interactionMode
        case .fallbackLLMProvider: return settings.fallbackLLMProvider.isEmpty ? "(미설정)" : settings.fallbackLLMProvider
        case .fallbackLLMModel: return settings.fallbackLLMModel.isEmpty ? "(미설정)" : settings.fallbackLLMModel
        }
    }
}

// MARK: - settings.set

@MainActor
final class SettingsSetTool: BuiltInToolProtocol {
    let name = "settings.set"
    let category: ToolCategory = .sensitive
    let description = "지정한 설정 키의 값을 변경합니다."
    let isBaseline = false

    private let settings: AppSettings
    private let keychainService: KeychainServiceProtocol

    init(settings: AppSettings, keychainService: KeychainServiceProtocol) {
        self.settings = settings
        self.keychainService = keychainService
    }

    var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "key": ["type": "string", "description": "변경할 설정 키"],
                "value": ["type": "string", "description": "새 값 (문자열로 전달)"]
            ],
            "required": ["key", "value"]
        ]
    }

    func execute(arguments: [String: Any]) async -> ToolResult {
        guard let key = arguments["key"] as? String, !key.isEmpty else {
            return ToolResult(toolCallId: "", content: "오류: key는 필수입니다.", isError: true)
        }
        guard let value = arguments["value"] as? String else {
            return ToolResult(toolCallId: "", content: "오류: value는 필수입니다.", isError: true)
        }

        // Handle API keys
        if let account = APIKeyAccount.allCases.first(where: { $0.rawValue == key }) {
            do {
                if value.isEmpty {
                    try keychainService.delete(account: account.rawValue)
                    Log.tool.info("Deleted API key: \(key)")
                    return ToolResult(toolCallId: "", content: "\(key)를 삭제했습니다.")
                }
                try keychainService.save(account: account.rawValue, value: value)
                Log.tool.info("Saved API key: \(key)")
                return ToolResult(toolCallId: "", content: "\(key)를 저장했습니다.")
            } catch {
                Log.tool.error("Failed to save API key \(key): \(error.localizedDescription)")
                return ToolResult(toolCallId: "", content: "오류: API 키 저장 실패 — \(error.localizedDescription)", isError: true)
            }
        }

        guard let settingKey = SettingKey(rawValue: key) else {
            let allKeys = SettingKey.allCases.map(\.rawValue) + APIKeyAccount.allCases.map(\.rawValue)
            return ToolResult(
                toolCallId: "",
                content: "오류: 알 수 없는 설정 키 '\(key)'. 사용 가능한 키: \(allKeys.joined(separator: ", "))",
                isError: true
            )
        }

        return applySettingValue(settingKey, rawValue: value)
    }

    // MARK: - Value Parsing & Validation

    private func applySettingValue(_ key: SettingKey, rawValue: String) -> ToolResult {
        switch key {
        // Bool settings
        case .wakeWordEnabled:
            guard let parsed = parseBool(rawValue) else {
                return invalidTypeResult(key: key, expected: "Bool (true/false)")
            }
            settings.wakeWordEnabled = parsed
        case .contextAutoCompress:
            guard let parsed = parseBool(rawValue) else {
                return invalidTypeResult(key: key, expected: "Bool (true/false)")
            }
            settings.contextAutoCompress = parsed

        // Double settings with validation
        case .chatFontSize:
            guard let parsed = Double(rawValue) else {
                return invalidTypeResult(key: key, expected: "Double")
            }
            guard parsed >= 10.0, parsed <= 24.0 else {
                return ToolResult(toolCallId: "", content: "오류: chatFontSize는 10~24 범위여야 합니다.", isError: true)
            }
            settings.chatFontSize = parsed
        case .ttsSpeed:
            guard let parsed = Double(rawValue) else {
                return invalidTypeResult(key: key, expected: "Double")
            }
            guard parsed >= 0.5, parsed <= 2.0 else {
                return ToolResult(toolCallId: "", content: "오류: ttsSpeed는 0.5~2.0 범위여야 합니다.", isError: true)
            }
            settings.ttsSpeed = parsed
        case .sttSilenceTimeout:
            guard let parsed = Double(rawValue) else {
                return invalidTypeResult(key: key, expected: "Double")
            }
            guard parsed > 0 else {
                return ToolResult(toolCallId: "", content: "오류: sttSilenceTimeout는 0보다 커야 합니다.", isError: true)
            }
            settings.sttSilenceTimeout = parsed

        // Int settings with validation
        case .ttsDiffusionSteps:
            guard let parsed = Int(rawValue) else {
                return invalidTypeResult(key: key, expected: "Int")
            }
            guard parsed >= 1, parsed <= 10 else {
                return ToolResult(toolCallId: "", content: "오류: ttsDiffusionSteps는 1~10 범위여야 합니다.", isError: true)
            }
            settings.ttsDiffusionSteps = parsed
        case .contextMaxSize:
            guard let parsed = Int(rawValue) else {
                return invalidTypeResult(key: key, expected: "Int")
            }
            guard parsed > 0 else {
                return ToolResult(toolCallId: "", content: "오류: contextMaxSize는 0보다 커야 합니다.", isError: true)
            }
            settings.contextMaxSize = parsed

        // String settings
        case .wakeWord:
            guard !rawValue.isEmpty else {
                return ToolResult(toolCallId: "", content: "오류: wakeWord는 비어 있을 수 없습니다.", isError: true)
            }
            settings.wakeWord = rawValue
        case .llmProvider:
            guard LLMProvider(rawValue: rawValue) != nil else {
                let valid = LLMProvider.allCases.map(\.rawValue).joined(separator: ", ")
                return ToolResult(toolCallId: "", content: "오류: 유효하지 않은 llmProvider '\(rawValue)'. 가능한 값: \(valid)", isError: true)
            }
            settings.llmProvider = rawValue
        case .llmModel:
            guard !rawValue.isEmpty else {
                return ToolResult(toolCallId: "", content: "오류: llmModel은 비어 있을 수 없습니다.", isError: true)
            }
            settings.llmModel = rawValue
        case .supertonicVoice:
            guard SupertonicVoice(rawValue: rawValue) != nil else {
                let valid = SupertonicVoice.allCases.map(\.rawValue).joined(separator: ", ")
                return ToolResult(toolCallId: "", content: "오류: 유효하지 않은 supertonicVoice '\(rawValue)'. 가능한 값: \(valid)", isError: true)
            }
            settings.supertonicVoice = rawValue
        case .activeAgentName:
            guard !rawValue.isEmpty else {
                return ToolResult(toolCallId: "", content: "오류: activeAgentName은 비어 있을 수 없습니다.", isError: true)
            }
            settings.activeAgentName = rawValue
        case .interactionMode:
            guard InteractionMode(rawValue: rawValue) != nil else {
                return ToolResult(toolCallId: "", content: "오류: 유효하지 않은 interactionMode '\(rawValue)'. 가능한 값: voiceAndText, textOnly", isError: true)
            }
            settings.interactionMode = rawValue
        case .fallbackLLMProvider:
            if !rawValue.isEmpty {
                guard LLMProvider(rawValue: rawValue) != nil else {
                    let valid = LLMProvider.allCases.map(\.rawValue).joined(separator: ", ")
                    return ToolResult(toolCallId: "", content: "오류: 유효하지 않은 fallbackLLMProvider '\(rawValue)'. 가능한 값: \(valid) (비우려면 빈 문자열)", isError: true)
                }
            }
            settings.fallbackLLMProvider = rawValue
        case .fallbackLLMModel:
            settings.fallbackLLMModel = rawValue
        }

        Log.tool.info("Setting changed: \(key.rawValue) = \(rawValue)")
        return ToolResult(toolCallId: "", content: "\(key.rawValue)를 '\(rawValue)'(으)로 변경했습니다.")
    }

    private func parseBool(_ value: String) -> Bool? {
        switch value.lowercased() {
        case "true", "1", "yes": return true
        case "false", "0", "no": return false
        default: return nil
        }
    }

    private func invalidTypeResult(key: SettingKey, expected: String) -> ToolResult {
        ToolResult(
            toolCallId: "",
            content: "오류: \(key.rawValue)의 값은 \(expected) 형식이어야 합니다.",
            isError: true
        )
    }
}
