import { releaseItem, renderAppcast } from "../scripts/appcast";

/**
 * Serves the updater fixtures Sparkle needs over HTTP: a feed at the running version, a feed with a
 * newer release, and an archive signed with a key that isn't Tot's, so installing it must fail.
 */
export async function startUpdateFixtureServer() {
  const archive = new Uint8Array(4096).fill(7);
  const keys = await crypto.subtle.generateKey("Ed25519", false, [
    "sign",
    "verify",
  ]);
  const foreignSignature = Buffer.from(
    await crypto.subtle.sign("Ed25519", keys.privateKey, archive),
  ).toString("base64");
  const server = Bun.serve({
    hostname: "127.0.0.1",
    port: 0,
    fetch(request) {
      const { pathname } = new URL(request.url);
      if (pathname === "/Tot.zip") return new Response(archive);
      // Debug builds are version 0; release versions are YYYYMMDD.N.
      const version = { "/current.xml": "0", "/newer.xml": "20991231.1" }[
        pathname
      ];
      if (!version) return new Response("not found", { status: 404 });
      const item = releaseItem({
        version,
        edSignature: foreignSignature,
        length: archive.length,
        pubDate: new Date(),
        notes: ["Fixture release for UI tests"],
      });
      item.url = new URL("/Tot.zip", server.url).href;
      return new Response(renderAppcast(item), {
        headers: { "content-type": "application/xml" },
      });
    },
  });
  return server;
}

if (import.meta.main) {
  const server = await startUpdateFixtureServer();
  console.log(server.url.href);
}
