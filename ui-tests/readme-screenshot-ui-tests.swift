import XCTest

/// Captures the README screenshots from docs/demo/demo-seed.sql; run by
/// scripts/capture-readme-screenshots.sh, which also places a neutral backdrop behind the panel.
final class ReadmeScreenshotUITests: XCTestCase {
  func testCaptureReadmeScreenshots() throws {
    guard let databasePath = ProcessInfo.processInfo.environment["TOT_SCREENSHOT_DATABASE"] else {
      throw XCTSkip("Run through scripts/capture-readme-screenshots.sh")
    }
    let directory = FileManager.default.temporaryDirectory.appending(path: "tot-shots-\(UUID().uuidString)")
    let app = XCUIApplication()
    app.launchEnvironment = [
      "TOT_DATABASE_PATH": databasePath,
      "TOT_CLEARED_PATH": directory.appending(path: "cleared.json").path,
      "TOT_DEFAULTS_SUITE": "dev.dak.tot.ui-tests.\(UUID().uuidString)",
    ]
    app.launchArguments = ["-SUEnableAutomaticChecks", "NO"]
    app.launch()
    defer { app.terminate() }

    let panel = app.dialogs["tot-overlay"]
    let rows = app.buttons.matching(identifier: "thread-row")
    XCTAssertTrue(rows["Speed up checkout page"].waitForExistence(timeout: 10))
    // Park the pointer away from the panel so it shows its idle, see-through glass.
    panel.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: -200, dy: 0)).hover()
    sleep(1)
    capture(panel, "overlay-working")

    app.buttons["done-toggle"].click()
    rows["Add dark mode toggle"].click()
    XCTAssertTrue(app.buttons["You: Check contrast on the product cards"].waitForExistence(timeout: 5))
    sleep(1)
    capture(panel, "overlay-detail")
  }

  private func capture(_ element: XCUIElement, _ name: String) {
    let shot = XCTAttachment(screenshot: element.screenshot())
    shot.name = name
    shot.lifetime = .keepAlways
    add(shot)
  }
}
