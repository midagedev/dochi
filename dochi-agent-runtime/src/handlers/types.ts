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
  userId: string;
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

// Tool dispatch types

export interface ToolDispatchParams {
  toolCallId: string;
  toolName: string;
  arguments: Record<string, unknown>;
  sessionId: string;
  riskLevel: "safe" | "sensitive" | "restricted";
}

export interface ToolResultParams {
  toolCallId: string;
  sessionId: string;
  success: boolean;
  content: string;
  errorCode?: number;
}

export interface ToolResultAck {
  received: boolean;
  toolCallId: string;
}

// Approval types

export interface ApprovalRequestParams {
  approvalId: string;
  toolCallId: string;
  sessionId: string;
  toolName: string;
  riskLevel: "sensitive" | "restricted";
  reason: string;
  argumentsSummary: string;
}

export interface ApprovalResolveParams {
  approvalId: string;
  toolCallId: string;
  sessionId: string;
  approved: boolean;
  scope: "once" | "session";
  note?: string;
}

export interface ApprovalResolveAck {
  received: boolean;
  approvalId: string;
}

// Re-export RpcError class and all error codes from the canonical module.
// Handlers may import from either location; the errors module is the source of truth.
export {
  RpcError,
  PARSE_ERROR,
  INVALID_REQUEST,
  METHOD_NOT_FOUND,
  INVALID_PARAMS,
  INTERNAL_ERROR,
  SESSION_NOT_FOUND,
  SESSION_ALREADY_CLOSED,
  RUNTIME_NOT_READY,
  SESSION_LIMIT_EXCEEDED,
  TOOL_NOT_FOUND,
  TOOL_EXECUTION_FAILED,
  TOOL_TIMEOUT,
  TOOL_PERMISSION_DENIED,
  TOOL_HOOK_BLOCKED,
  APPROVAL_NOT_FOUND,
  CONTEXT_NOT_FOUND,
} from "../errors/rpc-error";

// Context snapshot types

export interface ContextPushParams {
  snapshotRef: string;
  snapshot: {
    id: string;
    workspaceId: string;
    agentId: string;
    userId: string;
    layers: {
      systemLayer: { name: string; content: string; truncated: boolean; originalCharCount: number };
      workspaceLayer: { name: string; content: string; truncated: boolean; originalCharCount: number };
      agentLayer: { name: string; content: string; truncated: boolean; originalCharCount: number };
      personalLayer: { name: string; content: string; truncated: boolean; originalCharCount: number };
    };
    tokenEstimate: number;
    createdAt: string;
    sourceRevision: string;
  };
}

export interface ContextResolveParams {
  snapshotRef: string;
}

// Hook types

export type PreHookDecision = "allow" | "block" | "mask";

export interface PreHookResult {
  decision: PreHookDecision;
  hookName?: string;
  reason?: string;
  maskedArguments?: Record<string, unknown>;
}

export interface ToolAuditEvent {
  toolCallId: string;
  sessionId: string;
  agentId?: string;
  toolName: string;
  argumentsHash: string;
  riskLevel: string;
  decision: "allowed" | "approved" | "denied" | "timeout" | "policyBlocked" | "hookBlocked";
  hookName?: string;
  latencyMs: number;
  resultCode?: number;
  timestamp: string;
}
