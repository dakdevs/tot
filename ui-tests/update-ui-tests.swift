import XCTest

/// Drives Sparkle's real updater UI against fixture feeds that e2e/overlay.e2e.ts serves over HTTP
/// (Sparkle refuses file URLs). The fixture archive is signed with a key that isn't Tot's, so installing
/// it must fail validation. A successful install and relaunch is covered by scripts/verify-update-install.sh.
final class UpdateUITests: XCTestCase {
  private var fixtures: URL!
  private var app: XCUIApplication!

  override func setUpWithError() throws {
    continueAfterFailure = false
    let fixtureURL = ProcessInfo.processInfo.environment["TOT_UPDATE_FIXTURE_URL"]
    fixtures = try XCTUnwrap(fixtureURL.flatMap(URL.init(string:)), "Run through `bun run test:e2e`")
    let directory = FileManager.default.temporaryDirectory.appending(path: "tot-update-\(UUID().uuidString)")

    app = XCUIApplication()
    app.launchEnvironment = [
      "TOT_DATABASE_PATH": directory.appending(path: "missing.sqlite").path,
      "TOT_CLEARED_PATH": directory.appending(path: "cleared.json").path,
      "TOT_DEFAULTS_SUITE": "dev.dak.tot.ui-tests.\(UUID().uuidString)",
    ]
  }

  override func tearDown() {
    app?.terminate()
  }

  func testManualCheckReportsUpToDate() throws {
    launch(feed: "current.xml", automaticChecks: false)
    openSettings()
    app.buttons["Check for Updates…"].click()

    XCTAssertTrue(app.staticTexts["You’re up to date!"].waitForExistence(timeout: 20))
    button("OK").click()
    XCTAssertEqual(status, "Tot is up to date.")
  }

  func testScheduledUpdateAsksAndCanBeDeferredThenInstalledFromSettings() throws {
    launch(feed: "newer.xml", automaticChecks: true)

    // The background check fires on launch because the last check is long past.
    let install = button("Install Update")
    XCTAssertTrue(install.waitForExistence(timeout: 30), "Scheduled check asks about the new release")
    XCTAssertTrue(button("Remind Me Later").exists)
    XCTAssertEqual(app.state, .runningForeground, "The accessory app comes forward for the alert")
    attach("update-alert")

    button("Remind Me Later").click()
    XCTAssertTrue(waitForAbsence(install), "Deferring dismisses the alert without installing")

    openSettings()
    XCTAssertEqual(status, "Version 20991231.1 is available.")
    app.buttons["Check for Updates…"].click()
    XCTAssertTrue(install.waitForExistence(timeout: 20), "Settings can bring the deferred update back")
    install.click()

    // The fixture isn't signed with Tot's EdDSA key, so Sparkle must refuse it.
    let failure = app.staticTexts.containing(NSPredicate(format: "value CONTAINS[c] 'improperly signed'")).firstMatch
    XCTAssertTrue(failure.waitForExistence(timeout: 30), "An archive with a foreign signature is rejected")
    attach("update-rejected")
  }

  /// Sparkle's alert buttons are mirrored in the Touch Bar, so a plain query matches twice.
  private func button(_ title: String) -> XCUIElement { app.buttons[title].firstMatch }

  private var status: String? {
    let label = app.staticTexts["update-status"]
    XCTAssertTrue(label.waitForExistence(timeout: 10))
    return label.value as? String
  }

  private func launch(feed: String, automaticChecks: Bool) {
    app.launchEnvironment["TOT_UPDATE_FEED_URL"] = fixtures.appending(path: feed).absoluteString
    // Argument-domain overrides keep Sparkle's persisted check schedule from deciding the test.
    app.launchArguments = [
      "-SUEnableAutomaticChecks", automaticChecks ? "YES" : "NO",
      "-SULastCheckTime", "<date>2000-01-01T00:00:00Z</date>",
    ]
    app.launch()
  }

  private func openSettings() {
    let gear = app.buttons["Settings"]
    XCTAssertTrue(gear.waitForExistence(timeout: 10))
    gear.click()
    XCTAssertTrue(app.buttons["Check for Updates…"].waitForExistence(timeout: 10))
  }

  private func waitForAbsence(_ element: XCUIElement, timeout: TimeInterval = 5) -> Bool {
    let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: element)
    return XCTWaiter().wait(for: [gone], timeout: timeout) == .completed
  }

  private func attach(_ name: String) {
    let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    shot.name = name
    shot.lifetime = .keepAlways
    add(shot)
  }
}
