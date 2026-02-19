import * as crypto from "crypto";
import type { PreHookResult, ToolAuditEvent } from "./types";

// MARK: - Forbidden Patterns

interface ForbiddenPattern {
  pattern: string;
  tools: string[];
  reason: string;
}

const DEFAULT_FORBIDDEN_PATTERNS: ForbiddenPattern[] = [
  { pattern: "rm -rf /", tools: ["shell.execute", "terminal.run"], reason: "Root directory deletion blocked" },
  { pattern: "rm -rf /*", tools: ["shell.execute", "terminal.run"], reason: "Root directory deletion blocked" },
  { pattern: "sudo ", tools: ["shell.execute", "terminal.run"], reason: "Privileged command blocked" },
  { pattern: "mkfs", tools: ["shell.execute", "terminal.run"], reason: "Filesystem format blocked" },
  { pattern: "> /dev/sda", tools: ["shell.execute", "terminal.run"], reason: "Direct disk write blocked" },
  { pattern: ":(){ :|:&};:", tools: ["shell.execute", "terminal.run"], reason: "Fork bomb blocked" },
  { pattern: "chmod -R 777 /", tools: ["shell.execute", "terminal.run"], reason: "Broad permission change blocked" },
  { pattern: "shutdown", tools: ["shell.execute", "terminal.run"], reason: "System shutdown blocked" },
  { pattern: "reboot", tools: ["shell.execute", "terminal.run"], reason: "System reboot blocked" },
];

// MARK: - Audit Log

const auditLog: ToolAuditEvent[] = [];

/**
 * Record a tool execution event in the audit log.
 */
export function recordAudit(event: ToolAuditEvent): void {
  auditLog.push(event);
  console.error(
    `[audit] ${event.toolName} → ${event.decision} (${event.latencyMs}ms)${event.hookName ? ` hook=${event.hookName}` : ""}`,
  );
}

/**
 * Get audit log entries for a session.
 */
export function getSessionAuditLog(sessionId: string): ToolAuditEvent[] {
  return auditLog.filter((e) => e.sessionId === sessionId);
}

/**
 * Flush audit log for a session (logs summary then clears entries).
 */
export function flushSessionAudit(sessionId: string): void {
  const events = auditLog.filter((e) => e.sessionId === sessionId);
  if (events.length === 0) return;

  const allowed = events.filter((e) => e.decision === "allowed").length;
  const approved = events.filter((e) => e.decision === "approved").length;
  const denied = events.filter((e) => e.decision === "denied").length;
  const blocked = events.filter((e) => e.decision === "hookBlocked" || e.decision === "policyBlocked").length;
  const avgLatency = Math.round(events.reduce((sum, e) => sum + e.latencyMs, 0) / events.length);

  console.error(
    `[audit] flush session=${sessionId}: ${events.length} events — ` +
      `allowed=${allowed}, approved=${approved}, denied=${denied}, blocked=${blocked}, avgLatency=${avgLatency}ms`,
  );

  // Remove flushed entries
  const remaining = auditLog.filter((e) => e.sessionId !== sessionId);
  auditLog.length = 0;
  auditLog.push(...remaining);
}

/**
 * Flush all audit log entries (on runtime stop).
 */
export function flushAllAudit(): void {
  if (auditLog.length === 0) return;

  const sessions = new Set(auditLog.map((e) => e.sessionId));
  const errors = auditLog.filter((e) => e.resultCode != null).length;

  console.error(
    `[audit] flush all: ${auditLog.length} events across ${sessions.size} sessions, ${errors} errors`,
  );
  auditLog.length = 0;
}

// MARK: - PreToolUse Hook

/**
 * Run pre-tool-use hooks: forbidden pattern check.
 */
export function runPreToolHooks(
  toolName: string,
  args: Record<string, unknown>,
): PreHookResult {
  // Check forbidden patterns
  for (const fp of DEFAULT_FORBIDDEN_PATTERNS) {
    if (fp.tools.length > 0 && !fp.tools.includes(toolName)) continue;

    for (const val of Object.values(args)) {
      if (typeof val === "string" && val.toLowerCase().includes(fp.pattern.toLowerCase())) {
        return {
          decision: "block",
          hookName: "ForbiddenPattern",
          reason: fp.reason,
        };
      }
    }
  }

  return { decision: "allow" };
}

// MARK: - Arguments Hash

/**
 * Compute a short SHA-256 hash of tool arguments for audit logging.
 */
export function argumentsHash(args: Record<string, unknown>): string {
  const keys = Object.keys(args).sort();
  if (keys.length === 0) return "";
  const parts = keys.map((k) => `${k}=${String(args[k])}`);
  const joined = parts.join("&");
  return crypto.createHash("sha256").update(joined).digest("hex").slice(0, 16);
}
