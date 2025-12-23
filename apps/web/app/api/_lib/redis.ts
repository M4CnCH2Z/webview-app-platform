import Redis from "ioredis";

declare global {
  // eslint-disable-next-line no-var
  var __redisClient: Redis | undefined;
}

const redisUrl = process.env.REDIS_URL ?? "redis://localhost:6379";

const client = global.__redisClient ?? new Redis(redisUrl);
if (!global.__redisClient) {
  global.__redisClient = client;
}

export const redis = client;
