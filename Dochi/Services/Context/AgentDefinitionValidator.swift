import Foundation
import os

// MARK: - AgentDefinitionValidator

/// AgentDefinition 필수 필드 검증, permissionProfile 유효성, toolGroups 존재 확인.
@MainActor
final class AgentDefinitionValidator {

    /// 등록된 toolGroup 이름 (ToolRegistry에서 주입)
    private let knownToolGroups: Set<String>

    /// 등록된 에이전트 ID (중복 검사용)
    private let existingAgentIds: Set<String>

    init(knownToolGroups: Set<String> = [], existingAgentIds: Set<String> = []) {
        self.knownToolGroups = knownToolGroups
        self.existingAgentIds = existingAgentIds
    }

    // MARK: - Validate

    /// 에이전트 정의를 검증하고 오류 목록을 반환한다.
    func validate(_ definition: AgentDefinition) -> [AgentValidationError] {
        var errors: [AgentValidationError] = []

        // 1. 필수 필드
        if definition.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append(.emptyName)
        }

        if definition.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append(.emptyId)
        }

        // 2. 이름 형식 (특수문자 제한)
        if !definition.name.isEmpty && !isValidAgentName(definition.name) {
            errors.append(.invalidNameFormat(definition.name))
        }

        // 3. permissionProfile 유효성
        if let profile = definition.permissionProfile {
            errors.append(contentsOf: validatePermissionProfile(profile))
        }

        // 4. toolGroups 존재 확인
        if !knownToolGroups.isEmpty {
            for group in definition.toolGroups {
                let normalized = group.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if !knownToolGroups.contains(normalized) {
                    errors.append(.unknownToolGroup(normalized))
                }
            }
        }

        // 5. subagent 검증
        for subagent in definition.subagents {
            if subagent.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                errors.append(.subagentEmptyId)
            }
            if let profile = subagent.permissionProfile {
                errors.append(contentsOf: validatePermissionProfile(profile))
            }
            // subagent toolGroups 존재 확인
            if !knownToolGroups.isEmpty {
                for group in subagent.toolGroups {
                    let normalized = group.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    if !knownToolGroups.contains(normalized) {
                        errors.append(.subagentUnknownToolGroup(subagentId: subagent.id, group: normalized))
                    }
                }
            }
        }

        // 6. version 유효성
        if definition.version < 1 {
            errors.append(.invalidVersion(definition.version))
        }

        // 7. wakeWord 중복/형식 검증
        if let wakeWord = definition.wakeWord {
            if wakeWord.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                errors.append(.emptyWakeWord)
            }
        }

        // 8. memoryPolicy 검증
        if let policy = definition.memoryPolicy {
            if !policy.personalMemoryAccess && !policy.workspaceMemoryAccess && !policy.agentMemoryAccess {
                errors.append(.noMemoryAccess)
            }
        }

        return errors
    }

    /// 에이전트 정의가 유효한지 간단히 확인
    func isValid(_ definition: AgentDefinition) -> Bool {
        validate(definition).isEmpty
    }

    // MARK: - Private

    private func isValidAgentName(_ name: String) -> Bool {
        // 허용: 한글, 영문, 숫자, 공백, 하이픈, 언더스코어
        let pattern = "^[\\p{L}\\p{N}\\s\\-_]+$"
        return name.range(of: pattern, options: .regularExpression) != nil
    }

    private func validatePermissionProfile(_ profile: PermissionProfile) -> [AgentValidationError] {
        var errors: [AgentValidationError] = []

        // restricted가 allow이면 보안 경고
        if profile.restricted == .allow {
            errors.append(.restrictedToolsAllowed)
        }

        // safe가 deny이면 에이전트가 아무것도 못함
        if profile.safe == .deny {
            errors.append(.safeToolsDenied)
        }

        return errors
    }
}

// MARK: - AgentValidationError

enum AgentValidationError: LocalizedError, Equatable, Sendable {
    case emptyName
    case emptyId
    case invalidNameFormat(String)
    case unknownToolGroup(String)
    case subagentEmptyId
    case subagentUnknownToolGroup(subagentId: String, group: String)
    case invalidVersion(Int)
    case emptyWakeWord
    case noMemoryAccess
    case restrictedToolsAllowed
    case safeToolsDenied

    var errorDescription: String? {
        switch self {
        case .emptyName: return "에이전트 이름이 비어있습니다."
        case .emptyId: return "에이전트 ID가 비어있습니다."
        case .invalidNameFormat(let name): return "에이전트 이름 형식이 유효하지 않습니다: '\(name)'"
        case .unknownToolGroup(let group): return "등록되지 않은 toolGroup: '\(group)'"
        case .subagentEmptyId: return "서브에이전트 ID가 비어있습니다."
        case .subagentUnknownToolGroup(let subagentId, let group): return "서브에이전트 '\(subagentId)'의 등록되지 않은 toolGroup: '\(group)'"
        case .invalidVersion(let v): return "유효하지 않은 버전: \(v) (1 이상이어야 합니다)"
        case .emptyWakeWord: return "wakeWord가 비어있습니다."
        case .noMemoryAccess: return "모든 메모리 접근이 비활성화되어 있습니다."
        case .restrictedToolsAllowed: return "restricted 도구가 무조건 허용 상태입니다. 보안에 주의하세요."
        case .safeToolsDenied: return "safe 도구가 거부 상태이면 에이전트가 동작할 수 없습니다."
        }
    }
}
