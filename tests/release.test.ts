import { describe, expect, test } from "bun:test";
import {
  parseAppcast,
  releaseItem,
  renderAppcast,
  verifyEdSignature,
} from "../scripts/appcast";
import {
  compareReleaseVersions,
  nextReleaseVersion,
  releaseVersionForCommit,
} from "../scripts/release-version";

describe("release versions", () => {
  const now = new Date("2026-10-21T15:00:00Z");

  test("first release of the day is .1", () => {
    expect(nextReleaseVersion({ now, tags: [] })).toBe("20261021.1");
    expect(nextReleaseVersion({ now, tags: ["20261020.4"] })).toBe(
      "20261021.1",
    );
  });

  test("counts past .9 numerically, ignoring unrelated tags", () => {
    const tags = [
      "20261021.1",
      "20261021.9",
      "20261021.10",
      "v1.0.0",
      "20261021.x",
    ];
    expect(nextReleaseVersion({ now, tags })).toBe("20261021.11");
  });

  test("uses the UTC date, not the runner's local date", () => {
    // 23:30 on Oct 21 in Los Angeles is already Oct 22 in UTC.
    const lateInLosAngeles = new Date("2026-10-21T23:30:00-07:00");
    expect(
      nextReleaseVersion({ now: lateInLosAngeles, tags: ["20261021.3"] }),
    ).toBe("20261022.1");
  });

  test("orders by date then counter", () => {
    const sorted = [
      "20261022.1",
      "20261021.10",
      "20261021.9",
      "20261021.2",
    ].sort(compareReleaseVersions);
    expect(sorted).toEqual([
      "20261021.2",
      "20261021.9",
      "20261021.10",
      "20261022.1",
    ]);
  });

  test("a rerun on an already released commit reuses its tag", () => {
    expect(
      releaseVersionForCommit({
        now,
        tags: ["20261020.2", "20261021.1"],
        commitTags: ["20261020.2", "nightly"],
      }),
    ).toEqual({ version: "20261020.2", existing: true });
    expect(
      releaseVersionForCommit({
        now,
        tags: ["20261021.1"],
        commitTags: ["nightly"],
      }),
    ).toEqual({ version: "20261021.2", existing: false });
  });
});

describe("appcast", () => {
  test("points at the tagged release asset and round-trips", () => {
    const item = releaseItem({
      version: "20261021.2",
      edSignature: "c2lnbmF0dXJl",
      length: 1234,
      pubDate: new Date("2026-10-21T12:00:00Z"),
    });
    const xml = renderAppcast(item);
    expect(parseAppcast(xml)).toEqual({
      version: "20261021.2",
      url: "https://github.com/dakdevs/tot/releases/download/20261021.2/Tot.zip",
      edSignature: "c2lnbmF0dXJl",
      length: 1234,
    });
    expect(xml).toContain(
      "<sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>",
    );
    expect(xml).toContain("<pubDate>Wed, 21 Oct 2026 12:00:00 GMT</pubDate>");
  });

  test("escapes change notes inside the description", () => {
    const xml = renderAppcast(
      releaseItem({
        version: "20261021.3",
        edSignature: "c2ln",
        length: 1,
        pubDate: new Date(),
        notes: ["Fix <b> & ]]> handling"],
      }),
    );
    expect(xml).toContain("<li>Fix &lt;b&gt; &amp; ]]&gt; handling</li>");
    expect(xml.match(/\]\]>/g)?.length).toBe(1);
    expect(xml).toContain(
      '<a href="https://github.com/dakdevs/tot/releases/tag/20261021.3">',
    );
  });

  test("rejects feeds without exactly one complete item", () => {
    expect(() => parseAppcast("<rss><channel></channel></rss>")).toThrow();
    expect(() =>
      parseAppcast("<item><sparkle:version>1</sparkle:version></item>"),
    ).toThrow();
  });

  test("EdDSA verification accepts the signed archive and rejects any change", async () => {
    const keys = await crypto.subtle.generateKey("Ed25519", true, [
      "sign",
      "verify",
    ]);
    const publicKey = Buffer.from(
      await crypto.subtle.exportKey("raw", keys.publicKey),
    ).toString("base64");
    const data = new TextEncoder().encode("Tot.zip bytes");
    const signature = Buffer.from(
      await crypto.subtle.sign("Ed25519", keys.privateKey, data),
    ).toString("base64");

    expect(await verifyEdSignature({ publicKey, signature, data })).toBe(true);
    const tampered = data.slice();
    tampered[0] ^= 1;
    expect(
      await verifyEdSignature({ publicKey, signature, data: tampered }),
    ).toBe(false);
  });
});
