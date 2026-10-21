-- Fixture threads covering each case the overlay must distinguish. Load after t3-schema.sql.
INSERT INTO projection_projects (project_id, title, workspace_root, scripts_json, created_at, updated_at)
VALUES ('project-tot', 'tot', '/tmp/tot', '[]', '2026-10-20T00:00:00.000Z', '2026-10-20T00:00:00.000Z');

-- thread, title, payload (lineage / settled state), archived_at
INSERT INTO orchestration_v2_projection_threads
  (thread_id, project_id, title, default_provider, runtime_mode, interaction_mode, created_at, updated_at, archived_at, payload_json)
VALUES
  ('thread-login', 'project-tot', 'Fix login redirect', 'codex', 'full-access', 'default', '2026-10-21T06:00:00.000Z', '2026-10-21T07:00:00.000Z', NULL,
   '{"settledOverride":null,"settledAt":null,"lineage":{"parentThreadId":null}}'),
  ('thread-notes', 'project-tot', 'Write release notes', 'codex', 'full-access', 'default', '2026-10-21T06:00:00.000Z', '2026-10-21T07:00:00.000Z', NULL,
   '{"settledOverride":"settled","settledAt":"2026-10-21T06:30:00.000Z"}'),
  ('thread-parser', 'project-tot', 'Refactor parser', 'codex', 'full-access', 'default', '2026-10-21T06:00:00.000Z', '2026-10-21T07:00:00.000Z', NULL,
   '{}'),
  ('thread-child', 'project-tot', 'Subagent research', 'claudeAgent', 'full-access', 'default', '2026-10-21T06:00:00.000Z', '2026-10-21T07:00:00.000Z', NULL,
   '{"lineage":{"parentThreadId":"thread-login","relationshipToParent":"subagent"}}'),
  ('thread-docs', 'project-tot', 'Update docs', 'codex', 'full-access', 'default', '2026-10-21T06:00:00.000Z', '2026-10-21T07:00:00.000Z', NULL,
   '{}'),
  ('thread-archived', 'project-tot', 'Archived spike', 'codex', 'full-access', 'default', '2026-10-21T06:00:00.000Z', '2026-10-21T07:00:00.000Z', '2026-10-21T06:50:00.000Z',
   '{}'),
  ('thread-waiting', 'project-tot', 'Await subagent', 'codex', 'full-access', 'default', '2026-10-21T06:00:00.000Z', '2026-10-21T07:00:00.000Z', NULL,
   '{}'),
  ('thread-resumed', 'project-tot', 'Resume after settle', 'codex', 'full-access', 'default', '2026-10-21T06:00:00.000Z', '2026-10-21T07:00:00.000Z', NULL,
   '{"settledOverride":"settled","settledAt":"2026-10-21T05:00:00.000Z"}');

INSERT INTO orchestration_v2_projection_runs (run_id, thread_id, ordinal, provider, status, requested_at, completed_at, payload_json) VALUES
  ('run-login-1', 'thread-login', 1, 'codex', 'completed', '2026-10-21T06:00:00.000Z', '2026-10-21T06:05:00.000Z', '{}'),
  ('run-login-2', 'thread-login', 2, 'codex', 'completed', '2026-10-21T06:10:00.000Z', '2026-10-21T06:15:00.000Z', '{}'),
  ('run-login-3', 'thread-login', 3, 'codex', 'completed', '2026-10-21T06:20:00.000Z', '2026-10-21T06:25:00.000Z', '{}'),
  ('run-login-4', 'thread-login', 4, 'codex', 'completed', '2026-10-21T06:40:00.000Z', '2026-10-21T06:45:00.000Z', '{}'),
  ('run-notes-1', 'thread-notes', 1, 'codex', 'completed', '2026-10-21T06:00:00.000Z', '2026-10-21T06:20:00.000Z', '{}'),
  ('run-parser-1', 'thread-parser', 1, 'codex', 'running', '2026-10-21T06:50:00.000Z', NULL, '{}'),
  ('run-child-1', 'thread-child', 1, 'claudeAgent', 'completed', '2026-10-21T06:00:00.000Z', '2026-10-21T06:10:00.000Z', '{}'),
  ('run-docs-1', 'thread-docs', 1, 'codex', 'failed', '2026-10-21T06:00:00.000Z', '2026-10-21T06:30:00.000Z', '{}'),
  ('run-archived-1', 'thread-archived', 1, 'codex', 'completed', '2026-10-21T06:00:00.000Z', '2026-10-21T06:10:00.000Z', '{}'),
  ('run-waiting-1', 'thread-waiting', 1, 'codex', 'completed', '2026-10-21T06:00:00.000Z', '2026-10-21T06:35:00.000Z', '{}'),
  ('run-resumed-1', 'thread-resumed', 1, 'codex', 'completed', '2026-10-21T06:00:00.000Z', '2026-10-21T06:40:00.000Z', '{}');

INSERT INTO orchestration_v2_projection_turn_items (turn_item_id, thread_id, run_id, parent_item_id, ordinal, type, status, updated_at, payload_json) VALUES
  ('login-1-user', 'thread-login', 'run-login-1', NULL, 1, 'user_message', 'completed', '2026-10-21T06:00:00.000Z', '{"text":"Turn one request"}'),
  ('login-1-agent', 'thread-login', 'run-login-1', NULL, 2, 'assistant_message', 'completed', '2026-10-21T06:05:00.000Z', '{"text":"Turn one reply","streaming":false}'),
  ('login-2-user', 'thread-login', 'run-login-2', NULL, 1, 'user_message', 'completed', '2026-10-21T06:10:00.000Z', '{"text":"Turn two request"}'),
  ('login-2-agent', 'thread-login', 'run-login-2', NULL, 2, 'assistant_message', 'completed', '2026-10-21T06:15:00.000Z', '{"text":"Turn two reply","streaming":false}'),
  ('login-3-user', 'thread-login', 'run-login-3', NULL, 1, 'user_message', 'completed', '2026-10-21T06:20:00.000Z', '{"text":"Turn three request"}'),
  ('login-3-think', 'thread-login', 'run-login-3', NULL, 2, 'reasoning', 'completed', '2026-10-21T06:21:00.000Z', '{"text":"private reasoning"}'),
  ('login-3-agent', 'thread-login', 'run-login-3', NULL, 3, 'assistant_message', 'completed', '2026-10-21T06:25:00.000Z', '{"text":"Turn three reply","streaming":false}'),
  ('login-4-user', 'thread-login', 'run-login-4', NULL, 1, 'user_message', 'completed', '2026-10-21T06:40:00.000Z', '{"text":"Fix the login redirect loop"}'),
  ('login-4-read', 'thread-login', 'run-login-4', NULL, 2, 'dynamic_tool', 'completed', '2026-10-21T06:41:00.000Z', '{"title":"Read auth.ts","toolName":"Read","input":{"file_path":"auth.ts"}}'),
  ('login-4-read-child', 'thread-login', 'run-login-4', 'login-4-read', 3, 'dynamic_tool', 'completed', '2026-10-21T06:41:00.000Z', '{"title":"Nested child item"}'),
  ('login-4-cmd', 'thread-login', 'run-login-4', NULL, 4, 'command_execution', 'completed', '2026-10-21T06:42:00.000Z', '{"input":"bun test auth\nsecond line"}'),
  ('login-4-edit', 'thread-login', 'run-login-4', NULL, 5, 'file_change', 'completed', '2026-10-21T06:43:00.000Z', '{"fileName":"/tmp/tot/src/auth.ts"}'),
  ('login-4-agent', 'thread-login', 'run-login-4', NULL, 6, 'assistant_message', 'completed', '2026-10-21T06:45:00.000Z',
   '{"text":"Fixed the redirect loop.\nThe session cookie was cleared before the redirect check.\nI moved the check earlier.\nAll 42 auth tests pass.","streaming":false}'),
  ('parser-1-user', 'thread-parser', 'run-parser-1', NULL, 1, 'user_message', 'completed', '2026-10-21T06:50:00.000Z', '{"text":"Refactor the parser"}'),
  ('parser-1-cmd', 'thread-parser', 'run-parser-1', NULL, 2, 'command_execution', 'running', '2026-10-21T06:51:00.000Z', '{"input":"swift test"}'),
  ('docs-1-user', 'thread-docs', 'run-docs-1', NULL, 1, 'user_message', 'completed', '2026-10-21T06:00:00.000Z', '{"text":"Update the docs"}'),
  ('docs-1-error', 'thread-docs', 'run-docs-1', NULL, 2, 'error', 'failed', '2026-10-21T06:30:00.000Z', '{"failure":{"message":"Usage limit reached"}}'),
  ('waiting-1-subagent', 'thread-waiting', 'run-waiting-1', NULL, 1, 'subagent', 'running', '2026-10-21T06:35:00.000Z', '{"title":"Research"}'),
  ('resumed-1-user', 'thread-resumed', 'run-resumed-1', NULL, 1, 'user_message', 'completed', '2026-10-21T06:00:00.000Z', '{"text":"Resume work"}');
