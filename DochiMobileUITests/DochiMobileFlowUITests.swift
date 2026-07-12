import XCTest

@MainActor
final class DochiMobileFlowUITests: XCTestCase {
    private var app: XCUIApplication!

    func testColdLaunchSettingsAndEmptyMemoryFlow() throws {
        continueAfterFailure = false

        let runID = UUID().uuidString.lowercased()
        app = XCUIApplication()
        app.launchArguments = [
            "-mobile.agent.userID", "ui-test-user-\(runID)",
            "-mobile.agent.sessionID", "ui-test-session-\(runID)",
            "-mobile.agent.provider", "anthropic",
            "-mobile.agent.model.anthropic", "claude-sonnet-5",
            "-mobile.agent.memoryEnabled", "YES",
            "-mobile.agent.speechInputEnabled", "NO",
            "-mobile.agent.speakReplies", "NO",
            "-mobile.agent.hapticsEnabled", "NO",
        ]
        app.launch()
        defer { app.terminate() }

        assertColdLaunchConversation()
        attachScreenshot(named: "01-cold-launch-empty-conversation")

        restoreAppToForeground()
        let settingsButton = app.buttons["mobile-agent-settings-button"]
        waitUntilHittable(settingsButton)
        XCTAssertEqual(settingsButton.label, "에이전트 설정")
        settingsButton.tap()

        XCTAssertTrue(app.navigationBars["도치 설정"].waitForExistence(timeout: 5))
        assertProviderConfiguration()
        attachScreenshot(named: "02-provider-settings")

        assertMemoryPrivacyGuidance()
        attachScreenshot(named: "03-memory-privacy-settings")
        restoreAppToForeground()
        let managementLink = app.buttons["memory-management-link"]
        waitUntilHittable(managementLink)
        managementLink.tap()

        assertEmptyMemoryState()
        attachScreenshot(named: "04-empty-memory-management")
        assertPurgeIsolationGuidance()
    }

    private func assertColdLaunchConversation() {
        XCTAssertTrue(app.navigationBars["도치"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["무슨 이야기를 해볼까요?"].waitForExistence(timeout: 5))

        let avatar = app.images["mobile-empty-avatar"]
        XCTAssertTrue(avatar.exists)
        XCTAssertTrue(avatar.label.contains("도치 아바타"))

        let composer = app.textFields["mobile-message-composer"]
        XCTAssertTrue(composer.exists)
        XCTAssertEqual(composer.label, "메시지")
        XCTAssertTrue(app.buttons["메시지 보내기"].exists)
    }

    private func assertProviderConfiguration() {
        let providerPicker = app.descendants(matching: .any)["mobile-provider-picker"]
        scrollUntilHittable(providerPicker)
        XCTAssertTrue(providerPicker.exists)
        XCTAssertTrue(providerPicker.label.hasPrefix("프로바이더"))
        XCTAssertTrue(providerPicker.label.contains("Anthropic"))

        let modelField = app.textFields["mobile-model-name-field"]
        XCTAssertTrue(modelField.exists)
        XCTAssertEqual(modelField.value as? String, "claude-sonnet-5")

        let keyField = app.secureTextFields["mobile-provider-api-key-field"]
        XCTAssertTrue(keyField.exists)
        XCTAssertEqual(keyField.label, "Anthropic API 키")

        let keyGuidance = app.staticTexts["mobile-provider-key-guidance"]
        XCTAssertTrue(keyGuidance.exists)
        XCTAssertTrue(keyGuidance.label.contains("iOS Keychain"))
        XCTAssertTrue(keyGuidance.label.contains("HTTPS"))
    }

    private func assertMemoryPrivacyGuidance() {
        let memoryToggle = app.switches["mobile-memory-toggle"]
        scrollUntilHittable(memoryToggle)
        XCTAssertTrue(memoryToggle.exists)
        XCTAssertEqual(memoryToggle.value as? String, "1")

        let guidance = app.staticTexts["mobile-memory-privacy-guidance"]
        XCTAssertTrue(guidance.exists)
        XCTAssertTrue(guidance.label.contains("꺼도 저장된 데이터는 삭제되지 않습니다"))
        XCTAssertTrue(guidance.label.contains("선택한 모델 프로바이더로 전송됩니다"))

        let managementLink = app.buttons["memory-management-link"]
        scrollUntilHittable(managementLink)
        XCTAssertTrue(managementLink.exists)
    }

    private func assertEmptyMemoryState() {
        XCTAssertTrue(app.navigationBars["저장된 기억"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["저장된 기억이 없습니다"].waitForExistence(timeout: 8))
        XCTAssertTrue(
            app.staticTexts["현재 사용자에게 속한 기억이 생기면 과거 대화 범위까지 여기에 표시됩니다."].exists
        )
    }

    private func assertPurgeIsolationGuidance() {
        let isolationGuidance = app.staticTexts["memory-purge-isolation-guidance"]
        scrollUntilHittable(isolationGuidance)
        XCTAssertTrue(isolationGuidance.exists)
        XCTAssertEqual(isolationGuidance.label, "영구 삭제 범위 격리")

        let detail = app.staticTexts["memory-purge-isolation-detail"]
        XCTAssertTrue(detail.exists)
        XCTAssertTrue(detail.label.contains("다른 앱"))
        XCTAssertTrue(detail.label.contains("다른 사용자"))
        XCTAssertTrue(detail.label.contains("앱 전체 범위"))
    }

    private func scrollUntilHittable(_ element: XCUIElement, maxSwipes: Int = 8) {
        for _ in 0..<maxSwipes where !element.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable, "화면에서 요소를 찾지 못했습니다: \(element)")
    }

    private func restoreAppToForeground() {
        app.activate()
        XCTAssertTrue(
            app.wait(for: .runningForeground, timeout: 5),
            "도치 앱을 전면으로 복구하지 못했습니다."
        )
    }

    private func waitUntilHittable(_ element: XCUIElement) {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == true AND hittable == true"),
            object: element
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [expectation], timeout: 5),
            .completed,
            "요소가 탭 가능한 상태가 되지 않았습니다: \(element)"
        )
    }

    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
