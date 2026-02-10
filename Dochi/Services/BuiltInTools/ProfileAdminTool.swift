import Foundation
import os

/// 프로필 관리 도구 (create, merge, rename, add_alias)
@MainActor
final class ProfileAdminTool: BuiltInTool {
    var contextService: (any ContextServiceProtocol)?
    weak var settings: AppSettings?
    var conversationService: (any ConversationServiceProtocol)?

    nonisolated var tools: [MCPToolInfo] {
        [
            MCPToolInfo(
                id: "builtin:profile.create",
                name: "profile.create",
                description: "Create a new user profile.",
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "name": ["type": "string"],
                        "aliases": ["type": "array", "items": ["type": "string"]],
                        "description": ["type": "string"]
                    ],
                    "required": ["name"]
                ]
            ),
            MCPToolInfo(
                id: "builtin:profile.add_alias",
                name: "profile.add_alias",
                description: "Add an alias to an existing profile by name.",
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "name": ["type": "string"],
                        "alias": ["type": "string"]
                    ],
                    "required": ["name", "alias"]
                ]
            ),
            MCPToolInfo(
                id: "builtin:profile.rename",
                name: "profile.rename",
                description: "Rename a profile.",
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "from": ["type": "string"],
                        "to": ["type": "string"]
                    ],
                    "required": ["from", "to"]
                ]
            ),
            MCPToolInfo(
                id: "builtin:profile.merge",
                name: "profile.merge",
                description: "Merge source profile into target by name. merge_memory: append|skip|replace",
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "source": ["type": "string"],
                        "target": ["type": "string"],
                        "merge_memory": ["type": "string", "enum": ["append", "skip", "replace"]]
                    ],
                    "required": ["source", "target", "merge_memory"]
                ]
            )
        ]
    }

    func callTool(name: String, arguments: [String: Any]) async throws -> MCPToolResult {
        guard let contextService else {
            return MCPToolResult(content: "ContextService not available", isError: true)
        }
        switch name {
        case "profile.create":
            return createProfile(context: contextService, args: arguments)
        case "profile.add_alias":
            return addAlias(context: contextService, args: arguments)
        case "profile.rename":
            return renameProfile(context: contextService, args: arguments)
        case "profile.merge":
            return mergeProfiles(context: contextService, args: arguments)
        default:
            throw BuiltInToolError.unknownTool(name)
        }
    }

    // MARK: - Handlers

    private func createProfile(context: any ContextServiceProtocol, args: [String: Any]) -> MCPToolResult {
        guard let name = args["name"] as? String, !name.isEmpty else {
            return MCPToolResult(content: "name is required", isError: true)
        }
        let aliases = (args["aliases"] as? [Any])?.compactMap { $0 as? String } ?? []
        let description = (args["description"] as? String) ?? ""
        var profiles = context.loadProfiles()
        if profiles.contains(where: { $0.allNames.contains { $0.caseInsensitiveCompare(name) == .orderedSame } }) {
            return MCPToolResult(content: "Profile already exists: \(name)", isError: true)
        }
        let newProfile = UserProfile(name: name, aliases: aliases, description: description)
        profiles.append(newProfile)
        context.saveProfiles(profiles)
        return MCPToolResult(content: "Created profile '\(name)' (id=\(newProfile.id.uuidString))", isError: false)
    }

    private func addAlias(context: any ContextServiceProtocol, args: [String: Any]) -> MCPToolResult {
        guard let name = args["name"] as? String, let alias = args["alias"] as? String, !name.isEmpty, !alias.isEmpty else {
            return MCPToolResult(content: "name and alias are required", isError: true)
        }
        var profiles = context.loadProfiles()
        guard let idx = resolveProfileIndex(profiles: profiles, by: name) else {
            return MCPToolResult(content: "Profile not found: \(name)", isError: true)
        }
        if !profiles[idx].aliases.contains(where: { $0.caseInsensitiveCompare(alias) == .orderedSame }) {
            profiles[idx].aliases.append(alias)
            context.saveProfiles(profiles)
        }
        return MCPToolResult(content: "Added alias '\(alias)' to \(profiles[idx].name)", isError: false)
    }

    private func renameProfile(context: any ContextServiceProtocol, args: [String: Any]) -> MCPToolResult {
        guard let from = args["from"] as? String, let to = args["to"] as? String, !from.isEmpty, !to.isEmpty else {
            return MCPToolResult(content: "from and to are required", isError: true)
        }
        var profiles = context.loadProfiles()
        guard let idx = resolveProfileIndex(profiles: profiles, by: from) else {
            return MCPToolResult(content: "Profile not found: \(from)", isError: true)
        }
        profiles[idx].name = to
        context.saveProfiles(profiles)
        return MCPToolResult(content: "Renamed profile '\(from)' -> '\(to)'", isError: false)
    }

    private func mergeProfiles(context: any ContextServiceProtocol, args: [String: Any]) -> MCPToolResult {
        guard let sourceName = args["source"] as? String,
              let targetName = args["target"] as? String,
              let strategy = args["merge_memory"] as? String else {
            return MCPToolResult(content: "source, target, merge_memory are required", isError: true)
        }
        guard strategy == "append" || strategy == "skip" || strategy == "replace" else {
            return MCPToolResult(content: "merge_memory must be append|skip|replace", isError: true)
        }
        var profiles = context.loadProfiles()
        guard let sIdx = resolveProfileIndex(profiles: profiles, by: sourceName) else {
            return MCPToolResult(content: "Source profile not found: \(sourceName)", isError: true)
        }
        guard let tIdx = resolveProfileIndex(profiles: profiles, by: targetName) else {
            return MCPToolResult(content: "Target profile not found: \(targetName)", isError: true)
        }
        let source = profiles[sIdx]
        let target = profiles[tIdx]

        // Merge aliases and description (keep target description if non-empty)
        let newAliases = Array(Set(target.aliases + source.allNames.filter { $0.caseInsensitiveCompare(target.name) != .orderedSame }))
        profiles[tIdx].aliases = newAliases
        if profiles[tIdx].description.isEmpty, !source.description.isEmpty {
            profiles[tIdx].description = source.description
        }

        // Merge memories
        let sMem = context.loadUserMemory(userId: source.id)
        let tMem = context.loadUserMemory(userId: target.id)
        let mergedMem: String
        switch strategy {
        case "append":
            if tMem.isEmpty { mergedMem = sMem }
            else if sMem.isEmpty { mergedMem = tMem }
            else { mergedMem = tMem + "\n" + sMem }
        case "skip":
            mergedMem = tMem
        case "replace":
            mergedMem = sMem
        default:
            mergedMem = tMem
        }
        context.saveUserMemory(userId: target.id, content: mergedMem)
        // Clear source memory file (non-destructive delete)
        context.saveUserMemory(userId: source.id, content: "")

        // Remove source profile
        profiles.remove(at: sIdx)
        context.saveProfiles(profiles)

        // Migrate conversations' userId from source to target (best-effort)
        if let conversationService {
            let all = conversationService.list()
            for var c in all where c.userId == source.id.uuidString {
                c.userId = target.id.uuidString
                conversationService.save(c)
            }
        }

        Log.tool.info("프로필 병합: \(source.name) -> \(target.name), strategy=\(strategy)")
        return MCPToolResult(content: "Merged '\(source.name)' into '\(target.name)' (memory=\(strategy))", isError: false)
    }

    // MARK: - Helpers

    private func resolveProfileIndex(profiles: [UserProfile], by name: String) -> Int? {
        profiles.firstIndex { profile in
            profile.allNames.contains { n in
                n.localizedCaseInsensitiveContains(name) || name.localizedCaseInsensitiveContains(n)
            }
        }
    }
}
