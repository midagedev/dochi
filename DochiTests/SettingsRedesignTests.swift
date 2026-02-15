import XCTest
@testable import Dochi

// MARK: - SettingsSection Tests

final class SettingsSectionTests: XCTestCase {

    func testAllCasesCount() {
        XCTAssertEqual(SettingsSection.allCases.count, 17, "There should be 17 settings sections")
    }

    func testTitleNotEmpty() {
        for section in SettingsSection.allCases {
            XCTAssertFalse(section.title.isEmpty, "Section \(section.rawValue) should have a title")
        }
    }

    func testIconNotEmpty() {
        for section in SettingsSection.allCases {
            XCTAssertFalse(section.icon.isEmpty, "Section \(section.rawValue) should have an icon")
        }
    }

    func testSearchKeywordsNotEmpty() {
        for section in SettingsSection.allCases {
            XCTAssertFalse(section.searchKeywords.isEmpty, "Section \(section.rawValue) should have search keywords")
        }
    }

    func testUniqueRawValues() {
        let rawValues = SettingsSection.allCases.map(\.rawValue)
        XCTAssertEqual(Set(rawValues).count, rawValues.count, "Section raw values should be unique")
    }

    func testUniqueIds() {
        let ids = SettingsSection.allCases.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "Section IDs should be unique")
    }

    // MARK: - Group mapping

    func testGroupMapping() {
        XCTAssertEqual(SettingsSection.aiModel.group, .ai)
        XCTAssertEqual(SettingsSection.apiKey.group, .ai)
        XCTAssertEqual(SettingsSection.voice.group, .voice)
        XCTAssertEqual(SettingsSection.interface.group, .general)
        XCTAssertEqual(SettingsSection.wakeWord.group, .general)
        XCTAssertEqual(SettingsSection.heartbeat.group, .general)
        XCTAssertEqual(SettingsSection.family.group, .people)
        XCTAssertEqual(SettingsSection.agent.group, .people)
        XCTAssertEqual(SettingsSection.tools.group, .connection)
        XCTAssertEqual(SettingsSection.integrations.group, .connection)
        XCTAssertEqual(SettingsSection.shortcuts.group, .connection)
        XCTAssertEqual(SettingsSection.account.group, .connection)
        XCTAssertEqual(SettingsSection.guide.group, .help)
    }

    func testAllSectionsHaveGroup() {
        for section in SettingsSection.allCases {
            // Just verify group is accessible (no crash)
            _ = section.group
        }
    }

    func testAllGroupsHaveSections() {
        for group in SettingsSectionGroup.allCases {
            XCTAssertFalse(group.sections.isEmpty, "Group \(group.rawValue) should have at least one section")
        }
    }

    func testGroupSectionsAreComplete() {
        // All sections should be covered by groups
        let allGroupedSections = SettingsSectionGroup.allCases.flatMap(\.sections)
        XCTAssertEqual(
            Set(allGroupedSections),
            Set(SettingsSection.allCases),
            "All sections should be covered by groups"
        )
    }

    // MARK: - Specific titles and icons

    func testAIModelSection() {
        let section = SettingsSection.aiModel
        XCTAssertEqual(section.title, "AI 모델")
        XCTAssertEqual(section.icon, "brain")
        XCTAssertEqual(section.rawValue, "ai-model")
    }

    func testAPIKeySection() {
        let section = SettingsSection.apiKey
        XCTAssertEqual(section.title, "API 키")
        XCTAssertEqual(section.icon, "key")
    }

    func testVoiceSection() {
        let section = SettingsSection.voice
        XCTAssertEqual(section.title, "음성 합성")
        XCTAssertEqual(section.icon, "speaker.wave.2")
    }

    func testGuideSection() {
        let section = SettingsSection.guide
        XCTAssertEqual(section.title, "가이드")
        XCTAssertEqual(section.icon, "play.rectangle")
        XCTAssertEqual(section.group, .help)
    }
}

// MARK: - SettingsSearch Tests

final class SettingsSearchTests: XCTestCase {

    func testSearchByTitle() {
        // "AI 모델" should match the aiModel section
        XCTAssertTrue(SettingsSection.aiModel.matches(query: "AI 모델"))
        XCTAssertTrue(SettingsSection.aiModel.matches(query: "모델"))
        XCTAssertTrue(SettingsSection.apiKey.matches(query: "API"))
    }

    func testSearchByKeyword() {
        // "OpenAI" should match aiModel (keyword)
        XCTAssertTrue(SettingsSection.aiModel.matches(query: "OpenAI"))
        // "텔레그램" should match integrations
        XCTAssertTrue(SettingsSection.integrations.matches(query: "텔레그램"))
        // "속도" should match voice
        XCTAssertTrue(SettingsSection.voice.matches(query: "속도"))
        // "캘린더" should match heartbeat
        XCTAssertTrue(SettingsSection.heartbeat.matches(query: "캘린더"))
        // "VRM" should match interface
        XCTAssertTrue(SettingsSection.interface.matches(query: "VRM"))
    }

    func testSearchCaseInsensitive() {
        // Keywords should match case-insensitively
        XCTAssertTrue(SettingsSection.aiModel.matches(query: "openai"))
        XCTAssertTrue(SettingsSection.account.matches(query: "supabase"))
    }

    func testSearchNoMatch() {
        XCTAssertFalse(SettingsSection.aiModel.matches(query: "텔레그램"))
        XCTAssertFalse(SettingsSection.voice.matches(query: "칸반"))
        XCTAssertFalse(SettingsSection.guide.matches(query: "모델"))
    }

    func testSearchPartialMatch() {
        // Partial title match
        XCTAssertTrue(SettingsSection.integrations.matches(query: "통합"))
        // Partial keyword match
        XCTAssertTrue(SettingsSection.tools.matches(query: "권한"))
    }

    func testEveryKeywordMatchesCorrectSection() {
        // Spot-check: each section's keywords match that section
        for section in SettingsSection.allCases {
            for keyword in section.searchKeywords {
                XCTAssertTrue(
                    section.matches(query: keyword),
                    "Keyword '\(keyword)' should match section '\(section.title)'"
                )
            }
        }
    }
}

// MARK: - SettingsSectionGroup Tests

final class SettingsSectionGroupTests: XCTestCase {

    func testAllGroupsCount() {
        XCTAssertEqual(SettingsSectionGroup.allCases.count, 6, "There should be 6 settings groups")
    }

    func testGroupRawValues() {
        XCTAssertEqual(SettingsSectionGroup.ai.rawValue, "AI")
        XCTAssertEqual(SettingsSectionGroup.voice.rawValue, "음성")
        XCTAssertEqual(SettingsSectionGroup.general.rawValue, "일반")
        XCTAssertEqual(SettingsSectionGroup.people.rawValue, "사람")
        XCTAssertEqual(SettingsSectionGroup.connection.rawValue, "연결")
        XCTAssertEqual(SettingsSectionGroup.help.rawValue, "도움말")
    }

    func testAIGroupSections() {
        let sections = SettingsSectionGroup.ai.sections
        XCTAssertEqual(sections.count, 6)
        XCTAssertTrue(sections.contains(.aiModel))
        XCTAssertTrue(sections.contains(.apiKey))
        XCTAssertTrue(sections.contains(.usage))
        XCTAssertTrue(sections.contains(.rag))
        XCTAssertTrue(sections.contains(.memory))
        XCTAssertTrue(sections.contains(.feedback))
    }

    func testGeneralGroupSections() {
        let sections = SettingsSectionGroup.general.sections
        XCTAssertEqual(sections.count, 3)
        XCTAssertTrue(sections.contains(.interface))
        XCTAssertTrue(sections.contains(.wakeWord))
        XCTAssertTrue(sections.contains(.heartbeat))
    }

    func testConnectionGroupSections() {
        let sections = SettingsSectionGroup.connection.sections
        XCTAssertEqual(sections.count, 4)
        XCTAssertTrue(sections.contains(.tools))
        XCTAssertTrue(sections.contains(.integrations))
        XCTAssertTrue(sections.contains(.shortcuts))
        XCTAssertTrue(sections.contains(.account))
    }
}

// MARK: - CommandPalette Settings Items Tests

final class CommandPaletteSettingsItemsTests: XCTestCase {

    func testSettingsItemsExist() {
        let settingsItems = CommandPaletteRegistry.staticItems.filter { $0.category == .settings }
        // open-settings, reset-hints, settings.model, settings.open.ai, settings.open.apikey,
        // settings.open.voice, settings.open.agent, settings.open.integration, settings.open.account
        XCTAssertGreaterThanOrEqual(settingsItems.count, 9)
    }

    func testQuickModelPaletteItem() {
        let item = CommandPaletteRegistry.staticItems.first { $0.id == "settings.model" }
        XCTAssertNotNil(item, "Quick model palette item should exist")
        XCTAssertEqual(item?.title, "모델 빠르게 변경")
        XCTAssertEqual(item?.category, .settings)
    }

    func testSettingsSectionPaletteItems() {
        let sectionIds = [
            "settings.open.ai",
            "settings.open.apikey",
            "settings.open.voice",
            "settings.open.agent",
            "settings.open.integration",
            "settings.open.account",
        ]

        for id in sectionIds {
            let item = CommandPaletteRegistry.staticItems.first { $0.id == id }
            XCTAssertNotNil(item, "Palette item '\(id)' should exist")
            XCTAssertEqual(item?.category, .settings)
        }
    }

    func testAllStaticItemsHaveUniqueIds() {
        let ids = CommandPaletteRegistry.staticItems.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "Static item IDs should be unique")
    }
}
