# Data Overview (Conceptual)

High‑level entities and relationships (no storage specifics).

## Entities
- User: human identity; may have aliases; owns personal memory.
- Workspace: shared context for a purpose (family, team); contains agents and shared memory; has members.
- Agent: named assistant with persona, wake word, optional default model; scoped within a workspace.
- Memory:
  - Workspace memory: shared facts relevant to workspace.
  - Agent memory: agent‑specific accumulated notes in a workspace.
  - Personal memory: private, owned by a user, usable across workspaces.
- Conversation: ordered messages between user and agent; may include tool invocations and summaries.
- Message: system/user/assistant/tool content; may include images and tool calls.
- Device: a runtime peer capable of executing actions (voice, tools, UI), associated to a user and workspace.

## Relationships (informal)
- Workspace 1‑N Agents, 1‑N Members, 1‑N Conversations.
- User N‑M Workspaces (via membership); 1‑N Devices; 1 Personal Memory.
- Agent 1‑N Conversations; 1 persona; 1 memory per workspace.

## Retention & Size Guidelines
- Keep memories human‑readable and line‑oriented; prefer append and safe updates.
- Apply summarization/roll‑ups when files grow beyond configured limits.
- Allow manual edits with preview and confirmation for bulk changes.

## Visibility (Conceptual)
- Personal memory: visible to its owner; not shared across users.
- Workspace memory: visible to workspace members; not exposed to remote interfaces without opt‑in redaction.
- Agent memory: scoped to an agent within a workspace; used to specialize behavior.
