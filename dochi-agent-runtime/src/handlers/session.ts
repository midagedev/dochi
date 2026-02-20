import * as crypto from "crypto";
import type {
  SessionOpenParams,
  SessionOpenResult,
  SessionRunParams,
  SessionRunResult,
  SessionInterruptParams,
  SessionInterruptResult,
  SessionCloseParams,
  SessionCloseResult,
  SessionListResult,
  SessionEntry,
} from "./types";
import {
  RpcError,
  SESSION_NOT_FOUND,
  SESSION_ALREADY_CLOSED,
  INVALID_PARAMS,
} from "../errors/rpc-error";

// In-memory session store
const sessions = new Map<string, SessionEntry>();

export function handleSessionOpen(params: SessionOpenParams): SessionOpenResult {
  if (!params.workspaceId || !params.agentId || !params.conversationId || !params.userId) {
    throw new RpcError(
      INVALID_PARAMS,
      "session.open requires workspaceId, agentId, conversationId, and userId",
    );
  }

  // Build lookup key (deviceId excluded for cross-device resume — Issue #291)
  // Uses `:` separator — must match Swift SessionResumeService.normalizeSessionKey
  const lookupKey = `${params.workspaceId}:${params.agentId}:${params.conversationId}`;

  // Check for existing active session with same key
  for (const [, entry] of sessions) {
    if (entry.lookupKey === lookupKey && entry.status === "active") {
      entry.lastActiveAt = new Date().toISOString();
      console.error(`[session] reusing existing session ${entry.sessionId} for key ${lookupKey}`);
      return {
        sessionId: entry.sessionId,
        sdkSessionId: entry.sdkSessionId,
        created: false,
      };
    }
  }

  // Create new session
  const sessionId = crypto.randomUUID();
  const sdkSessionId = params.sdkSessionId ?? crypto.randomUUID();
  const now = new Date().toISOString();

  const entry: SessionEntry = {
    sessionId,
    sdkSessionId,
    workspaceId: params.workspaceId,
    agentId: params.agentId,
    conversationId: params.conversationId,
    userId: params.userId,
    deviceId: params.deviceId ?? "",
    status: "active",
    lookupKey,
    createdAt: now,
    lastActiveAt: now,
  };

  sessions.set(sessionId, entry);
  console.error(`[session] opened new session ${sessionId} (sdk: ${sdkSessionId})`);

  return { sessionId, sdkSessionId, created: true };
}

export function handleSessionRun(params: SessionRunParams): SessionRunResult {
  const entry = sessions.get(params.sessionId);
  if (!entry) {
    throw new RpcError(SESSION_NOT_FOUND, `Session not found: ${params.sessionId}`);
  }
  if (entry.status !== "active") {
    throw new RpcError(SESSION_ALREADY_CLOSED, `Session is ${entry.status}: ${params.sessionId}`);
  }

  entry.lastActiveAt = new Date().toISOString();
  console.error(`[session] run accepted for ${params.sessionId}: "${params.input.slice(0, 50)}..."`);

  return { accepted: true, sessionId: params.sessionId };
}

export function handleSessionInterrupt(params: SessionInterruptParams): SessionInterruptResult {
  const entry = sessions.get(params.sessionId);
  if (!entry) {
    throw new RpcError(SESSION_NOT_FOUND, `Session not found: ${params.sessionId}`);
  }

  entry.status = "interrupted";
  entry.lastActiveAt = new Date().toISOString();
  console.error(`[session] interrupted ${params.sessionId}`);

  return { interrupted: true, sessionId: params.sessionId };
}

export function handleSessionClose(params: SessionCloseParams): SessionCloseResult {
  const entry = sessions.get(params.sessionId);
  if (!entry) {
    throw new RpcError(SESSION_NOT_FOUND, `Session not found: ${params.sessionId}`);
  }

  entry.status = "closed";
  entry.lastActiveAt = new Date().toISOString();
  console.error(`[session] closed ${params.sessionId}`);

  return { closed: true, sessionId: params.sessionId };
}

export function handleSessionList(): SessionListResult {
  const summaries = Array.from(sessions.values()).map((entry) => ({
    sessionId: entry.sessionId,
    sdkSessionId: entry.sdkSessionId,
    workspaceId: entry.workspaceId,
    agentId: entry.agentId,
    conversationId: entry.conversationId,
    status: entry.status,
    createdAt: entry.createdAt,
  }));

  return { sessions: summaries };
}

export function getActiveSessionCount(): number {
  let count = 0;
  for (const entry of sessions.values()) {
    if (entry.status === "active") count++;
  }
  return count;
}
