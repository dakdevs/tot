import { expect, test } from "bun:test";
import { startUpdateFixtureServer } from "./update-fixture-server";

const root = `${import.meta.dir}/..`;

// Runs the XCUITest suite, which launches Tot.app against a fixture T3 database and local update
// feeds and drives the real overlay panel and Sparkle UI, then confirms every UI test actually ran.
test(
  "overlay and updater UI tests pass",
  async () => {
    const server = await startUpdateFixtureServer();
    try {
      // The install test needs Tot's private signing key (scripts/verify-update-install.sh), and the
      // README capture needs a backdrop (scripts/capture-readme-screenshots.sh).
      const run = Bun.spawn(
        [
          "scripts/run-ui-tests.sh",
          "-skip-testing:TotUITests/UpdateInstallUITests",
          "-skip-testing:TotUITests/ReadmeScreenshotUITests",
        ],
        {
          cwd: root,
          stdout: "pipe",
          stderr: "pipe",
          // xcodebuild forwards TEST_RUNNER_-prefixed variables to the UI test process.
          env: {
            ...process.env,
            TEST_RUNNER_TOT_UPDATE_FIXTURE_URL: server.url.href,
          },
        },
      );
      const [stdout, stderr, exitCode] = await Promise.all([
        new Response(run.stdout).text(),
        new Response(run.stderr).text(),
        run.exited,
      ]);
      if (exitCode !== 0) console.error((stdout + stderr).slice(-8_000));
      expect(exitCode).toBe(0);
    } finally {
      server.stop(true);
    }

    const summary = Bun.spawnSync(
      [
        "xcrun",
        "xcresulttool",
        "get",
        "test-results",
        "summary",
        "--path",
        "build/ui.xcresult",
      ],
      { cwd: root },
    );
    const result = JSON.parse(summary.stdout.toString());
    expect(result.result).toBe("Passed");
    expect(result.failedTests).toBe(0);
    expect(result.skippedTests).toBe(0);
    expect(result.passedTests).toBeGreaterThanOrEqual(7);
  },
  { timeout: 900_000 },
);
