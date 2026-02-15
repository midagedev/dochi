import XCTest
@testable import Dochi

// MARK: - HintManager Tests

final class HintManagerTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // 테스트 전 모든 hint 관련 UserDefaults 초기화
        let allKeys = UserDefaults.standard.dictionaryRepresentation().keys
        for key in allKeys where key.hasPrefix("hint_seen_") {
            UserDefaults.standard.removeObject(forKey: key)
        }
        UserDefaults.standard.removeObject(forKey: "hintsGloballyDisabled")
    }

    @MainActor
    func testHasSeenHint_defaultFalse() {
        let manager = HintManager.shared
        XCTAssertFalse(manager.hasSeenHint("testHint"))
    }

    @MainActor
    func testMarkHintSeen() {
        let manager = HintManager.shared
        manager.markHintSeen("testHint")
        XCTAssertTrue(manager.hasSeenHint("testHint"))
        XCTAssertTrue(UserDefaults.standard.bool(forKey: "hint_seen_testHint"))
    }

    @MainActor
    func testCanShowHint_notSeenAndNotDisabled() {
        let manager = HintManager.shared
        manager.activeHintId = nil
        XCTAssertTrue(manager.canShowHint("newHint"))
    }

    @MainActor
    func testCanShowHint_alreadySeen() {
        let manager = HintManager.shared
        manager.markHintSeen("seenHint")
        XCTAssertFalse(manager.canShowHint("seenHint"))
    }

    @MainActor
    func testCanShowHint_globallyDisabled() {
        let manager = HintManager.shared
        manager.disableAllHints()
        XCTAssertFalse(manager.canShowHint("anyHint"))
    }

    @MainActor
    func testCanShowHint_anotherHintActive() {
        let manager = HintManager.shared
        manager.activeHintId = "otherHint"
        XCTAssertFalse(manager.canShowHint("newHint"))
    }

    @MainActor
    func testCanShowHint_sameHintActive() {
        let manager = HintManager.shared
        manager.activeHintId = "myHint"
        XCTAssertTrue(manager.canShowHint("myHint"))
    }

    @MainActor
    func testDisableAllHints() {
        let manager = HintManager.shared
        manager.activeHintId = nil
        manager.activateHint("someHint")
        manager.disableAllHints()

        XCTAssertTrue(manager.isGloballyDisabled)
        XCTAssertNil(manager.activeHintId)
        XCTAssertFalse(manager.canShowHint("someHint"))
    }

    @MainActor
    func testResetAllHints() {
        let manager = HintManager.shared
        manager.markHintSeen("hint1")
        manager.markHintSeen("hint2")
        manager.disableAllHints()

        manager.resetAllHints()

        XCTAssertFalse(manager.isGloballyDisabled)
        XCTAssertFalse(manager.hasSeenHint("hint1"))
        XCTAssertFalse(manager.hasSeenHint("hint2"))
        XCTAssertNil(manager.activeHintId)
    }

    @MainActor
    func testActivateHint() {
        let manager = HintManager.shared
        manager.activeHintId = nil
        manager.activateHint("firstHint")
        XCTAssertEqual(manager.activeHintId, "firstHint")
    }

    @MainActor
    func testDismissHint() {
        let manager = HintManager.shared
        manager.activeHintId = nil
        manager.activateHint("toClose")
        manager.dismissHint("toClose")

        XCTAssertNil(manager.activeHintId)
        XCTAssertTrue(manager.hasSeenHint("toClose"))
    }
}

// MARK: - AppSettings Guide Tests

final class AppSettingsGuideTests: XCTestCase {

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: "hintsGloballyDisabled")
        UserDefaults.standard.removeObject(forKey: "featureTourCompleted")
        UserDefaults.standard.removeObject(forKey: "featureTourSkipped")
        UserDefaults.standard.removeObject(forKey: "featureTourBannerDismissed")
        let allKeys = UserDefaults.standard.dictionaryRepresentation().keys
        for key in allKeys where key.hasPrefix("hint_seen_") {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    @MainActor
    func testHintsEnabled_defaultTrue() {
        let settings = AppSettings()
        XCTAssertTrue(settings.hintsEnabled)
    }

    @MainActor
    func testHintsEnabled_setFalse() {
        let settings = AppSettings()
        settings.hintsEnabled = false
        XCTAssertFalse(settings.hintsEnabled)
        XCTAssertTrue(UserDefaults.standard.bool(forKey: "hintsGloballyDisabled"))
    }

    @MainActor
    func testHintsEnabled_setTrue() {
        let settings = AppSettings()
        settings.hintsEnabled = false
        settings.hintsEnabled = true
        XCTAssertTrue(settings.hintsEnabled)
        XCTAssertFalse(UserDefaults.standard.bool(forKey: "hintsGloballyDisabled"))
    }

    @MainActor
    func testFeatureTourCompleted() {
        let settings = AppSettings()
        XCTAssertFalse(settings.featureTourCompleted)
        settings.featureTourCompleted = true
        XCTAssertTrue(settings.featureTourCompleted)
    }

    @MainActor
    func testFeatureTourSkipped() {
        let settings = AppSettings()
        XCTAssertFalse(settings.featureTourSkipped)
        settings.featureTourSkipped = true
        XCTAssertTrue(settings.featureTourSkipped)
    }

    @MainActor
    func testResetAllHints() {
        let settings = AppSettings()
        // Setup: mark some hints as seen and disable
        UserDefaults.standard.set(true, forKey: "hint_seen_firstConversation")
        UserDefaults.standard.set(true, forKey: "hint_seen_firstKanban")
        UserDefaults.standard.set(true, forKey: "hintsGloballyDisabled")

        settings.resetAllHints()

        XCTAssertFalse(UserDefaults.standard.bool(forKey: "hint_seen_firstConversation"))
        XCTAssertFalse(UserDefaults.standard.bool(forKey: "hint_seen_firstKanban"))
        XCTAssertFalse(UserDefaults.standard.bool(forKey: "hintsGloballyDisabled"))
        XCTAssertTrue(settings.hintsEnabled)
    }

    @MainActor
    func testResetFeatureTour() {
        let settings = AppSettings()
        settings.featureTourCompleted = true
        settings.featureTourSkipped = true
        settings.featureTourBannerDismissed = true

        settings.resetFeatureTour()

        XCTAssertFalse(settings.featureTourCompleted)
        XCTAssertFalse(settings.featureTourSkipped)
        XCTAssertFalse(settings.featureTourBannerDismissed)
    }
}

// MARK: - Tour Step Tests

final class TourStepTests: XCTestCase {

    func testTourStepAllCases() {
        let allCases = TourStep.allCases
        XCTAssertEqual(allCases.count, 4)
        XCTAssertEqual(allCases[0], .overview)
        XCTAssertEqual(allCases[1], .conversation)
        XCTAssertEqual(allCases[2], .agentWorkspace)
        XCTAssertEqual(allCases[3], .shortcuts)
    }

    func testTourStepRawValues() {
        XCTAssertEqual(TourStep.overview.rawValue, 0)
        XCTAssertEqual(TourStep.conversation.rawValue, 1)
        XCTAssertEqual(TourStep.agentWorkspace.rawValue, 2)
        XCTAssertEqual(TourStep.shortcuts.rawValue, 3)
    }

    func testTourStepFromRawValue() {
        XCTAssertEqual(TourStep(rawValue: 0), .overview)
        XCTAssertEqual(TourStep(rawValue: 3), .shortcuts)
        XCTAssertNil(TourStep(rawValue: 4))
        XCTAssertNil(TourStep(rawValue: -1))
    }
}

// MARK: - CommandPalette Guide Items Tests

final class CommandPaletteGuideItemTests: XCTestCase {

    func testStaticItemsContainFeatureTour() {
        let tourItem = CommandPaletteRegistry.staticItems.first { $0.id == "feature-tour" }
        XCTAssertNotNil(tourItem, "Static items should contain feature tour item")
        XCTAssertEqual(tourItem?.title, "기능 투어")
    }

    func testStaticItemsContainResetHints() {
        let resetItem = CommandPaletteRegistry.staticItems.first { $0.id == "reset-hints" }
        XCTAssertNotNil(resetItem, "Static items should contain reset hints item")
        XCTAssertEqual(resetItem?.title, "인앱 힌트 초기화")
    }

    func testFeatureTourAction() {
        let tourItem = CommandPaletteRegistry.staticItems.first { $0.id == "feature-tour" }
        if case .openFeatureTour = tourItem?.action {
            // Expected
        } else {
            XCTFail("Feature tour item should have openFeatureTour action")
        }
    }

    func testResetHintsAction() {
        let resetItem = CommandPaletteRegistry.staticItems.first { $0.id == "reset-hints" }
        if case .resetHints = resetItem?.action {
            // Expected
        } else {
            XCTFail("Reset hints item should have resetHints action")
        }
    }
}
