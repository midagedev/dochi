// JSON-RPC 2.0 types

export interface JsonRpcRequest {
  jsonrpc: "2.0";
  id: string | number;
  method: string;
  params?: Record<string, unknown>;
}

export interface JsonRpcResponse {
  jsonrpc: "2.0";
  id: string | number;
  result?: unknown;
  error?: JsonRpcError;
}

export interface JsonRpcError {
  code: number;
  message: string;
  data?: unknown;
}

// Runtime handler types

export interface InitializeParams {
  runtimeVersion: string;
  configProfile: string;
}

export interface InitializeResult {
  capabilities: string[];
  runtimeSessionId: string;
}

export interface HealthResult {
  alive: boolean;
  uptimeMs: number;
  activeSessions: number;
  lastError: string | null;
}

export interface ShutdownResult {
  success: boolean;
}

// Session handler types

export interface SessionOpenParams {
  workspaceId: string;
  agentId: string;
  conversationId: string;
  userId: string;
  deviceId?: string;
  sdkSessionId?: string;
}

export interface SessionOpenResult {
  sessionId: string;
  sdkSessionId: string;
  created: boolean;
}

export interface SessionRunParams {
  sessionId: string;
  input: string;
  contextSnapshotRef?: string;
  permissionMode?: string;
}

export interface SessionRunResult {
  accepted: boolean;
  sessionId: string;
}

export interface SessionInterruptParams {
  sessionId: string;
}

export interface SessionInterruptResult {
  interrupted: boolean;
  sessionId: string;
}

export interface SessionCloseParams {
  sessionId: string;
}

export interface SessionCloseResult {
  closed: boolean;
  sessionId: string;
}

export interface SessionListResult {
  sessions: SessionSummary[];
}

export interface SessionSummary {
  sessionId: string;
  sdkSessionId: string;
  workspaceId: string;
  agentId: string;
  conversationId: string;
  status: string;
  createdAt: string;
}

export interface SessionEntry {
  sessionId: string;
  sdkSessionId: string;
  workspaceId: string;
  agentId: string;
  conversationId: string;
  deviceId: string;
  status: "active" | "closed" | "interrupted";
  lookupKey: string;
  createdAt: string;
  lastActiveAt: string;
}

// Event envelope

export interface BridgeEvent {
  eventId: string;
  timestamp: string;
  sessionId?: string;
  workspaceId?: string;
  agentId?: string;
  eventType: string;
  payload?: unknown;
}

// JSON-RPC error codes (standard)
export const PARSE_ERROR = -32700;
export const INVALID_REQUEST = -32600;
export const METHOD_NOT_FOUND = -32601;
export const INVALID_PARAMS = -32602;
export const INTERNAL_ERROR = -32603;

// Dochi-specific error codes
export const SESSION_NOT_FOUND = -32001;
export const SESSION_ALREADY_CLOSED = -32002;
export const RUNTIME_NOT_READY = -32003;
export const SESSION_LIMIT_EXCEEDED = -32004;
