import { expect, test } from "bun:test";

// `bun test` entry point for the Swift Testing suite in tests/tot-core-tests.
test(
  "Swift unit tests pass",
  () => {
    const run = Bun.spawnSync(["swift", "test"], {
      cwd: `${import.meta.dir}/..`,
      stderr: "pipe",
    });
    const output = run.stdout.toString() + run.stderr.toString();
    if (run.exitCode !== 0) console.error(output);
    expect(run.exitCode).toBe(0);
    const summary = output.match(
      /Test run with (\d+) tests? in \d+ suites? passed/,
    );
    expect(Number(summary?.[1])).toBeGreaterThan(0);
  },
  { timeout: 600_000 },
);
