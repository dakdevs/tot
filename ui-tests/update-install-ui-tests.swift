import XCTest

/// Installs a real signed update end to end; scripts/verify-update-install.sh builds the old and new
/// release apps, serves the signed feed, runs only this test, and then checks the replaced bundle.
final class UpdateInstallUITests: XCTestCase {
  func testInstallAndRelaunch() throws {
    let environment = ProcessInfo.processInfo.environment
    guard let appPath = environment["TOT_INSTALL_APP"], let feed = environment["TOT_INSTALL_FEED_URL"] else {
      throw XCTSkip("Run through scripts/verify-update-install.sh")
    }
    let app = XCUIApplication(url: URL(fileURLWithPath: appPath))
    let directory = FileManager.default.temporaryDirectory.appending(path: "tot-install-\(UUID().uuidString)")
    app.launchEnvironment = [
      "TOT_UPDATE_FEED_URL": feed,
      "TOT_DATABASE_PATH": directory.appending(path: "missing.sqlite").path,
      "TOT_CLEARED_PATH": directory.appending(path: "cleared.json").path,
      "TOT_DEFAULTS_SUITE": "dev.dak.tot.ui-tests.\(UUID().uuidString)",
    ]
    app.launchArguments = ["-SUEnableAutomaticChecks", "YES", "-SULastCheckTime", "<date>2000-01-01T00:00:00Z</date>"]
    app.launch()

    let install = app.buttons["Install Update"].firstMatch
    XCTAssertTrue(install.waitForExistence(timeout: 30))
    install.click()
    let relaunch = app.buttons["Install and Relaunch"].firstMatch
    XCTAssertTrue(relaunch.waitForExistence(timeout: 60), "Signed archive downloads and validates")
    relaunch.click()
    XCTAssertTrue(app.wait(for: .notRunning, timeout: 30), "Old version quits for the installer")
  }
}
