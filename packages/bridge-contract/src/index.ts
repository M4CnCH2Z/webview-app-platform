import { z } from "zod";
import { versions } from "./versions";

export const BridgeErrorCodes = {
  PERMISSION_DENIED: "PERMISSION_DENIED",
  NOT_SUPPORTED: "NOT_SUPPORTED",
  INVALID_PAYLOAD: "INVALID_PAYLOAD",
  INVALID_ORIGIN: "INVALID_ORIGIN",
  TIMEOUT: "TIMEOUT",
  INTERNAL_ERROR: "INTERNAL_ERROR"
} as const;

export type BridgeErrorCode = (typeof BridgeErrorCodes)[keyof typeof BridgeErrorCodes];

export const payloadSchema = z.record(z.string(), z.any());

export const requestSchema = z.object({
  id: z.string(),
  version: z.string(),
  type: z.string(),
  payload: z.unknown()
});

export type BridgeRequest = z.infer<typeof requestSchema>;

export const responseSchema = z.object({
  id: z.string(),
  ok: z.boolean(),
  payload: z.unknown().optional(),
  error: z
    .object({
      code: z.nativeEnum(BridgeErrorCodes),
      message: z.string().optional()
    })
    .optional()
});

export type BridgeResponse = z.infer<typeof responseSchema>;

// Capability negotiation
export const capability = z.enum([
  "auth.getSession",
  "nav.openExternal",
  "device.getPushToken",
  "media.pickImage"
]);

export type Capability = z.infer<typeof capability>;

export const capabilitiesRequestSchema = requestSchema.extend({
  type: z.literal("capabilities.request")
});

export const capabilitiesResponseSchema = responseSchema.extend({
  ok: z.literal(true),
  payload: z.object({
    appVersion: z.string(),
    bridgeVersion: z.string(),
    supported: z.array(capability)
  })
});

export type CapabilitiesResponse = z.infer<typeof capabilitiesResponseSchema>;

export const authGetSessionRequestSchema = requestSchema.extend({
  type: z.literal("auth.getSession"),
  payload: z.object({})
});

export const authGetSessionResponseSchema = responseSchema.extend({
  payload: z
    .object({
      sessionId: z.string().nullable(),
      userId: z.string().nullable()
    })
    .optional()
});

export const navOpenExternalRequestSchema = requestSchema.extend({
  type: z.literal("nav.openExternal"),
  payload: z.object({
    url: z.string().url()
  })
});

export const deviceGetPushTokenRequestSchema = requestSchema.extend({
  type: z.literal("device.getPushToken"),
  payload: z.object({})
});

export const mediaPickImageRequestSchema = requestSchema.extend({
  type: z.literal("media.pickImage"),
  payload: z.object({
    maxSizeBytes: z.number().optional()
  })
});

export const schemaByType: Record<string, z.ZodTypeAny> = {
  "capabilities.request": capabilitiesRequestSchema,
  "auth.getSession": authGetSessionRequestSchema,
  "nav.openExternal": navOpenExternalRequestSchema,
  "device.getPushToken": deviceGetPushTokenRequestSchema,
  "media.pickImage": mediaPickImageRequestSchema
};

export const supportedVersionRange = versions.bridgeRange;

export const isCompatibleVersion = (version: string) => {
  // Simple semver prefix check for skeleton; enforce major compatibility
  const [major] = version.split(".");
  const [supportedMajor] = supportedVersionRange.split(".");
  return major === supportedMajor;
};
