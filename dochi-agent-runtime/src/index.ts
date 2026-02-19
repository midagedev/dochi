import { createRpcServer } from "./rpc-server";

const SOCKET_PATH = process.env.DOCHI_RUNTIME_SOCKET ?? "/tmp/dochi-runtime.sock";

const server = createRpcServer(SOCKET_PATH);

server.listen(SOCKET_PATH, () => {
  console.error(`[runtime] listening on ${SOCKET_PATH}`);
  // Emit ready event to stdout for parent process detection
  const readyEvent = JSON.stringify({
    jsonrpc: "2.0",
    method: "runtime.ready",
    params: { socketPath: SOCKET_PATH, pid: process.pid },
  });
  process.stdout.write(readyEvent + "\n");
});

server.on("error", (err) => {
  console.error(`[runtime] server error: ${err.message}`);
  process.exit(1);
});

// Graceful shutdown on SIGTERM/SIGINT
function shutdown() {
  console.error("[runtime] shutting down...");
  server.close(() => {
    process.exit(0);
  });
  // Force exit after 5 seconds
  setTimeout(() => process.exit(1), 5000);
}

process.on("SIGTERM", shutdown);
process.on("SIGINT", shutdown);
