# Local services map (ports, creds, logs)

Quick reference for reaching the running services during dev. All services start from their own
subrepo. For UI work, Claude can attach to the running dev server via the preview tool (see
`.claude/launch.json`) and inspect the live DOM / computed CSS — prefer that over guessing at layout.

## match (Java/Spring + React)

| Thing | Where |
|---|---|
| portal-admin backend | `http://localhost:9080` (main class `AdminPortalMain`) |
| portal-admin frontend (Vite) | `http://localhost:5173` — proxies `/api` → backend `:9080` (preview name `portal-admin`) |
| contextual-analytics frontend (Vite) | `http://localhost:3000` (preview name `contextual-analytics`) |
| Postgres | local DB `match`, multi-schema (`match`, `build`, `public`); admin user in `portal_admin_user` |
| Pub/Sub emulator | `localhost:2222` |
| Compass proxy | backend `/compass/proxy/*` → hamster REST |

Note: a locally-run match reads workflow runs/triggers from the **DEV** orchestrator, not local
`jobmeta` — see memory `project_match_points_at_dev_orchestrator`.

## hamster (Kotlin/Compass)

| Thing | Where |
|---|---|
| REST API | `http://localhost:8090` — health: `GET /actuator/health` |
| Postgres | `postgresql://dev:password@localhost:15433/hamster` (uuid ids, `revision_id`/`is_latest` revisioning; `account_id` = match id as string) |
| CLI | `hamster/compass-cli` (`compass`) — preferred over hand-rolled curl for a running hamster |
| Local infra | `docker-compose -p hamster up -d` (Postgres + BigTable emulator) |

## orchestrator

| Thing | Where |
|---|---|
| Pub/Sub emulator | `localhost:2222` (topics `jobCreateRequestTopic`, `portalJobCompletedTopic`) |
| Postgres | local `jobmeta` DB |

## Logs

Services are usually run from the IDE / a terminal, so logs go to the console, not a fixed file.
Fastest paths for Claude: hit an endpoint (`curl` / `compass` CLI), query the DB (`psql`), or the
user pastes the stacktrace (that is how the HubSpot metadata 500 was diagnosed). If a service is
started with output redirected to a file, point Claude at the path and it can tail it.

Local read/verify commands (`curl`, `psql`, `lsof`, `pnpm` gates, read-only `git`) are allowlisted in
`.claude/settings.local.json` so they don't prompt. `git commit` / `git push` are intentionally NOT
allowlisted — those still wait for an explicit request.
