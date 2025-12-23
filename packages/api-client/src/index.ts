import { z } from "zod";

const sessionSchema = z.object({
  sessionId: z.string().nullable(),
  userId: z.string().nullable()
});

type Session = z.infer<typeof sessionSchema>;

type Fetcher = typeof fetch;

const parseJson = async <T>(res: Response, schema: z.ZodType<T>): Promise<T> => {
  const data = await res.json();
  const parsed = schema.safeParse(data);
  if (!parsed.success) {
    throw new Error("Invalid response shape");
  }
  return parsed.data;
};

export const createApiClient = (baseUrl: string, fetcher: Fetcher = fetch) => ({
  session: async (): Promise<Session> => {
    const res = await fetcher(`${baseUrl}/api/session`, { credentials: "include" });
    if (!res.ok) throw new Error("Failed to load session");
    return parseJson(res, sessionSchema);
  },
  login: async (username: string, password: string): Promise<Session> => {
    const res = await fetcher(`${baseUrl}/api/auth/login`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      credentials: "include",
      body: JSON.stringify({ username, password })
    });
    if (!res.ok) throw new Error("Login failed");
    return parseJson(res, sessionSchema);
  },
  logout: async (): Promise<void> => {
    await fetcher(`${baseUrl}/api/auth/logout`, { method: "POST", credentials: "include" });
  }
});
