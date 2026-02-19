import Foundation

enum CapabilityPackID: String, CaseIterable, Sendable {
    case chatCore = "chat.core"
    case codingRead = "coding.read"
}

struct CapabilityRoute: Equatable, Sendable {
    let primary: CapabilityPackID
    let secondary: CapabilityPackID?

    var packIDs: [CapabilityPackID] {
        if let secondary {
            return [primary, secondary]
        }
        return [primary]
    }
}

/// Static capability router used to compile a bounded tool menu.
/// This is intentionally lightweight for v2 foundation rollout.
struct CapabilityRouter: Sendable {
    struct Pack: Sendable {
        let id: CapabilityPackID
        let displayName: String
        let toolNames: Set<String>
    }

    private let packs: [CapabilityPackID: Pack]

    init(packs: [Pack] = CapabilityRouter.defaultPacks) {
        self.packs = Dictionary(uniqueKeysWithValues: packs.map { ($0.id, $0) })
    }

    func route(for permissions: [String]) -> CapabilityRoute {
        let permissionSet = Set(permissions)
        if permissionSet.contains(ToolCategory.restricted.rawValue) {
            return CapabilityRoute(primary: .chatCore, secondary: .codingRead)
        }
        return CapabilityRoute(primary: .chatCore, secondary: nil)
    }

    func label(for route: CapabilityRoute) -> String {
        route.packIDs.compactMap { packs[$0]?.displayName }.joined(separator: " + ")
    }

    func allowedToolNames(for route: CapabilityRoute) -> Set<String> {
        var names = Set<String>()
        for packID in route.packIDs {
            guard let pack = packs[packID] else { continue }
            names.formUnion(pack.toolNames)
        }
        return names
    }

    @MainActor
    func filter(
        tools: [any BuiltInToolProtocol],
        enabledToolNames: Set<String>,
        permissions: [String]
    ) -> (filteredTools: [any BuiltInToolProtocol], selectedLabel: String) {
        let selectedRoute = route(for: permissions)
        let allowed = allowedToolNames(for: selectedRoute)
        let label = label(for: selectedRoute)
        let filtered = tools.filter { tool in
            allowed.contains(tool.name) || enabledToolNames.contains(tool.name)
        }
        if filtered.isEmpty {
            return (tools, label)
        }
        return (filtered, label)
    }
}

private extension CapabilityRouter {
    static let defaultPacks: [Pack] = [
        Pack(
            id: .chatCore,
            displayName: "Chat Core",
            toolNames: [
                "tools.list",
                "tools.enable",
                "tools.enable_ttl",
                "tools.reset",
                "create_reminder",
                "list_reminders",
                "complete_reminder",
                "set_alarm",
                "list_alarms",
                "cancel_alarm",
                "save_memory",
                "update_memory",
                "set_current_user",
                "web_search",
                "generate_image",
                "print_image",
                "set_timer",
                "list_timers",
                "cancel_timer",
                "calendar.list_events",
                "calculate",
                "datetime",
                "app.guide",
            ]
        ),
        Pack(
            id: .codingRead,
            displayName: "Coding Read",
            toolNames: [
                "git.status",
                "git.log",
                "git.diff",
                "coding.review",
            ]
        ),
    ]
}
