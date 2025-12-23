-- Sessions table
CREATE TABLE IF NOT EXISTS sessions (
  session_id VARCHAR(128) PRIMARY KEY,
  user_id VARCHAR(64) NOT NULL,
  device_id VARCHAR(64),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  expires_at TIMESTAMPTZ NOT NULL,
  revoked_at TIMESTAMPTZ,
  last_seen_at TIMESTAMPTZ,
  ip INET,
  ua TEXT
);

-- Refresh tokens table
CREATE TABLE IF NOT EXISTS refresh_tokens (
  id BIGSERIAL PRIMARY KEY,
  session_id VARCHAR(128) REFERENCES sessions(session_id) ON DELETE CASCADE,
  token_hash VARCHAR(128) UNIQUE NOT NULL,
  expires_at TIMESTAMPTZ NOT NULL,
  revoked_at TIMESTAMPTZ,
  rotated_from_id BIGINT REFERENCES refresh_tokens(id)
);

-- Optional devices table
CREATE TABLE IF NOT EXISTS devices (
  device_id VARCHAR(64) PRIMARY KEY,
  user_id VARCHAR(64) NOT NULL,
  platform VARCHAR(32),
  model VARCHAR(128),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_sessions_user_id ON sessions(user_id);
CREATE INDEX IF NOT EXISTS idx_refresh_tokens_session_id ON refresh_tokens(session_id);
