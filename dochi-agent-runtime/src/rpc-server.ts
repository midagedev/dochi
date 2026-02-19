import * as net from "net";
import * as fs from "fs";
import * as crypto from "crypto";
import {
  type JsonRpcRequest,
  type JsonRpcResponse,
  METHOD_NOT_FOUND,
  PARSE_ERROR,
  INTERNAL_ERROR,
} from "./handlers/types";
import {
  handleInitialize,
  handleHealth,
  handleShutdown,
  setLastError,
} from "./handlers/runtime";
import {
  handleSessionOpen,
  handleSessionRun,
  handleSessionInterrupt,
  handleSessionClose,
  handleSessionList,
} from "./handlers/session";
import {
  handleToolResult,
  dispatchToolToApp,
  cancelPendingDispatches,
} from "./handlers/tool";
import type {
  SessionOpenParams,
  SessionRunParams,
  SessionInterruptParams,
  SessionCloseParams,
  ToolResultParams,
} from "./handlers/types";

type Handler = (params?: Record<string, unknown>) => unknown;

const handlers: Record<string, Handler> = {
  "runtime.initialize": (params) =>
    handleInitialize(params as { runtimeVersion: string; configProfile: string }),
  "runtime.health": () => handleHealth(),
  "runtime.shutdown": () => handleShutdown(),
  "session.open": (params) => handleSessionOpen(params as unknown as SessionOpenParams),
  "session.run": (params) => handleSessionRun(params as unknown as SessionRunParams),
  "session.interrupt": (params) => handleSessionInterrupt(params as unknown as SessionInterruptParams),
  "session.close": (params) => handleSessionClose(params as unknown as SessionCloseParams),
  "session.list": () => handleSessionList(),
  "tool.result": (params) => handleToolResult(params as unknown as ToolResultParams),
};

function processRequest(request: JsonRpcRequest): JsonRpcResponse {
  const handler = handlers[request.method];
  if (!handler) {
    return {
      jsonrpc: "2.0",
      id: request.id,
      error: {
        code: METHOD_NOT_FOUND,
        message: `Method not found: ${request.method}`,
      },
    };
  }

  try {
    const result = handler(request.params);
    return { jsonrpc: "2.0", id: request.id, result };
  } catch (err) {
    // Support structured error objects { code, message } from handlers
    if (typeof err === "object" && err !== null && "code" in err && "message" in err) {
      const structured = err as { code: number; message: string };
      setLastError(structured.message);
      return {
        jsonrpc: "2.0",
        id: request.id,
        error: { code: structured.code, message: structured.message },
      };
    }
    const message = err instanceof Error ? err.message : String(err);
    setLastError(message);
    return {
      jsonrpc: "2.0",
      id: request.id,
      error: { code: INTERNAL_ERROR, message },
    };
  }
}

/**
 * Emit stub streaming events for session.run (echo mode).
 * Sends the input text back as partial deltas.
 * If input contains "tool:" prefix, dispatches a tool call to the app.
 */
async function emitSessionRunEvents(conn: net.Socket, params: SessionRunParams): Promise<void> {
  const sessionId = params.sessionId;
  const input = params.input;

  // Tool dispatch mode: "tool:toolName arg1 arg2"
  const toolMatch = input.match(/^tool:(\S+)\s*(.*)/);
  if (toolMatch) {
    await emitToolDispatchFlow(conn, sessionId, toolMatch[1], toolMatch[2]);
    return;
  }

  const words = input.split(/\s+/).filter((w) => w.length > 0);

  if (words.length === 0) {
    const notification = {
      jsonrpc: "2.0",
      method: "bridge.event",
      params: {
        eventId: crypto.randomUUID(),
        timestamp: new Date().toISOString(),
        sessionId,
        eventType: "session.completed",
        payload: { text: "" },
      },
    };
    conn.write(JSON.stringify(notification) + "\n");
    return;
  }

  let accumulated = "";
  let delay = 0;

  for (const word of words) {
    delay += 50;
    const delta = (accumulated ? " " : "") + word;
    accumulated += delta;
    const capturedDelta = delta;

    setTimeout(() => {
      if (conn.destroyed) return;
      const notification = {
        jsonrpc: "2.0",
        method: "bridge.event",
        params: {
          eventId: crypto.randomUUID(),
          timestamp: new Date().toISOString(),
          sessionId,
          eventType: "session.partial",
          payload: { delta: capturedDelta },
        },
      };
      conn.write(JSON.stringify(notification) + "\n");
    }, delay);
  }

  const finalText = accumulated;
  setTimeout(() => {
    if (conn.destroyed) return;
    const notification = {
      jsonrpc: "2.0",
      method: "bridge.event",
      params: {
        eventId: crypto.randomUUID(),
        timestamp: new Date().toISOString(),
        sessionId,
        eventType: "session.completed",
        payload: { text: finalText },
      },
    };
    conn.write(JSON.stringify(notification) + "\n");
  }, delay + 100);
}

/**
 * Emit a tool dispatch flow: tool_call event → tool.dispatch → wait for result → tool_result event → completed.
 */
async function emitToolDispatchFlow(
  conn: net.Socket,
  sessionId: string,
  toolName: string,
  argsStr: string,
): Promise<void> {
  const toolCallId = crypto.randomUUID();

  // Parse simple "key=value" arguments
  const args: Record<string, unknown> = {};
  for (const pair of argsStr.split(/\s+/).filter((s) => s.includes("="))) {
    const [key, ...rest] = pair.split("=");
    args[key] = rest.join("=");
  }

  // 1. Emit session.tool_call event
  conn.write(
    JSON.stringify({
      jsonrpc: "2.0",
      method: "bridge.event",
      params: {
        eventId: crypto.randomUUID(),
        timestamp: new Date().toISOString(),
        sessionId,
        eventType: "session.tool_call",
        payload: { toolName, toolCallId },
      },
    }) + "\n",
  );

  // 2. Dispatch tool to app and wait for result
  const result = await dispatchToolToApp(conn, {
    toolCallId,
    toolName,
    arguments: args,
    sessionId,
    riskLevel: "safe",
  });

  if (conn.destroyed) return;

  // 3. Emit session.tool_result event
  conn.write(
    JSON.stringify({
      jsonrpc: "2.0",
      method: "bridge.event",
      params: {
        eventId: crypto.randomUUID(),
        timestamp: new Date().toISOString(),
        sessionId,
        eventType: "session.tool_result",
        payload: {
          toolCallId,
          content: result.content,
          success: result.success,
        },
      },
    }) + "\n",
  );

  // 4. Emit session.completed with tool result as final text
  conn.write(
    JSON.stringify({
      jsonrpc: "2.0",
      method: "bridge.event",
      params: {
        eventId: crypto.randomUUID(),
        timestamp: new Date().toISOString(),
        sessionId,
        eventType: "session.completed",
        payload: {
          text: result.success
            ? `Tool '${toolName}' result: ${result.content}`
            : `Tool '${toolName}' failed: ${result.content}`,
        },
      },
    }) + "\n",
  );
}

export function createRpcServer(socketPath: string): net.Server {
  // Remove stale socket file
  if (fs.existsSync(socketPath)) {
    fs.unlinkSync(socketPath);
  }

  const server = net.createServer((conn) => {
    let buffer = "";

    conn.on("data", (data) => {
      buffer += data.toString();

      // Process newline-delimited JSON messages
      let newlineIndex: number;
      while ((newlineIndex = buffer.indexOf("\n")) !== -1) {
        const line = buffer.slice(0, newlineIndex).trim();
        buffer = buffer.slice(newlineIndex + 1);

        if (!line) continue;

        let request: JsonRpcRequest;
        try {
          request = JSON.parse(line);
        } catch {
          const response: JsonRpcResponse = {
            jsonrpc: "2.0",
            id: 0,
            error: { code: PARSE_ERROR, message: "Parse error" },
          };
          conn.write(JSON.stringify(response) + "\n");
          continue;
        }

        const response = processRequest(request);
        conn.write(JSON.stringify(response) + "\n");

        // After ack for session.run, emit streaming events (stub echo mode)
        if (request.method === "session.run" && !response.error) {
          // Fire-and-forget: async tool dispatch may await app response
          emitSessionRunEvents(conn, request.params as unknown as SessionRunParams).catch(
            (err) => console.error(`[rpc-server] emitSessionRunEvents error: ${err}`),
          );
        }

        // Cancel pending tool dispatches on session interrupt/close
        if (
          (request.method === "session.interrupt" || request.method === "session.close") &&
          !response.error &&
          request.params
        ) {
          const sid = (request.params as { sessionId?: string }).sessionId;
          if (sid) {
            const cancelled = cancelPendingDispatches(sid);
            if (cancelled > 0) {
              console.error(`[rpc-server] cancelled ${cancelled} pending tool dispatches for ${sid}`);
            }
          }
        }
      }
    });

    conn.on("error", (err) => {
      console.error(`[rpc-server] connection error: ${err.message}`);
    });
  });

  return server;
}
