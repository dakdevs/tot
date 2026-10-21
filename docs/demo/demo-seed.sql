-- Mock threads for the README screenshots (scripts/capture-readme-screenshots.sh). Load after
-- tests/fixtures/t3-schema.sql. Times are relative to now so the overlay shows recent activity.
CREATE TEMP VIEW t AS SELECT
  strftime('%Y-%m-%dT%H:%M:%fZ', 'now', '-40 minutes') AS m40,
  strftime('%Y-%m-%dT%H:%M:%fZ', 'now', '-30 minutes') AS m30,
  strftime('%Y-%m-%dT%H:%M:%fZ', 'now', '-25 minutes') AS m25,
  strftime('%Y-%m-%dT%H:%M:%fZ', 'now', '-20 minutes') AS m20,
  strftime('%Y-%m-%dT%H:%M:%fZ', 'now', '-15 minutes') AS m15,
  strftime('%Y-%m-%dT%H:%M:%fZ', 'now', '-12 minutes') AS m12,
  strftime('%Y-%m-%dT%H:%M:%fZ', 'now', '-8 minutes') AS m8,
  strftime('%Y-%m-%dT%H:%M:%fZ', 'now', '-4 minutes') AS m4,
  strftime('%Y-%m-%dT%H:%M:%fZ', 'now', '-1 minutes') AS m1;

INSERT INTO projection_projects (project_id, title, workspace_root, scripts_json, created_at, updated_at)
SELECT 'p-shop', 'storefront', '/tmp/storefront', '[]', m40, m40 FROM t UNION ALL
SELECT 'p-api', 'billing-api', '/tmp/billing-api', '[]', m40, m40 FROM t UNION ALL
SELECT 'p-docs', 'handbook', '/tmp/handbook', '[]', m40, m40 FROM t;

INSERT INTO orchestration_v2_projection_threads
  (thread_id, project_id, title, default_provider, runtime_mode, interaction_mode, created_at, updated_at, archived_at, payload_json)
SELECT 'checkout', 'p-shop', 'Speed up checkout page', 'codex', 'full-access', 'default', m40, m1, NULL, '{}' FROM t UNION ALL
SELECT 'webhooks', 'p-api', 'Retry failed webhooks', 'claudeAgent', 'full-access', 'default', m40, m1, NULL, '{}' FROM t UNION ALL
SELECT 'audit', 'p-api', 'Audit dependency licenses', 'codex', 'full-access', 'default', m40, m4, NULL, '{}' FROM t UNION ALL
SELECT 'darkmode', 'p-shop', 'Add dark mode toggle', 'codex', 'full-access', 'default', m40, m8, NULL, '{}' FROM t UNION ALL
SELECT 'onboarding', 'p-docs', 'Rewrite onboarding guide', 'claudeAgent', 'full-access', 'default', m40, m20, NULL, '{}' FROM t UNION ALL
SELECT 'flaky', 'p-api', 'Fix flaky invoice test', 'codex', 'full-access', 'default', m40, m30, NULL, '{}' FROM t;

INSERT INTO orchestration_v2_projection_runs (run_id, thread_id, ordinal, provider, status, requested_at, completed_at, payload_json)
SELECT 'checkout-1', 'checkout', 1, 'codex', 'running', m4, NULL, '{}' FROM t UNION ALL
SELECT 'webhooks-1', 'webhooks', 1, 'claudeAgent', 'running', m8, NULL, '{}' FROM t UNION ALL
SELECT 'audit-1', 'audit', 1, 'codex', 'completed', m12, m4, '{}' FROM t UNION ALL
SELECT 'darkmode-1', 'darkmode', 1, 'codex', 'completed', m40, m30, '{}' FROM t UNION ALL
SELECT 'darkmode-2', 'darkmode', 2, 'codex', 'completed', m25, m20, '{}' FROM t UNION ALL
SELECT 'darkmode-3', 'darkmode', 3, 'codex', 'completed', m12, m8, '{}' FROM t UNION ALL
SELECT 'onboarding-1', 'onboarding', 1, 'claudeAgent', 'completed', m30, m20, '{}' FROM t UNION ALL
SELECT 'flaky-1', 'flaky', 1, 'codex', 'failed', m40, m30, '{}' FROM t;

INSERT INTO orchestration_v2_projection_turn_items (turn_item_id, thread_id, run_id, parent_item_id, ordinal, type, status, updated_at, payload_json)
SELECT 'c-1', 'checkout', 'checkout-1', NULL, 1, 'user_message', 'completed', m4, '{"text":"Profile the checkout page and cut its load time"}' FROM t UNION ALL
SELECT 'c-2', 'checkout', 'checkout-1', NULL, 2, 'command_execution', 'running', m1, '{"input":"bun run lighthouse /checkout"}' FROM t UNION ALL
SELECT 'w-1', 'webhooks', 'webhooks-1', NULL, 1, 'user_message', 'completed', m8, '{"text":"Retry webhooks that failed during the outage"}' FROM t UNION ALL
SELECT 'w-2', 'webhooks', 'webhooks-1', NULL, 2, 'assistant_message', 'completed', m1, '{"text":"Found 214 failed deliveries; replaying them in batches of 20.","streaming":true}' FROM t UNION ALL
SELECT 'a-1', 'audit', 'audit-1', NULL, 1, 'user_message', 'completed', m12, '{"text":"List any dependency with a copyleft license"}' FROM t UNION ALL
SELECT 'a-2', 'audit', 'audit-1', NULL, 2, 'subagent', 'running', m4, '{"title":"Scan transitive dependencies"}' FROM t UNION ALL
SELECT 'd-1', 'darkmode', 'darkmode-1', NULL, 1, 'user_message', 'completed', m40, '{"text":"Add a dark mode toggle to the header"}' FROM t UNION ALL
SELECT 'd-2', 'darkmode', 'darkmode-1', NULL, 2, 'file_change', 'completed', m30, '{"fileName":"/tmp/storefront/src/header.tsx"}' FROM t UNION ALL
SELECT 'd-3', 'darkmode', 'darkmode-1', NULL, 3, 'assistant_message', 'completed', m30, '{"text":"Added the toggle; it follows the system setting until you pick one.","streaming":false}' FROM t UNION ALL
SELECT 'd-4', 'darkmode', 'darkmode-2', NULL, 1, 'user_message', 'completed', m25, '{"text":"Remember the choice across visits"}' FROM t UNION ALL
SELECT 'd-5', 'darkmode', 'darkmode-2', NULL, 2, 'assistant_message', 'completed', m20, '{"text":"The choice is now saved in localStorage and applied before first paint, so there is no flash.","streaming":false}' FROM t UNION ALL
SELECT 'd-6', 'darkmode', 'darkmode-3', NULL, 1, 'user_message', 'completed', m12, '{"text":"Check contrast on the product cards"}' FROM t UNION ALL
SELECT 'd-7', 'darkmode', 'darkmode-3', NULL, 2, 'command_execution', 'completed', m8, '{"input":"bun run test:a11y"}' FROM t UNION ALL
SELECT 'd-8', 'darkmode', 'darkmode-3', NULL, 3, 'assistant_message', 'completed', m8, '{"text":"Two card prices were below 4.5:1 in dark mode. I darkened the surface token; all contrast checks pass now.","streaming":false}' FROM t UNION ALL
SELECT 'o-1', 'onboarding', 'onboarding-1', NULL, 1, 'user_message', 'completed', m30, '{"text":"Rewrite the onboarding guide for new contributors"}' FROM t UNION ALL
SELECT 'o-2', 'onboarding', 'onboarding-1', NULL, 2, 'assistant_message', 'completed', m20, '{"text":"Rewrote the guide around a 15-minute first run.","streaming":false}' FROM t UNION ALL
SELECT 'f-1', 'flaky', 'flaky-1', NULL, 1, 'user_message', 'completed', m40, '{"text":"Fix the flaky invoice rounding test"}' FROM t UNION ALL
SELECT 'f-2', 'flaky', 'flaky-1', NULL, 2, 'error', 'failed', m30, '{"failure":{"message":"Usage limit reached"}}' FROM t;
