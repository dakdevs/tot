# Architecture

How Tot reads T3 Code, what it shows, and where it falls short. Setup is in the [README](../README.md);
releases and updates are in [releasing.md](releasing.md).

## Behavior

- **Floating panel.** Sits at the bottom right of the screen, 360 pt wide, above the Dock, on every Space and over
  full-screen apps. It never takes focus from the app you're watching.
- **Glass.** Idle, the panel is see-through clear Liquid Glass with a light window-colored tint (Settings → "Idle
  glass tint"); text and icons stay fully opaque. While the pointer is over it, the glass fills with a solid
  window-colored backing. An "Idle opacity" value saved by an earlier build is converted once to the new tint.
- **Working threads.** The list shows top-level threads that are running (spinning ring) or waiting (hourglass),
  each with its project and current activity: the latest tool call or assistant line. A thread whose run ended
  but whose subagent or background tool is still running counts as waiting, matching T3's "Waiting" state. The
  five newest sit nearest the corner; the status bar shows the working count and a spinner.
- **Done count.** The status bar's "N done" button counts top-level threads whose latest run completed or failed
  and that you haven't settled in T3 or cleared here since. Click it to list them instead of the working threads;
  click again to switch back.
- **Thread detail.** Click a thread and its glass morphs into the last three **turns**. Each turn is one user
  input grouped with its tool and assistant continuations. Messages start collapsed to two lines; click to
  expand, click again to collapse. When new messages arrive, the oldest turn slides out the top and the new one
  slides in at the bottom, with a spinner at the bottom right while the thread is receiving. Reduced Motion
  replaces the moves with fades.
- **Icon-only controls.** Back, Open in T3 Code, and Clear. Clear hides one specific completion; if the same
  thread finishes again later, it reappears.
- **Live transitions.** An open working thread keeps updating; when it finishes, the spinner stops, Clear
  appears, and it moves from the working list to the done count.
- **Optional one-line summaries.** Each finished thread can get a one-line summary, written through OpenCode or
  Codex using the CLI's existing login. Models, variants, and service tiers come from the provider's live catalog,
  and custom model IDs are accepted.

## Components

| Piece                    | Source                                       | Notes                                                                                                |
| ------------------------ | -------------------------------------------- | ---------------------------------------------------------------------------------------------------- |
| T3 reader                | `sources/tot-core/t3-database.swift`         | Opens `~/.t3/userdata/statev2.sqlite` read-only (`mode=ro`); polls `PRAGMA data_version` each second |
| Turn grouping            | `sources/tot-core/turn-builder.swift`        | Top-level `turn_items` per run; hides reasoning; folds consecutive tool calls into one entry         |
| Done filter and clearing | `sources/tot-core/cleared-completions.swift` | Clears are keyed by `runId@completedAt` in `~/Library/Application Support/Tot/`                      |
| Glass backing            | `sources/tot-core/overlay-glass.swift`       | Idle tint clamping, solid hover backing, and migration from the old idle-opacity setting             |
| Overlay state            | `sources/tot-core/overlay-model.swift`       | `@Observable` model shared by the panel and the tests                                                |
| Providers                | `sources/tot-core/summary-provider.swift`    | Builds `opencode api post /api/experimental/generate` or `codex exec --ephemeral` calls              |
| Panel and views          | `app/tot/*.swift`                            | `NSPanel` (non-activating, `.statusBar` level) hosting SwiftUI `GlassEffectContainer`                |
| Updates                  | `app/tot/update-controller.swift`            | Sparkle 2 standard updater; see [releasing.md](releasing.md)                                         |

The filename is `Package.swift` because SwiftPM requires it; every other file is kebab-case.

## Provider support (verified 2026-10-21)

- **OpenCode.** Tot uses the running OpenCode background service through `opencode api`, so the CLI handles
  server discovery and auth, and Tot never reads OpenCode's password. Models come from `GET /api/model`.
  `openai/gpt-6-luna-fast` with variant `low` is "GPT-6 Luna Fast Low", served through the ChatGPT subscription
  backend.
- **Codex.** Tot runs `codex exec --ephemeral --ignore-user-config -s read-only` with the CLI's ChatGPT login,
  passing `-c model_reasoning_effort=<effort>` and an optional `-c service_tier=priority` ("Fast"). Models come
  from `codex debug models`. Each call costs about 7k tokens.
- **How this compares to Hex.** Hex (now `anomalyco/hex`, a Rust/GPUI app; the original Swift/TCA
  `kitlangton/Hex` is archived) talks only to OpenCode. It finds the background service, lists `/api/model`, and
  posts to `/api/experimental/generate` with `{providerID, id, variant}`. Tot follows the same contract. Hex has
  no Codex path; Tot adds one.

## Limitations

- **Opening a thread.** T3 Code's desktop app has no thread deep link: `t3code://` is registered only for auth
  returns. "Open in T3 Code" brings the app forward without selecting the thread. A Settings toggle instead opens
  the exact web route `http://127.0.0.1:3773/<environmentId>/<threadId>`, which needs a signed-in browser session.
- **Clearing is local to Tot.** T3's own `thread.settle` command requires an authenticated WebSocket session with
  the `orchestration:operate` scope. Tot does not pair with T3, so it never changes T3 state. Threads you settle
  in T3 do disappear from Tot.
- **The database schema isn't a stable API.** Tot reads T3's internal SQLite projections, which change between
  releases. If a T3 update breaks the queries, the status bar shows the error instead of an empty list. The
  supported alternative is T3's authenticated `/ws` RPC (`orchestration.subscribeShell`).
- **Waiting state is approximate.** It's inferred from unfinished subagent and tool items, which is the same
  condition as T3's `shell_pending` index. T3's server-computed runtime state can differ briefly.
- **Summaries are sent as a command-line argument.** The OpenCode prompt, which contains the last turn's
  transcript, goes to `opencode api` as an argument because that CLI takes the request body only as an argument.
  Other local processes can see it while the call runs.
