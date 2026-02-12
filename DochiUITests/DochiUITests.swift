import XCTest

final class DochiUITests: XCTestCase {
    func testPlaceholder() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.windows.count > 0)
    }
}
