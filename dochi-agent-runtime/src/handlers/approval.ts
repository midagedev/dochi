import * as crypto from "crypto";
import type * as net from "net";
import type { ApprovalResolveParams, ApprovalResolveAck } from "./types";
import { TOOL_PERMISSION_DENIED } from "./types";

/** Tracks a pending approval awaiting user decision from the app. */
interface PendingApproval {
  approvalId: string;
  toolCallId: string;
  sessionId: string;
  toolName: string;
  riskLevel: string;
  requestedAt: number;
  timeoutMs: number;
  timer: ReturnType<typeof setTimeout>;
  resolve: (result: { approved: boolean; scope: string }) => void;
}

/** Approval timeout: 30 seconds (matches app-side banner timeout). */
const APPROVAL_TIMEOUT_MS = 30_000;

/** In-memory map of pending approvals keyed by approvalId. */
const pendingApprovals = new Map<string, PendingApproval>();

/** Session-scoped approvals: toolName → true (approved for rest of session). */
const sessionApprovals = new Map<string, Set<string>>();

/**
 * Check if a tool has a session-scoped approval.
 */
export function hasSessionApproval(sessionId: string, toolName: string): boolean {
  return sessionApprovals.get(sessionId)?.has(toolName) ?? false;
}

/**
 * Request approval from the app for a sensitive/restricted tool.
 * Sends an approval.required bridge event and waits for approval.resolve RPC.
 */
export function requestApproval(
  conn: net.Socket,
  params: {
    toolCallId: string;
    sessionId: string;
    toolName: string;
    riskLevel: string;
    reason: string;
    argumentsSummary: string;
  },
): Promise<{ approved: boolean; scope: string }> {
  // Check session-scoped approval first
  if (hasSessionApproval(params.sessionId, params.toolName)) {
    console.error(
      `[approval] session-scoped approval found for ${params.toolName} in ${params.sessionId}`,
    );
    return Promise.resolve({ approved: true, scope: "session" });
  }

  const approvalId = crypto.randomUUID();

  return new Promise<{ approved: boolean; scope: string }>((resolve) => {
    const timer = setTimeout(() => {
      pendingApprovals.delete(approvalId);
      console.error(`[approval] timeout for ${params.toolName} (${approvalId})`);
      resolve({ approved: false, scope: "once" });
    }, APPROVAL_TIMEOUT_MS);

    pendingApprovals.set(approvalId, {
      approvalId,
      toolCallId: params.toolCallId,
      sessionId: params.sessionId,
      toolName: params.toolName,
      riskLevel: params.riskLevel,
      requestedAt: Date.now(),
      timeoutMs: APPROVAL_TIMEOUT_MS,
      timer,
      resolve,
    });

    // Send approval.required notification to the app
    const notification = {
      jsonrpc: "2.0",
      method: "bridge.event",
      params: {
        eventId: crypto.randomUUID(),
        timestamp: new Date().toISOString(),
        sessionId: params.sessionId,
        eventType: "approval.required",
        payload: {
          approvalId,
          toolCallId: params.toolCallId,
          toolName: params.toolName,
          riskLevel: params.riskLevel,
          reason: params.reason,
          argumentsSummary: params.argumentsSummary,
        },
      },
    };

    conn.write(JSON.stringify(notification) + "\n");
    console.error(
      `[approval] requested approval for ${params.toolName} (${approvalId}), risk=${params.riskLevel}`,
    );
  });
}

/**
 * Handle `approval.resolve` RPC from the app.
 */
export function handleApprovalResolve(params: ApprovalResolveParams): ApprovalResolveAck {
  const pending = pendingApprovals.get(params.approvalId);
  if (!pending) {
    console.error(`[approval] received resolve for unknown approvalId: ${params.approvalId}`);
    return { received: false, approvalId: params.approvalId };
  }

  clearTimeout(pending.timer);
  pendingApprovals.delete(params.approvalId);

  // Record session-scoped approval
  if (params.approved && params.scope === "session") {
    if (!sessionApprovals.has(pending.sessionId)) {
      sessionApprovals.set(pending.sessionId, new Set());
    }
    sessionApprovals.get(pending.sessionId)!.add(pending.toolName);
    console.error(
      `[approval] session-scoped approval granted for ${pending.toolName} in ${pending.sessionId}`,
    );
  }

  pending.resolve({ approved: params.approved, scope: params.scope });

  console.error(
    `[approval] resolved ${pending.toolName} (${params.approvalId}): approved=${params.approved}, scope=${params.scope}`,
  );

  return { received: true, approvalId: params.approvalId };
}

/**
 * Cancel all pending approvals for a session.
 */
export function cancelPendingApprovals(sessionId: string): number {
  let cancelled = 0;
  for (const [id, pending] of pendingApprovals) {
    if (pending.sessionId === sessionId) {
      clearTimeout(pending.timer);
      pending.resolve({ approved: false, scope: "once" });
      pendingApprovals.delete(id);
      cancelled++;
    }
  }
  // Clear session-scoped approvals
  sessionApprovals.delete(sessionId);
  return cancelled;
}
