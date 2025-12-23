# Session & Token Model

- Postgres: `sessions`, `refresh_tokens`, `devices` as canonical state (see infra/migrations/001_init.sql).
- Postgres app data: `users`, `posts` (see infra/migrations/002_users_posts.sql); posts `author_id` references users.
- Redis:
  - `sess:{session_id}` -> cached snapshot (TTL 5-30m)
  - `deny:{session_id}` -> `1` (TTL until session expiry) for revocations
  - `rl:{ip}:{route}` -> rate limiting
- Flow:
  1. Request reads Redis `deny:*`; if present, reject.
  2. Attempt Redis `sess:*`; on miss, load from Postgres and repopulate cache.
  3. Refresh rotation writes new token, sets `rotated_from_id` and updates cache.
  4. Revocation writes `deny:*` to immediately block while DB write commits.
- Security: SameSite=Lax session cookie, CSRF via Origin/Referer allowlist, capabilities-gated bridge actions.
