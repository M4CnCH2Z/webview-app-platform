# Bridge Contract

Contract-first schema for WebView bridge messages.

## Message shapes
- Request: `{ id, version, type, payload }`
- Response: `{ id, ok, payload?, error? }`

## Capabilities
- Negotiation: `capabilities.request` -> `{ appVersion, bridgeVersion, supported }`
- Minimum examples: `auth.getSession`, `nav.openExternal`, `device.getPushToken`, `media.pickImage`

## Error codes
`PERMISSION_DENIED`, `NOT_SUPPORTED`, `INVALID_PAYLOAD`, `INVALID_ORIGIN`, `TIMEOUT`, `INTERNAL_ERROR`

## Semver
- MAJOR for breaking schema changes
- MINOR for additive capabilities
- PATCH for fixes
- Android and Web enforce major compatibility; CI should diff schemas and block breaking changes without MAJOR bump.
