// Renders and verifies Tot's Sparkle appcast. Each release publishes a one-item appcast.xml; the app
// reads it from GitHub's `releases/latest/download/` alias, which never resolves to drafts or prereleases.

export const repository = "dakdevs/tot";
export const archiveName = "Tot.zip";
export const minimumSystemVersion = "26.0";

export type AppcastItem = {
  version: string;
  url: string;
  edSignature: string;
  length: number;
  pubDate: Date;
  minimumSystemVersion: string;
  releaseURL: string;
  /** Change summaries, shown as a list in Sparkle's update alert. */
  notes: readonly string[];
};

const escape = (value: string) =>
  value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");

export function releaseItem({
  version,
  edSignature,
  length,
  pubDate,
  notes = [],
}: {
  version: string;
  edSignature: string;
  length: number;
  pubDate: Date;
  notes?: readonly string[];
}): AppcastItem {
  const base = `https://github.com/${repository}/releases`;
  return {
    version,
    url: `${base}/download/${version}/${archiveName}`,
    edSignature,
    length,
    pubDate,
    minimumSystemVersion,
    releaseURL: `${base}/tag/${version}`,
    notes,
  };
}

export function renderAppcast(item: AppcastItem): string {
  const v = escape(item.version);
  const notes = item.notes.map((note) => `<li>${escape(note)}</li>`).join("");
  const description = `${notes ? `<ul>${notes}</ul>` : ""}<p><a href="${escape(item.releaseURL)}">Release on GitHub</a></p>`;
  return `<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Tot</title>
    <item>
      <title>Tot ${v}</title>
      <pubDate>${item.pubDate.toUTCString()}</pubDate>
      <sparkle:version>${v}</sparkle:version>
      <sparkle:shortVersionString>${v}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>${escape(item.minimumSystemVersion)}</sparkle:minimumSystemVersion>
      <link>${escape(item.releaseURL)}</link>
      <description><![CDATA[${description}]]></description>
      <enclosure url="${escape(item.url)}" length="${item.length}" type="application/octet-stream" sparkle:edSignature="${escape(item.edSignature)}"/>
    </item>
  </channel>
</rss>
`;
}

/** Reads back the fields Sparkle relies on; throws if the feed doesn't have exactly one well-formed item. */
export function parseAppcast(
  xml: string,
): Pick<AppcastItem, "version" | "url" | "edSignature" | "length"> {
  const items = xml.match(/<item>/g) ?? [];
  if (items.length !== 1)
    throw new Error(`expected 1 appcast item, found ${items.length}`);
  const tag = (name: string) =>
    new RegExp(`<${name}>([^<]+)</${name}>`).exec(xml)?.[1];
  const attribute = (name: string) =>
    new RegExp(`<enclosure[^>]*\\s${name}="([^"]+)"`).exec(xml)?.[1];
  const version = tag("sparkle:version");
  const url = attribute("url");
  const edSignature = attribute("sparkle:edSignature");
  const length = Number(attribute("length"));
  if (!version || !url || !edSignature || !Number.isInteger(length))
    throw new Error(
      "appcast item is missing version, url, signature, or length",
    );
  return { version, url, edSignature, length };
}

/** Verifies a Sparkle EdDSA signature (base64 Ed25519 over the raw archive bytes). */
export async function verifyEdSignature({
  publicKey,
  signature,
  data,
}: {
  publicKey: string;
  signature: string;
  data: Uint8Array;
}): Promise<boolean> {
  const key = await crypto.subtle.importKey(
    "raw",
    Buffer.from(publicKey, "base64"),
    "Ed25519",
    false,
    ["verify"],
  );
  return crypto.subtle.verify(
    "Ed25519",
    key,
    Buffer.from(signature, "base64"),
    data,
  );
}

const plistValue = (appPath: string, key: string) =>
  Bun.spawnSync([
    "/usr/libexec/PlistBuddy",
    "-c",
    `Print :${key}`,
    `${appPath}/Contents/Info.plist`,
  ])
    .stdout.toString()
    .trim();

/**
 * Checks a built release before publishing: the archive matches the appcast's length and EdDSA
 * signature under the public key embedded in the app, and the app's versions match the appcast.
 */
export async function verifyRelease({
  appPath,
  archivePath,
  appcastPath,
}: {
  appPath: string;
  archivePath: string;
  appcastPath: string;
}): Promise<void> {
  const item = parseAppcast(await Bun.file(appcastPath).text());
  const data = await Bun.file(archivePath).bytes();
  if (data.length !== item.length)
    throw new Error(
      `archive is ${data.length} bytes; appcast says ${item.length}`,
    );
  const publicKey = plistValue(appPath, "SUPublicEDKey");
  if (
    !(await verifyEdSignature({ publicKey, signature: item.edSignature, data }))
  )
    throw new Error(
      "archive EdDSA signature does not verify against SUPublicEDKey",
    );
  for (const key of ["CFBundleVersion", "CFBundleShortVersionString"]) {
    const value = plistValue(appPath, key);
    if (value !== item.version)
      throw new Error(`${key} is ${value}; appcast says ${item.version}`);
  }
}

if (import.meta.main) {
  const [command, ...args] = Bun.argv.slice(2);
  if (command === "render") {
    const [version, edSignature, archivePath, notesPath] = args;
    const notes = notesPath
      ? (await Bun.file(notesPath).text()).split("\n").filter(Boolean)
      : [];
    const item = releaseItem({
      version,
      edSignature,
      length: Bun.file(archivePath).size,
      pubDate: new Date(),
      notes,
    });
    process.stdout.write(renderAppcast(item));
  } else if (command === "verify") {
    const [appPath, archivePath, appcastPath] = args;
    await verifyRelease({ appPath, archivePath, appcastPath });
    console.log("appcast, archive signature, and app version agree");
  } else {
    console.error(
      "usage: appcast.ts render <version> <edSignature> <archive> [notes-file] | verify <app> <archive> <appcast>",
    );
    process.exit(2);
  }
}
