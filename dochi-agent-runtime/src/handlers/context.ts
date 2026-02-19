/**
 * Context snapshot store and handlers for the runtime.
 *
 * The app pushes context snapshots via `context.push` before calling
 * `session.run`. The runtime stores them and references them by
 * `snapshotRef` during agent execution.
 */

export interface ContextLayer {
  name: "system" | "workspace" | "agent" | "personal";
  content: string;
  truncated: boolean;
  originalCharCount: number;
}

export interface ContextLayers {
  systemLayer: ContextLayer;
  workspaceLayer: ContextLayer;
  agentLayer: ContextLayer;
  personalLayer: ContextLayer;
}

export interface ContextSnapshot {
  id: string;
  workspaceId: string;
  agentId: string;
  userId: string;
  layers: ContextLayers;
  tokenEstimate: number;
  createdAt: string;
  sourceRevision: string;
}

export interface ContextPushParams {
  snapshotRef: string;
  snapshot: ContextSnapshot;
}

export interface ContextPushResult {
  stored: boolean;
  snapshotRef: string;
  tokenEstimate: number;
}

export interface ContextResolveParams {
  snapshotRef: string;
}

export interface ContextResolveResult {
  found: boolean;
  snapshot?: ContextSnapshot;
}

// In-memory snapshot store (keyed by snapshotRef)
const snapshots = new Map<string, { snapshot: ContextSnapshot; storedAt: number }>();

// TTL for stored snapshots (1 hour)
const SNAPSHOT_TTL_MS = 3600_000;
const MAX_SNAPSHOTS = 50;

/**
 * Handle `context.push` RPC: store a snapshot from the app.
 */
export function handleContextPush(params: ContextPushParams): ContextPushResult {
  evictExpired();

  // Evict oldest if at capacity
  if (snapshots.size >= MAX_SNAPSHOTS) {
    let oldestKey: string | null = null;
    let oldestTime = Infinity;
    for (const [key, entry] of snapshots) {
      if (entry.storedAt < oldestTime) {
        oldestTime = entry.storedAt;
        oldestKey = key;
      }
    }
    if (oldestKey) {
      snapshots.delete(oldestKey);
    }
  }

  snapshots.set(params.snapshotRef, {
    snapshot: params.snapshot,
    storedAt: Date.now(),
  });

  console.error(
    `[context] stored snapshot ${params.snapshotRef} (tokens≈${params.snapshot.tokenEstimate}, layers=${countActiveLayers(params.snapshot)})`,
  );

  return {
    stored: true,
    snapshotRef: params.snapshotRef,
    tokenEstimate: params.snapshot.tokenEstimate,
  };
}

/**
 * Handle `context.resolve` RPC: retrieve a stored snapshot.
 */
export function handleContextResolve(params: ContextResolveParams): ContextResolveResult {
  const entry = snapshots.get(params.snapshotRef);
  if (!entry) {
    return { found: false };
  }

  // Check TTL
  if (Date.now() - entry.storedAt > SNAPSHOT_TTL_MS) {
    snapshots.delete(params.snapshotRef);
    return { found: false };
  }

  return { found: true, snapshot: entry.snapshot };
}

/**
 * Get the combined context text for a snapshot ref (for agent system prompt injection).
 */
export function getSnapshotText(snapshotRef: string): string | null {
  const result = handleContextResolve({ snapshotRef });
  if (!result.found || !result.snapshot) return null;

  const layers = result.snapshot.layers;
  const parts: string[] = [];

  for (const layer of [layers.systemLayer, layers.workspaceLayer, layers.agentLayer, layers.personalLayer]) {
    if (layer.content.length > 0) {
      parts.push(layer.content);
    }
  }

  return parts.join("\n\n");
}

/**
 * Remove all snapshots for a given workspace.
 */
export function removeWorkspaceSnapshots(workspaceId: string): number {
  let removed = 0;
  for (const [key, entry] of snapshots) {
    if (entry.snapshot.workspaceId === workspaceId) {
      snapshots.delete(key);
      removed++;
    }
  }
  return removed;
}

/**
 * Remove a specific snapshot.
 */
export function removeSnapshot(snapshotRef: string): boolean {
  return snapshots.delete(snapshotRef);
}

/**
 * Get current snapshot count.
 */
export function snapshotCount(): number {
  return snapshots.size;
}

// Internal helpers

function evictExpired(): void {
  const now = Date.now();
  for (const [key, entry] of snapshots) {
    if (now - entry.storedAt > SNAPSHOT_TTL_MS) {
      snapshots.delete(key);
    }
  }
}

function countActiveLayers(snapshot: ContextSnapshot): number {
  let count = 0;
  const layers = snapshot.layers;
  if (layers.systemLayer.content.length > 0) count++;
  if (layers.workspaceLayer.content.length > 0) count++;
  if (layers.agentLayer.content.length > 0) count++;
  if (layers.personalLayer.content.length > 0) count++;
  return count;
}
