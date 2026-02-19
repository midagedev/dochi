import * as crypto from "crypto";
import {
  type InitializeParams,
  type InitializeResult,
  type HealthResult,
  type ShutdownResult,
} from "./types";
import { getActiveSessionCount } from "./session";
import { flushAllAudit } from "./hooks";

const startTime = Date.now();
let lastError: string | null = null;
let runtimeSessionId: string | null = null;

export function handleInitialize(params: InitializeParams): InitializeResult {
  runtimeSessionId = crypto.randomUUID();
  console.error(
    `[runtime] initialized: version=${params.runtimeVersion} profile=${params.configProfile} sessionId=${runtimeSessionId}`
  );
  return {
    capabilities: ["session.open", "session.run", "tool.dispatch"],
    runtimeSessionId,
  };
}

export function handleHealth(): HealthResult {
  return {
    alive: true,
    uptimeMs: Date.now() - startTime,
    activeSessions: getActiveSessionCount(),
    lastError,
  };
}

export function handleShutdown(): ShutdownResult {
  console.error("[runtime] shutdown requested");
  // Flush all audit log entries before exit
  flushAllAudit();
  // Schedule process exit after response is sent
  setTimeout(() => process.exit(0), 100);
  return { success: true };
}

export function setLastError(error: string): void {
  lastError = error;
}
