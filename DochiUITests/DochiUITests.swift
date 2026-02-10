import XCTest

final class DochiUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-uiTest"]
        app.launchEnvironment["UITEST"] = "1"
        app.launch()
    }

    func testOpenCommandPalette() {
        // 메뉴를 통해 커맨드 팔레트 열기 (단축키보다 안정적)
        let menuBar = app.menuBars
        let dochiMenu = menuBar.menuBarItems["Dochi"]
        XCTAssertTrue(dochiMenu.waitForExistence(timeout: 2))
        dochiMenu.click()
        let menuItem = app.menuItems["Command Palette…"]
        XCTAssertTrue(menuItem.waitForExistence(timeout: 2))
        menuItem.click()

        let field = app.textFields["palette.search"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
    }

    func testSendUserMessageAppears() {
        let input = app.textFields["input.textField"]
        XCTAssertTrue(input.waitForExistence(timeout: 3))
        input.click()
        input.typeText("안녕 도치")
        app.buttons["input.send"].click()

        // 사용자 메시지 텍스트가 화면에 존재하는지 검사
        XCTAssertTrue(app.staticTexts["안녕 도치"].waitForExistence(timeout: 2))
    }

    func testOpenSettingsAndFindTelegramCard() {
        let settingsButton = app.buttons["open.settings"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 3))
        settingsButton.click()

        let toggle = app.switches["integrations.telegram.toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 3))
        let tokenField = app.secureTextFields["integrations.telegram.token"]
        XCTAssertTrue(tokenField.exists)
        let status = app.staticTexts["integrations.telegram.status"]
        XCTAssertTrue(status.exists)
    }
}
