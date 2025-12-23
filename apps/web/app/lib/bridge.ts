import { v4 as uuid } from "uuid";
import {
  capability,
  type Capability,
  type BridgeRequest,
  type BridgeResponse,
  requestSchema,
  responseSchema
} from "@platform/bridge-contract";

type Listener = (event: MessageEvent) => void;

const BRIDGE_VERSION = "1.0.0";

const isWeb = typeof window !== "undefined";

const postMessage = (payload: BridgeRequest) => {
  if (!isWeb) return;
  if (window.ReactNativeWebView?.postMessage) {
    window.ReactNativeWebView.postMessage(JSON.stringify(payload));
    return;
  }
  if ((window as any).__nativeBridge?.postMessage) {
    (window as any).__nativeBridge.postMessage(JSON.stringify(payload));
    return;
  }
  console.warn("No bridge transport detected");
};

const once = (handler: (data: BridgeResponse) => void): Listener => {
  const listener = (event: MessageEvent) => {
    try {
      const parsed = responseSchema.safeParse(JSON.parse(event.data));
      if (parsed.success) {
        handler(parsed.data);
      }
    } catch (err) {
      console.warn("Bridge response parse failed", err);
    } finally {
      window.removeEventListener("message", listener);
    }
  };
  window.addEventListener("message", listener);
  return listener;
};

export const sendBridgeRequest = async <T = unknown>(
  type: string,
  payload: unknown
): Promise<T | null> => {
  if (!isWeb) return null;
  const message: BridgeRequest = {
    id: uuid(),
    version: BRIDGE_VERSION,
    type,
    payload
  };
  const validation = requestSchema.safeParse(message);
  if (!validation.success) throw new Error("Invalid bridge message");

  return new Promise<T | null>((resolve, reject) => {
    const timeout = setTimeout(() => reject(new Error("Bridge timeout")), 3000);
    once((response) => {
      clearTimeout(timeout);
      if (response.ok) {
        resolve((response.payload as T) ?? (null as any));
      } else {
        reject(new Error(response.error?.code ?? "UNKNOWN"));
      }
    });
    postMessage(message);
  });
};

export const getCapabilities = async () => {
  const res = await sendBridgeRequest<{
    appVersion: string;
    bridgeVersion: string;
    supported: Capability[];
  }>("capabilities.request", {});
  if (!res) return null;
  const parsed = capability.array().safeParse(res.supported);
  if (!parsed.success) return null;
  return res;
};
