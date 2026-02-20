import type { JsonRpcError } from "../handlers/types";

// JSON-RPC 2.0 standard error codes
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
export const TOOL_NOT_FOUND = -32010;
export const TOOL_EXECUTION_FAILED = -32011;
export const TOOL_TIMEOUT = -32012;
export const TOOL_PERMISSION_DENIED = -32013;
export const TOOL_HOOK_BLOCKED = -32014;
export const APPROVAL_NOT_FOUND = -32020;
export const CONTEXT_NOT_FOUND = -32030;

/**
 * Structured RPC error class for type-safe error handling in handlers.
 *
 * Throw `new RpcError(code, message)` from any handler to produce a
 * well-formed JSON-RPC error response. The `rpc-server` catches these
 * via `instanceof RpcError` and maps them directly to {@link JsonRpcError}.
 *
 * @example
 * ```ts
 * throw new RpcError(SESSION_NOT_FOUND, `Session not found: ${id}`);
 * throw new RpcError(TOOL_TIMEOUT, "Timed out", { toolCallId, elapsed });
 * ```
 */
export class RpcError extends Error {
  readonly code: number;
  readonly data?: unknown;

  constructor(code: number, message: string, data?: unknown) {
    super(message);
    this.name = "RpcError";
    this.code = code;
    this.data = data;
    // Restore prototype chain broken by extending built-in Error
    Object.setPrototypeOf(this, RpcError.prototype);
  }

  /** Convert to the JSON-RPC error envelope shape. */
  toJsonRpcError(): JsonRpcError {
    const err: JsonRpcError = { code: this.code, message: this.message };
    if (this.data !== undefined) {
      err.data = this.data;
    }
    return err;
  }
}
