import Foundation
import Combine
import os

/// 서비스 콜백 및 Combine 바인딩 설정
extension DochiViewModel {
    func setupCallbacks() {
        speechService.onWakeWordDetected = { [weak self] transcript in
            guard let self else { return }
            self.isSessionActive = true
            self.state = .listening
            self.sessionManager.identifyUserFromTranscript(transcript)
            Log.app.info("세션 시작 (사용자: \(self.currentUserName ?? Constants.Session.unknownUserLabel))")
        }

        speechService.onQueryCaptured = { [weak self] query in
            guard let self else { return }

            if self.isAskingToEndSession {
                self.isAskingToEndSession = false
                self.sessionManager.handleEndSessionResponse(query)
                return
            }

            if self.isSessionActive && self.sessionManager.isEndSessionRequest(query) {
                self.sessionManager.confirmAndEndSession()
                return
            }

            self.handleQuery(query)
        }

        speechService.onListeningCancelled = { [weak self] in
            guard let self, self.state == .listening else { return }
            Log.app.info("리스닝 취소 — 상태 리셋")
            self.state = .idle
            self.sessionManager.startWakeWordIfNeeded()
        }

        speechService.onSilenceTimeout = { [weak self] in
            guard let self, self.isSessionActive else { return }

            if self.isAskingToEndSession {
                self.isAskingToEndSession = false
                self.sessionManager.endSession()
                return
            }

            if self.autoEndSession {
                self.sessionManager.askToEndSession()
            } else {
                self.sessionManager.startContinuousListening()
            }
        }

        llmService.onSentenceReady = { [weak self] sentence in
            guard let self else { return }
            if self.supertonicService.state == .ready || self.supertonicService.state == .synthesizing || self.supertonicService.state == .playing {
                if self.state != .speaking {
                    self.speechService.stopListening()
                    self.speechService.stopWakeWordDetection()
                }
                self.state = .speaking
                self.supertonicService.speed = self.settings.ttsSpeed
                self.supertonicService.diffusionSteps = self.settings.ttsDiffusionSteps
                let cleaned = TTSSanitizer.sanitize(sentence)
                guard !cleaned.isEmpty else { return }
                self.supertonicService.enqueueSentence(cleaned, voice: self.settings.supertonicVoice)
            }
        }

        llmService.onResponseComplete = { [weak self] response in
            guard let self else { return }
            self.messages.append(Message(role: .assistant, content: response))
            self.sessionManager.recoverIfTTSDidNotPlay()
        }

        llmService.onToolCallsReceived = { [weak self] toolCalls in
            guard let self else { return }
            Task {
                await self.toolExecutor.executeToolLoop(toolCalls: toolCalls)
            }
        }

        supertonicService.onSpeakingComplete = { [weak self] in
            guard let self else { return }
            self.state = .idle

            Task {
                // Task 취소 시 에코 방지 딜레이 스킵은 의도된 동작
                try? await Task.sleep(for: .milliseconds(Constants.Timing.echoPreventionDelayMs))
                guard self.state == .idle else { return }

                if self.isSessionActive {
                    self.sessionManager.startContinuousListening()
                } else {
                    self.sessionManager.startWakeWordIfNeeded()
                }
            }
        }

        builtInToolService.onAlarmFired = { [weak self] message in
            guard let self else { return }
            Log.app.info("알람 발동: \(message), 현재 상태: \(String(describing: self.state)), TTS 상태: \(String(describing: self.supertonicService.state))")
            if self.state == .speaking {
                self.supertonicService.stopPlayback()
            }
            if self.state == .listening {
                self.speechService.stopListening()
            }
            self.state = .speaking
            self.supertonicService.speed = self.settings.ttsSpeed
            self.supertonicService.diffusionSteps = self.settings.ttsDiffusionSteps
            self.supertonicService.speak("알람이에요! \(message)", voice: self.settings.supertonicVoice)
        }

        supertonicService.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] ttsState in
                guard let self, ttsState == .ready, self.state == .idle else { return }
                self.sessionManager.startWakeWordIfNeeded()
            }
            .store(in: &cancellables)
    }

    func setupChangeForwarding() {
        speechService.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        llmService.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        supertonicService.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        supabaseService.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    func setupProfileCallback() {
        builtInToolService.profileTool.onUserIdentified = { [weak self] profile in
            guard let self else { return }
            self.currentUserId = profile.id
            self.currentUserName = profile.name
            Log.app.info("사용자 설정됨 (tool): \(profile.name)")
        }
    }

    func setupLLMCallbacks() {
        llmService.onResponseComplete = { [weak self] response in
            guard let self else { return }
            self.messages.append(Message(role: .assistant, content: response))
            self.sessionManager.recoverIfTTSDidNotPlay()
        }

        llmService.onToolCallsReceived = { [weak self] toolCalls in
            guard let self else { return }
            Task {
                await self.toolExecutor.executeToolLoop(toolCalls: toolCalls)
            }
        }
    }
}
