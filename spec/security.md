# Security & Privacy (High‑Level)

## Principles
- Local‑first execution: tools and audio run on the device when possible; cloud used for synchronization only.
- Least privilege: agents have scoped permissions; sensitive actions require explicit user confirmation.
- Transparency: surface what data is sent to external services and why.

## Secrets & Credentials
- API keys and tokens are stored securely and masked in UI; avoid logging secrets.
- External services (LLMs, search, image generation, messaging) are opt‑in.

## Risky Operations
- Permission taxonomy:
  - Safe: read‑only queries, reminders, alarms, web/image generation, printing.
  - Sensitive: profile/context edits, workspace/agent management, device selection.
  - Restricted‑remote: file/system control, shell execution, external app control.
- Remote defaults: only Safe by default; Sensitive require explicit opt‑in; Restricted‑remote disabled.
- Confirmation rules: Sensitive/Restricted actions require explicit user confirmation (in‑app); remote confirmations must be re‑verified in app before execution.
- Model/tool outputs are validated for allowed operations and arguments before execution.

## Data Handling
- Personal memory is private to the user; workspace memory is visible to members only.
- Logs and telemetry (if enabled) minimize PII and are local by default.
- Redaction: messages and tool results shown to remote interfaces may redact local paths, usernames, tokens, or device identifiers.
