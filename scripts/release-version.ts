// Date-based release versions: `YYYYMMDD.N`, where the date is UTC and N counts that day's releases from 1.
// Sparkle compares CFBundleVersion numerically per component, so 20261021.10 > 20261021.9 and the next
// day's .1 sorts after every earlier counter.

const versionPattern = /^(\d{8})\.([1-9]\d*)$/;

export function utcDateStamp(now: Date): string {
  return now.toISOString().slice(0, 10).replaceAll("-", "");
}

export function isReleaseVersion(value: string): boolean {
  return versionPattern.test(value);
}

/** Orders two release versions by date, then by counter, numerically. */
export function compareReleaseVersions(a: string, b: string): number {
  const [aDate, aCount] = a.split(".").map(Number);
  const [bDate, bCount] = b.split(".").map(Number);
  return aDate - bDate || aCount - bCount;
}

/** The next free version for `now`, given every existing tag name; non-release tags are ignored. */
export function nextReleaseVersion({
  now,
  tags,
}: {
  now: Date;
  tags: readonly string[];
}): string {
  const date = utcDateStamp(now);
  const latest = tags.reduce((highest, tag) => {
    const match = versionPattern.exec(tag);
    if (match?.[1] !== date) return highest;
    return Math.max(highest, Number(match[2]));
  }, 0);
  return `${date}.${latest + 1}`;
}

/**
 * Reuses a release tag already on the commit so reruns of the same commit publish nothing new;
 * otherwise allocates the next version. Picks the highest when a commit somehow carries several.
 */
export function releaseVersionForCommit({
  now,
  tags,
  commitTags,
}: {
  now: Date;
  tags: readonly string[];
  commitTags: readonly string[];
}): { version: string; existing: boolean } {
  const existing = commitTags
    .filter(isReleaseVersion)
    .sort(compareReleaseVersions)
    .at(-1);
  return existing
    ? { version: existing, existing: true }
    : { version: nextReleaseVersion({ now, tags }), existing: false };
}

if (import.meta.main) {
  const git = (...args: string[]) => {
    const run = Bun.spawnSync(["git", ...args], { stderr: "inherit" });
    if (!run.success) throw new Error(`git ${args.join(" ")} failed`);
    return run.stdout.toString().split("\n").filter(Boolean);
  };
  const result = releaseVersionForCommit({
    now: new Date(),
    tags: git("tag", "--list"),
    commitTags: git("tag", "--points-at", "HEAD"),
  });
  console.log(`version=${result.version}\nexisting=${result.existing}`);
}
