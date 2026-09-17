import XCTest

final class BleKeyStudioUITests: XCTestCase {
  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  @MainActor
  func testMappingWorkspaceSupportsDirectKeySelection() throws {
    let app = XCUIApplication()
    app.launchEnvironment["BLEKEY_DEMO_MODE"] = "1"
    app.launch()

    XCTAssertTrue(app.windows["BleKey Studio"].waitForExistence(timeout: 5))

    let mappings = app.tables["mappingTable"]
    XCTAssertTrue(mappings.waitForExistence(timeout: 2))
    mappings.tableRows.element(boundBy: 1).click()

    let keycap = app.buttons["keycap.key.k"]
    XCTAssertTrue(keycap.waitForExistence(timeout: 2))
    keycap.click()

    XCTAssertTrue(app.buttons["applyChanges"].exists)
    XCTAssertTrue(app.staticTexts["键盘"].exists)
  }
}
