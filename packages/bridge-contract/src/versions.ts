export const versions = {
  bridge: "1.0.0",
  bridgeRange: "1.x",
  minWeb: "0.1.0",
  minApp: "0.1.0"
} as const;

export const semverPolicy = `
- Breaking bridge changes bump MAJOR (requires app+web updates)
- Additive non-breaking bridge changes bump MINOR
- Fixes bump PATCH
- Web must send its bridge version; Android validates compatibility (major match)
- CI idea: compare current contract with previous tag, fail if schema breaking without MAJOR bump
`;
