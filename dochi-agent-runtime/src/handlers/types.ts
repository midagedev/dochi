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

// JSON-RPC error codes
export const PARSE_ERROR = -32700;
export const INVALID_REQUEST = -32600;
export const METHOD_NOT_FOUND = -32601;
export const INVALID_PARAMS = -32602;
export const INTERNAL_ERROR = -32603;
