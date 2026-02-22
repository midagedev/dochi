import Foundation

struct GitRepositoryInsight: Sendable, Codable, Equatable {
    let workDomain: String
    let workDomainConfidence: Double
    let workDomainReason: String
    let path: String
    let name: String
    let branch: String
    let originURL: String?
    let remoteHost: String?
    let remoteOwner: String?
    let remoteRepository: String?
    let lastCommitEpoch: Int?
    let lastCommitISO8601: String?
    let lastCommitRelative: String
    let lastCommitShortHash: String?
    let lastCommitSubject: String?
    let upstreamLastCommitEpoch: Int?
    let upstreamLastCommitISO8601: String?
    let upstreamLastCommitRelative: String
    let daysSinceLastCommit: Int?
    let recentCommitCount30d: Int
    let changedFileCount: Int
    let untrackedFileCount: Int
    let aheadCount: Int?
    let behindCount: Int?
    let score: Int

    init(
        workDomain: String,
        workDomainConfidence: Double,
        workDomainReason: String,
        path: String,
        name: String,
        branch: String,
        originURL: String?,
        remoteHost: String?,
        remoteOwner: String?,
        remoteRepository: String?,
        lastCommitEpoch: Int?,
        lastCommitISO8601: String?,
        lastCommitRelative: String,
        lastCommitShortHash: String? = nil,
        lastCommitSubject: String? = nil,
        upstreamLastCommitEpoch: Int?,
        upstreamLastCommitISO8601: String?,
        upstreamLastCommitRelative: String,
        daysSinceLastCommit: Int?,
        recentCommitCount30d: Int,
        changedFileCount: Int,
        untrackedFileCount: Int,
        aheadCount: Int?,
        behindCount: Int?,
        score: Int
    ) {
        self.workDomain = workDomain
        self.workDomainConfidence = workDomainConfidence
        self.workDomainReason = workDomainReason
        self.path = path
        self.name = name
        self.branch = branch
        self.originURL = originURL
        self.remoteHost = remoteHost
        self.remoteOwner = remoteOwner
        self.remoteRepository = remoteRepository
        self.lastCommitEpoch = lastCommitEpoch
        self.lastCommitISO8601 = lastCommitISO8601
        self.lastCommitRelative = lastCommitRelative
        self.lastCommitShortHash = lastCommitShortHash
        self.lastCommitSubject = lastCommitSubject
        self.upstreamLastCommitEpoch = upstreamLastCommitEpoch
        self.upstreamLastCommitISO8601 = upstreamLastCommitISO8601
        self.upstreamLastCommitRelative = upstreamLastCommitRelative
        self.daysSinceLastCommit = daysSinceLastCommit
        self.recentCommitCount30d = recentCommitCount30d
        self.changedFileCount = changedFileCount
        self.untrackedFileCount = untrackedFileCount
        self.aheadCount = aheadCount
        self.behindCount = behindCount
        self.score = score
    }
}

struct GitRepositoryActivityMetrics: Sendable, Equatable {
    let daysSinceLastCommit: Int?
    let recentCommitCount30d: Int
    let changedFileCount: Int
    let untrackedFileCount: Int
    let aheadCount: Int?
}

enum GitRepositoryInsightScorer {
    static func score(_ metrics: GitRepositoryActivityMetrics) -> Int {
        let days = metrics.daysSinceLastCommit ?? 3650
        let recencyScore: Int
        switch days {
        case ..<1:
            recencyScore = 40
        case 1...3:
            recencyScore = 32
        case 4...7:
            recencyScore = 24
        case 8...14:
            recencyScore = 16
        case 15...30:
            recencyScore = 8
        case 31...90:
            recencyScore = 3
        default:
            recencyScore = 0
        }

        let commitVelocityScore = min(metrics.recentCommitCount30d, 30) * 2
        let dirtyScore = min(metrics.changedFileCount + metrics.untrackedFileCount, 15)
        let untrackedBonus = min(metrics.untrackedFileCount, 5)
        let aheadBonus = min(max(metrics.aheadCount ?? 0, 0), 5) * 2

        return recencyScore + commitVelocityScore + dirtyScore + untrackedBonus + aheadBonus
    }
}

enum GitRepositoryInsightScanner {
    private static let maxScanDepth = 5
    private static let maxDiscoveredRoots = 300
    private static let skipDirectoryNames: Set<String> = [
        ".git",
        ".build",
        "build",
        "dist",
        "node_modules",
        "Pods",
        "DerivedData",
        "Library",
        ".cache",
        ".swiftpm",
    ]

    static func discover(searchPaths: [String]?, limit: Int) -> [GitRepositoryInsight] {
        let normalizedLimit = max(1, min(200, limit))
        let paths = normalizedSearchPaths(searchPaths)
        guard !paths.isEmpty else { return [] }
        let personalIdentity = detectPersonalIdentity()

        var discoveredRoots: Set<String> = []
        for path in paths {
            if let root = resolveGitTopLevel(path: path) {
                discoveredRoots.insert(root)
            }
            discoveredRoots.formUnion(scanForGitRoots(basePath: path))
            if discoveredRoots.count >= maxDiscoveredRoots {
                break
            }
        }

        guard !discoveredRoots.isEmpty else { return [] }

        let insights = discoveredRoots.compactMap { path in
            insightForRepository(path: path, personalIdentity: personalIdentity)
        }
        let sorted = insights.sorted { lhs, rhs in
            if lhs.score != rhs.score {
                return lhs.score > rhs.score
            }
            let lhsEpoch = lhs.lastCommitEpoch ?? Int.min
            let rhsEpoch = rhs.lastCommitEpoch ?? Int.min
            if lhsEpoch != rhsEpoch {
                return lhsEpoch > rhsEpoch
            }
            if lhs.recentCommitCount30d != rhs.recentCommitCount30d {
                return lhs.recentCommitCount30d > rhs.recentCommitCount30d
            }
            return lhs.path < rhs.path
        }

        return Array(sorted.prefix(normalizedLimit))
    }

    private static func normalizedSearchPaths(_ input: [String]?) -> [String] {
        let rawPaths: [String]
        if let input, !input.isEmpty {
            rawPaths = input
        } else {
            rawPaths = defaultSearchPaths()
        }

        var seen = Set<String>()
        var normalized: [String] = []
        for rawPath in rawPaths {
            let expanded = expandTilde(rawPath).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !expanded.isEmpty else { continue }
            let standardized = URL(fileURLWithPath: expanded).standardizedFileURL.path
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: standardized, isDirectory: &isDir), isDir.boolValue else {
                continue
            }
            if seen.insert(standardized).inserted {
                normalized.append(standardized)
            }
        }
        return normalized
    }

    private static func defaultSearchPaths() -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [
            FileManager.default.currentDirectoryPath,
            "\(home)/repo",
            "\(home)/repos",
            "\(home)/workspace",
            "\(home)/work",
            "\(home)/projects",
            "\(home)/src",
        ]
    }

    private static func expandTilde(_ path: String) -> String {
        guard path.hasPrefix("~") else { return path }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path == "~" {
            return home
        }
        if path.hasPrefix("~/") {
            return home + "/" + path.dropFirst(2)
        }
        return path
    }

    private static func scanForGitRoots(basePath: String) -> Set<String> {
        let baseURL = URL(fileURLWithPath: basePath)
        guard let enumerator = FileManager.default.enumerator(
            at: baseURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsPackageDescendants]
        ) else {
            return []
        }

        let baseDepth = baseURL.pathComponents.count
        var roots = Set<String>()

        for case let url as URL in enumerator {
            let depth = url.pathComponents.count - baseDepth
            if depth > maxScanDepth {
                enumerator.skipDescendants()
                continue
            }

            let name = url.lastPathComponent
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            let isDir = values?.isDirectory == true
            let isSymlink = values?.isSymbolicLink == true

            if isSymlink {
                enumerator.skipDescendants()
                continue
            }

            if isDir, name.hasPrefix("."), name != ".git" {
                enumerator.skipDescendants()
                continue
            }

            if isDir, skipDirectoryNames.contains(name), name != ".git" {
                enumerator.skipDescendants()
                continue
            }

            if name == ".git" {
                roots.insert(url.deletingLastPathComponent().standardizedFileURL.path)
                if isDir {
                    enumerator.skipDescendants()
                }
                if roots.count >= maxDiscoveredRoots {
                    break
                }
            }
        }

        return roots
    }

    private static func insightForRepository(path: String, personalIdentity: Set<String>) -> GitRepositoryInsight? {
        guard FileManager.default.fileExists(atPath: path) else { return nil }

        let name = URL(fileURLWithPath: path).lastPathComponent
        let branch = gitOutput(repoPath: path, args: ["rev-parse", "--abbrev-ref", "HEAD"]) ?? "unknown"
        let originURL = gitOutput(repoPath: path, args: ["remote", "get-url", "origin"])
        let remoteInfo = parseRemoteInfo(originURL)
        let workDomainClassification = classifyWorkDomain(
            remoteInfo: remoteInfo,
            personalIdentity: personalIdentity
        )
        let lastCommitHeadline = gitOutput(repoPath: path, args: ["log", "-1", "--format=%h%x1f%s"])
        let parsedHeadline = parseLastCommitHeadline(lastCommitHeadline)
        let lastCommitEpoch = gitOutput(repoPath: path, args: ["log", "-1", "--format=%ct"]).flatMap { Int($0) }
        let upstreamLastCommitEpoch = gitOutput(repoPath: path, args: ["log", "-1", "--format=%ct", "@{upstream}"]).flatMap { Int($0) }
        let recentCommitCount30d = gitOutput(repoPath: path, args: ["rev-list", "--count", "--since=30 days ago", "HEAD"]).flatMap { Int($0) } ?? 0

        let statusLines = (gitOutput(repoPath: path, args: ["status", "--porcelain"]) ?? "")
            .split(whereSeparator: \.isNewline)
            .map(String.init)
        let changedFileCount = statusLines.filter { !$0.hasPrefix("??") }.count
        let untrackedFileCount = statusLines.filter { $0.hasPrefix("??") }.count

        let aheadBehindOutput = gitOutput(repoPath: path, args: ["rev-list", "--left-right", "--count", "@{upstream}...HEAD"])
        let (aheadCount, behindCount) = parseAheadBehind(aheadBehindOutput)

        let daysSinceLastCommit: Int? = lastCommitEpoch.map { epoch in
            max(0, Int((Date().timeIntervalSince1970 - TimeInterval(epoch)) / 86_400))
        }

        let metrics = GitRepositoryActivityMetrics(
            daysSinceLastCommit: daysSinceLastCommit,
            recentCommitCount30d: recentCommitCount30d,
            changedFileCount: changedFileCount,
            untrackedFileCount: untrackedFileCount,
            aheadCount: aheadCount
        )
        let score = GitRepositoryInsightScorer.score(metrics)

        return GitRepositoryInsight(
            workDomain: workDomainClassification.domain,
            workDomainConfidence: workDomainClassification.confidence,
            workDomainReason: workDomainClassification.reason,
            path: path,
            name: name,
            branch: branch,
            originURL: originURL,
            remoteHost: remoteInfo.host,
            remoteOwner: remoteInfo.owner,
            remoteRepository: remoteInfo.repository,
            lastCommitEpoch: lastCommitEpoch,
            lastCommitISO8601: lastCommitEpoch.map(iso8601(epoch:)),
            lastCommitRelative: relativeTimeDescription(daysSinceLastCommit: daysSinceLastCommit),
            lastCommitShortHash: parsedHeadline.shortHash,
            lastCommitSubject: parsedHeadline.subject,
            upstreamLastCommitEpoch: upstreamLastCommitEpoch,
            upstreamLastCommitISO8601: upstreamLastCommitEpoch.map(iso8601(epoch:)),
            upstreamLastCommitRelative: relativeTimeDescription(daysSinceLastCommit: upstreamLastCommitEpoch.map(daysSinceEpoch(_:))),
            daysSinceLastCommit: daysSinceLastCommit,
            recentCommitCount30d: recentCommitCount30d,
            changedFileCount: changedFileCount,
            untrackedFileCount: untrackedFileCount,
            aheadCount: aheadCount,
            behindCount: behindCount,
            score: score
        )
    }

    private static func resolveGitTopLevel(path: String) -> String? {
        gitOutput(repoPath: path, args: ["rev-parse", "--show-toplevel"])
            .map { URL(fileURLWithPath: $0).standardizedFileURL.path }
    }

    private static func parseAheadBehind(_ output: String?) -> (ahead: Int?, behind: Int?) {
        guard let output else { return (nil, nil) }
        let parts = output.split(whereSeparator: \.isWhitespace).map(String.init)
        guard parts.count >= 2, let behind = Int(parts[0]), let ahead = Int(parts[1]) else {
            return (nil, nil)
        }
        return (ahead, behind)
    }

    private static func parseLastCommitHeadline(_ output: String?) -> (shortHash: String?, subject: String?) {
        guard let output else { return (nil, nil) }
        let tokens = output.split(separator: "\u{001F}", maxSplits: 1, omittingEmptySubsequences: false)
        guard !tokens.isEmpty else { return (nil, nil) }

        let hash = tokens.first.map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let subjectRaw = tokens.count > 1 ? String(tokens[1]) : ""
        let subject = subjectRaw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")

        let normalizedHash = (hash?.isEmpty == false) ? hash : nil
        let normalizedSubject = subject.isEmpty ? nil : String(subject.prefix(120))
        return (normalizedHash, normalizedSubject)
    }

    private struct RemoteInfo {
        let host: String?
        let owner: String?
        let repository: String?
    }

    private struct WorkDomainClassification {
        let domain: String
        let confidence: Double
        let reason: String
    }

    private static func parseRemoteInfo(_ originURL: String?) -> RemoteInfo {
        guard let originURL, !originURL.isEmpty else {
            return RemoteInfo(host: nil, owner: nil, repository: nil)
        }

        var host: String?
        var owner: String?
        var repository: String?

        if originURL.contains("://"), let url = URL(string: originURL) {
            host = url.host?.lowercased()
            var path = url.path
            if path.hasPrefix("/") {
                path.removeFirst()
            }
            let parts = path.split(separator: "/").map(String.init)
            if parts.count >= 2 {
                owner = parts[0].lowercased()
                repository = sanitizeRepositoryName(parts[1])
            }
        } else if let atIndex = originURL.firstIndex(of: "@"), let colonIndex = originURL[atIndex...].firstIndex(of: ":") {
            let hostStart = originURL.index(after: atIndex)
            host = String(originURL[hostStart..<colonIndex]).lowercased()
            let repoPath = String(originURL[originURL.index(after: colonIndex)...])
            let parts = repoPath.split(separator: "/").map(String.init)
            if parts.count >= 2 {
                owner = parts[0].lowercased()
                repository = sanitizeRepositoryName(parts[1])
            }
        }

        return RemoteInfo(host: host, owner: owner, repository: repository)
    }

    private static func sanitizeRepositoryName(_ raw: String) -> String {
        var value = raw.lowercased()
        if value.hasSuffix(".git") {
            value.removeLast(4)
        }
        return value
    }

    private static func classifyWorkDomain(
        remoteInfo: RemoteInfo,
        personalIdentity: Set<String>
    ) -> WorkDomainClassification {
        guard let host = remoteInfo.host, let owner = remoteInfo.owner else {
            return WorkDomainClassification(domain: "unknown", confidence: 0.0, reason: "origin remote unavailable")
        }

        let publicHosts: Set<String> = ["github.com", "gitlab.com", "bitbucket.org"]
        if !publicHosts.contains(host) {
            return WorkDomainClassification(domain: "company", confidence: 0.85, reason: "self-hosted git remote")
        }

        if personalIdentity.contains(owner) {
            return WorkDomainClassification(domain: "personal", confidence: 0.9, reason: "origin owner matches local git identity")
        }

        if owner.contains("personal") || owner.contains("private") {
            return WorkDomainClassification(domain: "personal", confidence: 0.65, reason: "origin owner naming pattern")
        }

        return WorkDomainClassification(domain: "unknown", confidence: 0.45, reason: "public host but owner not matched to local identity")
    }

    private static func detectPersonalIdentity() -> Set<String> {
        var values = Set<String>()

        if let email = gitConfigValue(key: "user.email")?.lowercased(), !email.isEmpty {
            if let localPart = email.split(separator: "@").first, !localPart.isEmpty {
                values.insert(String(localPart))
            }
        }

        if let name = gitConfigValue(key: "user.name")?.lowercased(), !name.isEmpty {
            let compact = name.replacingOccurrences(of: " ", with: "")
            if !compact.isEmpty {
                values.insert(compact)
            }
            values.insert(name)
        }

        if let username = ProcessInfo.processInfo.environment["USER"]?.lowercased(), !username.isEmpty {
            values.insert(username)
        }

        return values
    }

    private static func gitConfigValue(key: String) -> String? {
        let (output, exitCode) = runProcess(arguments: ["git", "config", "--global", key])
        guard exitCode == 0 else { return nil }
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func daysSinceEpoch(_ epoch: Int) -> Int {
        max(0, Int((Date().timeIntervalSince1970 - TimeInterval(epoch)) / 86_400))
    }

    private static func relativeTimeDescription(daysSinceLastCommit: Int?) -> String {
        guard let daysSinceLastCommit else { return "unknown" }
        if daysSinceLastCommit == 0 { return "today" }
        if daysSinceLastCommit < 30 { return "\(daysSinceLastCommit)d ago" }
        if daysSinceLastCommit < 365 { return "\(daysSinceLastCommit / 30)mo ago" }
        return "\(daysSinceLastCommit / 365)y ago"
    }

    private static func iso8601(epoch: Int) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(epoch)))
    }

    private static func gitOutput(repoPath: String, args: [String]) -> String? {
        let expandedRepoPath = expandTilde(repoPath)
        let (output, exitCode) = runProcess(arguments: ["git", "-C", expandedRepoPath] + args)
        guard exitCode == 0 else { return nil }
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func runProcess(arguments: [String]) -> (output: String, exitCode: Int32) {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let output = String(data: data, encoding: .utf8) ?? ""
            return (output, process.terminationStatus)
        } catch {
            return ("", 1)
        }
    }
}
