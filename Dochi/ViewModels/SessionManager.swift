import Foundation
import os

/// 세션 라이프사이클 관리: 웨이크워드, 연속 대화, 세션 종료
@MainActor
final class SessionManager {
    private weak var vm: DochiViewModel?

    let sessionTimeoutSeconds: TimeInterval = 10.0

    init(viewModel: DochiViewModel) {
        self.vm = viewModel
    }

    // MARK: - Wake Word

    func startWakeWordIfNeeded() {
        guard let vm else { return }
        guard vm.settings.wakeWordEnabled,
              vm.state == .idle,
              vm.speechService.state == .idle,
              !vm.settings.wakeWord.isEmpty
        else { return }

        // 권한이 이미 허용된 경우에만 자동 시작 — 앱 시작 시 반복 프롬프트 방지
        guard SpeechService.isAuthorized() else { return }

        Log.stt.info("웨이크워드 자모 매칭 시작: \(vm.settings.wakeWord)")
        vm.speechService.startWakeWordDetection(wakeWord: vm.settings.wakeWord)
    }

    func stopWakeWord() {
        vm?.speechService.stopWakeWordDetection()
    }

    // MARK: - User Identification

    func identifyUserFromTranscript(_ transcript: String) {
        guard let vm else { return }
        let profiles = vm.contextService.loadProfiles()
        guard !profiles.isEmpty else {
            vm.currentUserId = nil
            vm.currentUserName = nil
            return
        }

        let normalized = transcript.replacingOccurrences(of: " ", with: "").lowercased()

        if let matched = profiles.first(where: { profile in
            profile.allNames.contains { normalized.contains($0.lowercased()) }
        }) {
            vm.currentUserId = matched.id
            vm.currentUserName = matched.name
            Log.app.info("웨이크워드에서 사용자 식별: \(matched.name)")
            return
        }

        if let defaultId = vm.settings.defaultUserId,
           let defaultProfile = profiles.first(where: { $0.id == defaultId }) {
            vm.currentUserId = defaultProfile.id
            vm.currentUserName = defaultProfile.name
            Log.app.info("기본 사용자 할당: \(defaultProfile.name)")
            return
        }

        vm.currentUserId = nil
        vm.currentUserName = nil
    }

    func assignDefaultUserIfNeeded() {
        guard let vm, vm.currentUserId == nil else { return }
        let profiles = vm.contextService.loadProfiles()
        if !profiles.isEmpty, let defaultId = vm.settings.defaultUserId,
           let defaultProfile = profiles.first(where: { $0.id == defaultId }) {
            vm.currentUserId = defaultProfile.id
            vm.currentUserName = defaultProfile.name
            Log.app.info("PTT 기본 사용자 할당: \(defaultProfile.name)")
        }
    }

    // MARK: - Continuous Conversation

    func startContinuousListening() {
        guard let vm else { return }
        vm.state = .listening
        vm.speechService.silenceTimeout = vm.settings.sttSilenceTimeout
        vm.speechService.startContinuousListening(timeout: sessionTimeoutSeconds)
        Log.app.info("연속 대화 STT 시작 (타임아웃: \(self.sessionTimeoutSeconds)초)")
    }

    func askToEndSession() {
        guard let vm else { return }
        vm.isAskingToEndSession = true
        vm.speechService.stopListening()
        vm.speechService.stopWakeWordDetection()
        if vm.settings.interactionMode == .voiceAndText {
            vm.state = .speaking
            vm.supertonicService.speed = vm.settings.ttsSpeed
            vm.supertonicService.diffusionSteps = vm.settings.ttsDiffusionSteps
            vm.supertonicService.speak(Constants.Session.askEndMessage, voice: vm.settings.supertonicVoice)
        } else {
            vm.messages.append(Message(role: .assistant, content: Constants.Session.askEndMessage))
            vm.state = .idle
        }
        Log.app.info("세션 종료 여부 질문")
    }

    func handleEndSessionResponse(_ response: String) {
        guard let vm else { return }
        let normalized = response.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let positiveKeywords = Constants.Session.endKeywords

        if positiveKeywords.contains(where: { normalized.contains($0) }) {
            endSession()
        } else {
            Log.app.info("세션 계속")
            vm.handleQuery(response)
        }
    }

    func isEndSessionRequest(_ query: String) -> Bool {
        let normalized = query.lowercased().replacingOccurrences(of: " ", with: "")
        let endKeywords = Constants.Session.endTriggers
        return endKeywords.contains(where: { normalized.contains($0) })
    }

    func confirmAndEndSession() {
        guard let vm else { return }
        vm.speechService.stopListening()
        vm.speechService.stopWakeWordDetection()
        if vm.settings.interactionMode == .voiceAndText {
            vm.state = .speaking
            vm.supertonicService.speed = vm.settings.ttsSpeed
            vm.supertonicService.diffusionSteps = vm.settings.ttsDiffusionSteps
            vm.supertonicService.speak(Constants.Session.endConfirmMessage, voice: vm.settings.supertonicVoice)

            Task { [weak vm] in
                guard let vm else { return }
                while vm.supertonicService.state == .playing || vm.supertonicService.state == .synthesizing {
                    try? await Task.sleep(for: .milliseconds(Constants.Timing.ttsCompletionPollMs))
                }
                self.endSession()
            }
        } else {
            vm.messages.append(Message(role: .assistant, content: Constants.Session.endConfirmMessage))
            self.endSession()
        }
    }

    func endSession() {
        guard let vm else { return }
        Log.app.info("세션 종료")
        vm.isSessionActive = false
        vm.isAskingToEndSession = false

        if !vm.messages.isEmpty {
            let sessionMessages = vm.messages
            let sessionUserId = vm.currentUserId
            Task {
                await vm.contextAnalyzer.saveAndAnalyzeConversation(sessionMessages, userId: sessionUserId)
            }
        }
        vm.messages.removeAll()
        vm.currentConversationId = nil

        vm.currentUserId = nil
        vm.currentUserName = nil

        vm.state = .idle
        startWakeWordIfNeeded()
    }

    /// TTS가 재생되지 않았을 때 상태 복구 (텍스트 전용 응답 등)
    func recoverIfTTSDidNotPlay() {
        guard let vm else { return }
        guard vm.state == .processing else { return }

        vm.state = .idle
        Log.app.info("TTS 미재생 — 상태 복구")

        if vm.isSessionActive {
            startContinuousListening()
        } else {
            startWakeWordIfNeeded()
        }
    }
}
