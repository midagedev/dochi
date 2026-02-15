import Foundation

// MARK: - DeviceType

enum DeviceType: String, Codable, CaseIterable, Sendable {
    case desktop
    case mobile
    case cli

    var displayName: String {
        switch self {
        case .desktop: return "데스크탑"
        case .mobile: return "모바일"
        case .cli: return "CLI"
        }
    }

    var iconName: String {
        switch self {
        case .desktop: return "desktopcomputer"
        case .mobile: return "iphone"
        case .cli: return "terminal"
        }
    }

    var defaultPriority: Int {
        switch self {
        case .desktop: return 0
        case .mobile: return 1
        case .cli: return 2
        }
    }
}

// MARK: - DevicePlatform

enum DevicePlatform: String, Codable, CaseIterable, Sendable {
    case macos
    case ios
    case cli

    var displayName: String {
        switch self {
        case .macos: return "macOS"
        case .ios: return "iOS"
        case .cli: return "CLI"
        }
    }
}

// MARK: - DeviceCapabilities

struct DeviceCapabilities: Codable, Sendable, Equatable {
    var supportsVoice: Bool
    var supportsTTS: Bool
    var supportsNotifications: Bool
    var supportsTools: Bool

    static let desktop = DeviceCapabilities(
        supportsVoice: true,
        supportsTTS: true,
        supportsNotifications: true,
        supportsTools: true
    )

    static let mobile = DeviceCapabilities(
        supportsVoice: true,
        supportsTTS: true,
        supportsNotifications: true,
        supportsTools: false
    )

    static let cli = DeviceCapabilities(
        supportsVoice: false,
        supportsTTS: false,
        supportsNotifications: false,
        supportsTools: true
    )
}

// MARK: - DeviceInfo

struct DeviceInfo: Codable, Identifiable, Sendable, Equatable {
    static let onlineThreshold: TimeInterval = 120

    let id: UUID
    var name: String
    var deviceType: DeviceType
    var platform: DevicePlatform
    var lastSeen: Date
    var isCurrentDevice: Bool
    var priority: Int
    var capabilities: DeviceCapabilities

    var isOnline: Bool {
        Date().timeIntervalSince(lastSeen) < Self.onlineThreshold
    }

    var statusText: String {
        if isCurrentDevice {
            return "이 디바이스"
        }
        if isOnline {
            return "온라인"
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: lastSeen, relativeTo: Date())
    }

    init(
        id: UUID = UUID(),
        name: String,
        deviceType: DeviceType,
        platform: DevicePlatform,
        lastSeen: Date = Date(),
        isCurrentDevice: Bool = false,
        priority: Int? = nil,
        capabilities: DeviceCapabilities? = nil
    ) {
        self.id = id
        self.name = name
        self.deviceType = deviceType
        self.platform = platform
        self.lastSeen = lastSeen
        self.isCurrentDevice = isCurrentDevice
        self.priority = priority ?? deviceType.defaultPriority
        self.capabilities = capabilities ?? {
            switch deviceType {
            case .desktop: return .desktop
            case .mobile: return .mobile
            case .cli: return .cli
            }
        }()
    }
}

// MARK: - DeviceSelectionPolicy

enum DeviceSelectionPolicy: String, Codable, CaseIterable, Sendable {
    case priorityBased
    case lastActive
    case manual

    var displayName: String {
        switch self {
        case .priorityBased: return "우선순위 기반"
        case .lastActive: return "최근 활성"
        case .manual: return "수동 선택"
        }
    }

    var description: String {
        switch self {
        case .priorityBased: return "우선순위가 높은 디바이스가 응답합니다. 드래그로 순서를 변경할 수 있습니다."
        case .lastActive: return "가장 최근에 활동한 디바이스가 응답합니다."
        case .manual: return "지정된 디바이스만 응답합니다."
        }
    }

    var iconName: String {
        switch self {
        case .priorityBased: return "list.number"
        case .lastActive: return "clock.arrow.circlepath"
        case .manual: return "hand.tap"
        }
    }
}

// MARK: - DeviceNegotiationResult

enum DeviceNegotiationResult: Sendable, Equatable {
    case thisDevice
    case otherDevice(DeviceInfo)
    case noDeviceAvailable
    case singleDevice

    var displayText: String {
        switch self {
        case .thisDevice: return "이 디바이스가 응답"
        case .otherDevice(let device): return "\(device.name)이(가) 응답"
        case .noDeviceAvailable: return "응답 가능한 디바이스 없음"
        case .singleDevice: return "단일 디바이스"
        }
    }
}
