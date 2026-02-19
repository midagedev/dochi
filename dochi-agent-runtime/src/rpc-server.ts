import * as net from "net";
import * as fs from "fs";
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

type Handler = (params?: Record<string, unknown>) => unknown;

const handlers: Record<string, Handler> = {
  "runtime.initialize": (params) =>
    handleInitialize(params as { runtimeVersion: string; configProfile: string }),
  "runtime.health": () => handleHealth(),
  "runtime.shutdown": () => handleShutdown(),
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
    const message = err instanceof Error ? err.message : String(err);
    setLastError(message);
    return {
      jsonrpc: "2.0",
      id: request.id,
      error: { code: INTERNAL_ERROR, message },
    };
  }
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
      }
    });

    conn.on("error", (err) => {
      console.error(`[rpc-server] connection error: ${err.message}`);
    });
  });

  return server;
}
