import Foundation

enum BridgeWorkingDirectorySelectionReason: String, Sendable {
    case existingSessionReused = "existing_session_reused"
    case existingSessionReusedForceIgnored = "existing_session_reused_force_ignored"
    case existingProfilePreserved = "existing_profile_preserved"
    case existingProfileOverridden = "existing_profile_overridden"
    case requestedWorkingDirectory = "requested_working_directory"
    case recommendedGitRoot = "recommended_git_root"
    case fallbackHomeDirectory = "fallback_home_directory"
}

struct BridgeWorkingDirectoryDecision: Sendable, Equatable {
    let workingDirectory: String
    let selectionReason: BridgeWorkingDirectorySelectionReason
    let selectionDetail: String
}

enum BridgeWorkingDirectorySelector {
    static func decideForActiveSession(
        profileWorkingDirectory: String,
        requestedWorkingDirectory: String?,
        forceWorkingDirectory: Bool
    ) -> BridgeWorkingDirectoryDecision {
        if forceWorkingDirectory, let requestedWorkingDirectory {
            return BridgeWorkingDirectoryDecision(
                workingDirectory: profileWorkingDirectory,
                selectionReason: .existingSessionReusedForceIgnored,
                selectionDetail: "active session reused; requested '\(requestedWorkingDirectory)' ignored because running session cwd cannot be overwritten"
            )
        }
        return BridgeWorkingDirectoryDecision(
            workingDirectory: profileWorkingDirectory,
            selectionReason: .existingSessionReused,
            selectionDetail: "active session already exists for profile; reusing profile working directory"
        )
    }

    static func decide(
        existingProfile: ExternalToolProfile?,
        requestedWorkingDirectory: String?,
        forceWorkingDirectory: Bool,
        recommendedRoots: [GitRepositoryInsight]
    ) -> BridgeWorkingDirectoryDecision {
        if let existingProfile {
            if let requestedWorkingDirectory, forceWorkingDirectory {
                return BridgeWorkingDirectoryDecision(
                    workingDirectory: requestedWorkingDirectory,
                    selectionReason: .existingProfileOverridden,
                    selectionDetail: "existing profile working_directory overridden by force_working_directory"
                )
            }

            if let requestedWorkingDirectory {
                return BridgeWorkingDirectoryDecision(
                    workingDirectory: existingProfile.workingDirectory,
                    selectionReason: .existingProfilePreserved,
                    selectionDetail: "existing profile working_directory preserved; requested '\(requestedWorkingDirectory)' ignored (use force_working_directory=true to override)"
                )
            }

            return BridgeWorkingDirectoryDecision(
                workingDirectory: existingProfile.workingDirectory,
                selectionReason: .existingProfilePreserved,
                selectionDetail: "reusing existing profile working_directory"
            )
        }

        if let requestedWorkingDirectory {
            return BridgeWorkingDirectoryDecision(
                workingDirectory: requestedWorkingDirectory,
                selectionReason: .requestedWorkingDirectory,
                selectionDetail: "working_directory was explicitly provided"
            )
        }

        if let recommended = recommendedRoots.first {
            let dirtySummary = "\(recommended.changedFileCount)+\(recommended.untrackedFileCount)"
            return BridgeWorkingDirectoryDecision(
                workingDirectory: recommended.path,
                selectionReason: .recommendedGitRoot,
                selectionDetail: "selected top recommended git root '\(recommended.name)' (score=\(recommended.score), last_commit=\(recommended.lastCommitRelative), dirty=\(dirtySummary))"
            )
        }

        return BridgeWorkingDirectoryDecision(
            workingDirectory: "~",
            selectionReason: .fallbackHomeDirectory,
            selectionDetail: "no recommended git root found; fallback to home directory"
        )
    }
}
