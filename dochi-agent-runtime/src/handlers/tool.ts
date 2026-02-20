import * as crypto from "crypto";
import type * as net from "net";
import type {
  ToolDispatchParams,
  ToolResultParams,
  ToolResultAck,
} from "./types";
import { TOOL_TIMEOUT, TOOL_NOT_FOUND, RpcError } from "../errors/rpc-error";

/** Tracks a pending tool dispatch awaiting a result from the app. */
interface PendingToolDispatch {
  toolCallId: string;
  sessionId: string;
  toolName: string;
  dispatchedAt: number;
  timeoutMs: number;
  timer: ReturnType<typeof setTimeout>;
  resolve: (result: ToolResultParams) => void;
}

/** Default timeout per risk level (ms). */
const TIMEOUT_BY_RISK: Record<string, number> = {
  safe: 30_000,
  sensitive: 60_000,
  restricted: 120_000,
};

/** In-memory map of pending tool dispatches keyed by toolCallId. */
const pendingDispatches = new Map<string, PendingToolDispatch>();

/**
 * Dispatch a tool call to the app via a `tool.dispatch` bridge event notification.
 * Returns a promise that resolves when the app sends back `tool.result`.
 */
export function dispatchToolToApp(
  conn: net.Socket,
  params: ToolDispatchParams,
): Promise<ToolResultParams> {
  const timeoutMs = TIMEOUT_BY_RISK[params.riskLevel] ?? TIMEOUT_BY_RISK.safe;

  return new Promise<ToolResultParams>((resolve) => {
    const timer = setTimeout(() => {
      // Timeout: resolve with error result
      pendingDispatches.delete(params.toolCallId);
      resolve({
        toolCallId: params.toolCallId,
        sessionId: params.sessionId,
        success: false,
        content: `Tool '${params.toolName}' timed out after ${timeoutMs}ms`,
        errorCode: TOOL_TIMEOUT,
      });
    }, timeoutMs);

    pendingDispatches.set(params.toolCallId, {
      toolCallId: params.toolCallId,
      sessionId: params.sessionId,
      toolName: params.toolName,
      dispatchedAt: Date.now(),
      timeoutMs,
      timer,
      resolve,
    });

    // Send tool.dispatch notification to the app
    const notification = {
      jsonrpc: "2.0",
      method: "bridge.event",
      params: {
        eventId: crypto.randomUUID(),
        timestamp: new Date().toISOString(),
        sessionId: params.sessionId,
        eventType: "tool.dispatch",
        payload: {
          toolCallId: params.toolCallId,
          toolName: params.toolName,
          arguments: params.arguments,
          riskLevel: params.riskLevel,
        },
      },
    };

    conn.write(JSON.stringify(notification) + "\n");
    console.error(
      `[tool] dispatched ${params.toolName} (${params.toolCallId}) to app, timeout=${timeoutMs}ms`,
    );
  });
}

/**
 * Handle `tool.result` RPC from the app.
 * Resolves the pending dispatch promise.
 */
export function handleToolResult(params: ToolResultParams): ToolResultAck {
  const pending = pendingDispatches.get(params.toolCallId);
  if (!pending) {
    throw new RpcError(
      TOOL_NOT_FOUND,
      `No pending tool dispatch for toolCallId: ${params.toolCallId}`,
      { toolCallId: params.toolCallId },
    );
  }

  clearTimeout(pending.timer);
  pendingDispatches.delete(params.toolCallId);
  pending.resolve(params);

  console.error(
    `[tool] received result for ${pending.toolName} (${params.toolCallId}): success=${params.success}`,
  );

  return { received: true, toolCallId: params.toolCallId };
}

/**
 * Cancel all pending dispatches for a session (e.g., on interrupt/close).
 */
export function cancelPendingDispatches(sessionId: string): number {
  let cancelled = 0;
  for (const [id, pending] of pendingDispatches) {
    if (pending.sessionId === sessionId) {
      clearTimeout(pending.timer);
      pending.resolve({
        toolCallId: pending.toolCallId,
        sessionId,
        success: false,
        content: "Tool dispatch cancelled: session interrupted",
        errorCode: TOOL_TIMEOUT,
      });
      pendingDispatches.delete(id);
      cancelled++;
    }
  }
  return cancelled;
}
