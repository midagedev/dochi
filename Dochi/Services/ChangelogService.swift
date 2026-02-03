import Foundation

/// 버전 변경 감지 및 changelog 관리 서비스
final class ChangelogService {
    private let userDefaults: UserDefaults
    private let bundle: Bundle

    private enum Keys {
        static let lastSeenVersion = "changelog.lastSeenVersion"
    }

    init(userDefaults: UserDefaults = .standard, bundle: Bundle = .main) {
        self.userDefaults = userDefaults
        self.bundle = bundle
    }

    /// 현재 앱 버전 (예: "1.0.0")
    var currentVersion: String {
        bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }

    /// 현재 빌드 번호 (예: "1")
    var currentBuild: String {
        bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

    /// 마지막으로 본 버전
    var lastSeenVersion: String? {
        userDefaults.string(forKey: Keys.lastSeenVersion)
    }

    /// 버전 업데이트 후 첫 실행인지 확인
    var hasNewVersion: Bool {
        guard let lastSeen = lastSeenVersion else {
            // 처음 설치한 경우는 새 버전으로 취급하지 않음
            return false
        }
        return compareVersions(currentVersion, lastSeen) == .orderedDescending
    }

    /// 앱을 처음 설치한 경우인지 확인
    var isFirstLaunch: Bool {
        lastSeenVersion == nil
    }

    /// 현재 버전을 본 것으로 표시
    func markCurrentVersionAsSeen() {
        userDefaults.set(currentVersion, forKey: Keys.lastSeenVersion)
    }

    /// Changelog 내용 로드
    func loadChangelog() -> String {
        guard let url = bundle.url(forResource: "CHANGELOG", withExtension: "md"),
              let content = try? String(contentsOf: url, encoding: .utf8) else {
            return "Changelog를 불러올 수 없습니다."
        }
        return content
    }

    /// 현재 버전의 변경사항만 추출
    func loadCurrentVersionChanges() -> String {
        let full = loadChangelog()
        return extractVersionSection(from: full, version: currentVersion)
    }

    // MARK: - Private

    /// 버전 문자열 비교 (semantic versioning)
    private func compareVersions(_ v1: String, _ v2: String) -> ComparisonResult {
        let components1 = v1.split(separator: ".").compactMap { Int($0) }
        let components2 = v2.split(separator: ".").compactMap { Int($0) }

        let maxCount = max(components1.count, components2.count)

        for i in 0..<maxCount {
            let c1 = i < components1.count ? components1[i] : 0
            let c2 = i < components2.count ? components2[i] : 0

            if c1 > c2 { return .orderedDescending }
            if c1 < c2 { return .orderedAscending }
        }
        return .orderedSame
    }

    /// 특정 버전 섹션 추출
    private func extractVersionSection(from changelog: String, version: String) -> String {
        let lines = changelog.components(separatedBy: .newlines)
        var result: [String] = []
        var capturing = false

        for line in lines {
            // ## v1.0.0 형식의 버전 헤더 감지
            if line.hasPrefix("## ") {
                if capturing {
                    // 다음 버전 섹션 시작하면 중단
                    break
                }
                if line.contains(version) {
                    capturing = true
                    result.append(line)
                }
            } else if capturing {
                result.append(line)
            }
        }

        return result.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
